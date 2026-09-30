import Foundation

/// Registro persistente para diagnosticar problemas sin reproducirlos: arranque y
/// configuración del gateway, peticiones, sesiones, runner y decisiones de la app.
///
/// Escribe una línea por evento en `~/Library/Logs/CuyScout/<nombre>.log` (se ve en
/// Consola.app) y rota a `.1` al pasar 5 MB. Nunca registra tokens, cuerpos de petición ni
/// textos escritos: solo metadatos. `CUYSCOUT_LOG_DIR` cambia la carpeta y
/// `CUYSCOUT_LOG_LEVEL=debug` agrega el detalle fino.
public final class ScoutLog: @unchecked Sendable {
    public enum Level: Int, Comparable, Sendable {
        case debug, info, warning, error
        public static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }
        var tag: String { ["DEBUG", "INFO", "WARN", "ERROR"][rawValue] }
    }

    public static let gateway = ScoutLog(name: "gateway")
    public static let app = ScoutLog(name: "app")

    public let fileURL: URL
    public let minimumLevel: Level
    private let lock = NSLock()
    private let maxBytes: UInt64
    // ISO8601DateFormatter es seguro entre hilos (Formatter), aunque no esté marcado Sendable.
    nonisolated(unsafe) private static let timestamp: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    public static var directory: URL {
        let environment = ProcessInfo.processInfo.environment
        if let custom = environment["CUYSCOUT_LOG_DIR"], !custom.isEmpty { return URL(fileURLWithPath: custom, isDirectory: true) }
        if ArtifactStore.isRunningTests {
            return FileManager.default.temporaryDirectory.appendingPathComponent("cuyscout-test-logs-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/CuyScout", isDirectory: true)
    }

    public init(name: String, directory: URL = ScoutLog.directory, maxBytes: UInt64 = 5_000_000,
                minimumLevel: Level = ProcessInfo.processInfo.environment["CUYSCOUT_LOG_LEVEL"]?.lowercased() == "debug" ? .debug : .info) {
        fileURL = directory.appendingPathComponent("\(name).log")
        self.maxBytes = maxBytes
        self.minimumLevel = minimumLevel
    }

    public func debug(_ category: String, _ message: String, _ fields: [String: Any] = [:]) { write(.debug, category, message, fields) }
    public func info(_ category: String, _ message: String, _ fields: [String: Any] = [:]) { write(.info, category, message, fields) }
    public func warning(_ category: String, _ message: String, _ fields: [String: Any] = [:]) { write(.warning, category, message, fields) }
    public func error(_ category: String, _ message: String, _ fields: [String: Any] = [:]) { write(.error, category, message, fields) }

    /// Línea legible: `fecha NIVEL [categoría] mensaje clave=valor …`.
    static func format(_ level: Level, _ category: String, _ message: String, _ fields: [String: Any], date: Date = Date()) -> String {
        let extras = fields.keys.sorted().map { key -> String in
            let value = redact(key: key, value: "\(fields[key] ?? "")").replacingOccurrences(of: "\n", with: " ")
            return value.contains(" ") ? "\(key)=\"\(value)\"" : "\(key)=\(value)"
        }
        let text = redact(key: "", value: message).replacingOccurrences(of: "\n", with: " ")
        return ([timestamp.string(from: date), level.tag, "[\(category)]", text] + extras).joined(separator: " ")
    }

    /// Nada que parezca un secreto llega al archivo, aunque alguien lo pase por error.
    static func redact(key: String, value: String) -> String {
        let lowered = key.lowercased()
        if lowered == "text" || ["token", "password", "secret", "authorization", "clave"].contains(where: { lowered.contains($0) }) { return "<oculto>" }
        return redactValue(value)
    }

    /// Como `LessonRedactor`, pero conserva identificadores útiles para diagnosticar (UDID,
    /// rutas): solo oculta números de 11 dígitos o más (cuentas, tarjetas, documentos largos).
    static func redactValue(_ text: String) -> String {
        var value = text
        let patterns = [
            #"\b[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}\b"#,
            #"(?i)\b(?:bearer\s+)[A-Z0-9._~+/\-]+=*"#,
            #"(?i)\b(?:password|passwd|token|secret|api[_-]?key|clave|contraseña|contrasena)\s*[:=]\s*[^\s,;]+"#,
            #"(?<![0-9A-Fa-f-])\d{11,}(?![0-9A-Fa-f-])"#
        ]
        for pattern in patterns {
            value = value.replacingOccurrences(of: pattern, with: "<oculto>", options: [.regularExpression, .caseInsensitive])
        }
        return value
    }

    private func write(_ level: Level, _ category: String, _ message: String, _ fields: [String: Any]) {
        guard level >= minimumLevel else { return }
        let line = Self.format(level, category, message, fields) + "\n"
        lock.lock(); defer { lock.unlock() }
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let size = (try? fileManager.attributesOfItem(atPath: fileURL.path))?[.size] as? UInt64, size > maxBytes {
            let rotated = fileURL.appendingPathExtension("1")
            try? fileManager.removeItem(at: rotated)
            try? fileManager.moveItem(at: fileURL, to: rotated)
        }
        if !fileManager.fileExists(atPath: fileURL.path) {
            fileManager.createFile(atPath: fileURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(line.utf8))
    }

    /// Últimas `lines` líneas (para `/logs` y el diagnóstico); tras una rotación completa
    /// con el archivo `.1`.
    public func tail(lines: Int = 200) -> [String] {
        let wanted = max(1, min(lines, 2_000))
        lock.lock(); defer { lock.unlock() }
        var result = Self.lastLines(of: fileURL, count: wanted)
        if result.count < wanted {
            result = Self.lastLines(of: fileURL.appendingPathExtension("1"), count: wanted - result.count) + result
        }
        return result
    }

    private static func lastLines(of url: URL, count: Int) -> [String] {
        guard count > 0, let handle = FileHandle(forReadingAtPath: url.path) else { return [] }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let window: UInt64 = 512 * 1024
        try? handle.seek(toOffset: size > window ? size - window : 0)
        let text = String(decoding: handle.readDataToEndOfFile(), as: UTF8.self)
        return Array(text.split(separator: "\n", omittingEmptySubsequences: true).suffix(count).map(String.init))
    }
}

/// Deja pasar un evento repetido como mucho una vez por intervalo.
public final class LogThrottle: @unchecked Sendable {
    private let lock = NSLock()
    private let interval: TimeInterval
    private var last: Date?
    public init(interval: TimeInterval) { self.interval = interval }
    public func shouldLog(now: Date = Date()) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if let last, now.timeIntervalSince(last) < interval { return false }
        last = now
        return true
    }
}
