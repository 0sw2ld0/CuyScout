import Foundation

/// Rastro de un replay para depurarlo sin reproducirlo: cada paso va a `gateway.log` y, si
/// falla, se guarda una carpeta con la captura de la pantalla, sus textos y controles, y el
/// resumen de los pasos (sin lo escrito). Se conservan las últimas 10 carpetas.
final class ReplayDiagnostics: @unchecked Sendable {
    private let sessionID: String
    private var lines: [String] = []
    private let lock = NSLock()

    init(sessionID: String) { self.sessionID = sessionID }

    static var directory: URL { ScoutLog.directory.appendingPathComponent("replays", isDirectory: true) }

    func step(_ number: Int, action: ScoutAction, milliseconds: Int, result: String, note: String) {
        let line = "paso \(number) · \(Self.describe(action)) · \(milliseconds) ms · \(result)\(note.isEmpty ? "" : " · \(note)")"
        lock.lock(); lines.append(line); lock.unlock()
        ScoutLog.gateway.info("replay", line, ["session": sessionID])
    }

    /// Resumen de la acción sin el texto escrito (puede ser una clave).
    static func describe(_ action: ScoutAction) -> String {
        switch action {
        case .tap(let x, let y): return "toque en (\(Int(x)), \(Int(y)))"
        case .tapElement(let selector): return "tocar \(selector.strategy.rawValue)=«\(selector.value)»"
        case .typeElement(let selector, _): return "escribir en \(selector.strategy.rawValue)=«\(selector.value)»"
        case .clearElement(let selector): return "borrar \(selector.strategy.rawValue)=«\(selector.value)»"
        case .waitFor(let selector, _), .assertVisible(let selector): return "esperar \(selector.strategy.rawValue)=«\(selector.value)»"
        case .assertText(let selector, _): return "verificar texto de \(selector.strategy.rawValue)=«\(selector.value)»"
        case .accessibilityTree, .accessibilityTreeWithOptions, .accessibilityDiff: return "observar"
        default: return String(String(describing: action).prefix(60))
        }
    }

    func saveFailure(message: String, screenshot: Data?, tree: Data?) -> URL? {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let folder = Self.directory.appendingPathComponent("\(stamp)-\(sessionID.prefix(8))", isDirectory: true)
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            lock.lock(); let steps = lines.joined(separator: "\n"); lock.unlock()
            try (steps + "\n\n" + message + "\n").write(to: folder.appendingPathComponent("pasos.txt"), atomically: true, encoding: .utf8)
            if let screenshot { try screenshot.write(to: folder.appendingPathComponent("pantalla.png")) }
            if let tree { try Self.screenSummary(tree).write(to: folder.appendingPathComponent("pantalla.txt"), atomically: true, encoding: .utf8) }
            Self.prune(keep: 10)
            ScoutLog.gateway.warning("replay", "Replay fallido; diagnóstico guardado", ["session": sessionID, "carpeta": folder.path])
            return folder
        } catch {
            ScoutLog.gateway.error("replay", "No se pudo guardar el diagnóstico del replay", ["error": error.localizedDescription])
            return nil
        }
    }

    /// Una línea por elemento visible: tipo, texto o identificador y marco. Los valores de los
    /// campos seguros no se incluyen.
    static func screenSummary(_ tree: Data) -> String {
        let elements = ((try? JSONSerialization.jsonObject(with: tree)) as? [String: Any])?["elements"] as? [[String: Any]] ?? []
        return elements.compactMap { element -> String? in
            let type = String(describing: element["type"] ?? "")
            let label = element["label"] as? String ?? ""
            let identifier = element["identifier"] as? String ?? ""
            let value = type.lowercased().contains("secure") ? "" : (element["value"] as? String ?? "")
            guard !label.isEmpty || !identifier.isEmpty || !value.isEmpty, let frame = ScoutEngine.frame(of: element) else { return nil }
            let parts = [identifier.isEmpty ? nil : "id=\(identifier)", label.isEmpty ? nil : "«\(label.prefix(80))»", value.isEmpty ? nil : "valor=«\(value.prefix(40))»"].compactMap { $0 }
            return "\(type) \(parts.joined(separator: " ")) (\(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))×\(Int(frame.height)))"
        }.joined(separator: "\n")
    }

    private static func prune(keep: Int) {
        let fileManager = FileManager.default
        guard let folders = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey]) else { return }
        let sorted = folders.sorted { ($0.lastPathComponent) > ($1.lastPathComponent) }
        for folder in sorted.dropFirst(keep) { try? fileManager.removeItem(at: folder) }
    }
}

/// Video de un replay en simulador (`simctl io recordVideo`, como Maestro).
final class ReplayVideo: @unchecked Sendable {
    private let deviceID: String
    private let path: URL

    private init(deviceID: String, path: URL) { self.deviceID = deviceID; self.path = path }

    /// `nil` en iPhone físico, en las pruebas o con `CUYSCOUT_REPLAY_VIDEO=0`.
    static func start(device: Device, sessionID: String) -> ReplayVideo? {
        guard device.kind != .physical, !ArtifactStore.isRunningTests,
              ProcessInfo.processInfo.environment["CUYSCOUT_REPLAY_VIDEO"] != "0" else { return nil }
        let path = ReplayDiagnostics.directory.appendingPathComponent("en-curso-\(sessionID.prefix(8)).mp4")
        do { try SimulatorVideoRecorder.start(deviceID: device.id, path: path.path) } catch {
            ScoutLog.gateway.warning("replay", "No se pudo grabar el video del replay", ["error": error.localizedDescription])
            return nil
        }
        return ReplayVideo(deviceID: device.id, path: path)
    }

    /// Detiene la grabación. Con carpeta, mueve el video ahí y devuelve su ruta; sin ella lo borra.
    @discardableResult
    func finish(keepIn folder: URL?) -> URL? {
        SimulatorVideoRecorder.stop(deviceID: deviceID)
        let fileManager = FileManager.default
        guard let folder, fileManager.fileExists(atPath: path.path) else { try? fileManager.removeItem(at: path); return nil }
        let destination = folder.appendingPathComponent("video.mp4")
        do { try fileManager.moveItem(at: path, to: destination); return destination } catch { try? fileManager.removeItem(at: path); return nil }
    }
}

/// Resultados recientes de los replays de cada prueba, para distinguir una prueba inestable
/// (pasa y falla sin cambios) de una que se rompió.
enum ReplayHistory {
    struct Entry: Codable { let date: Date; let success: Bool; let failedStep: Int? }
    struct Stability { let label: String; let runs: Int; let passes: Int }

    static let keep = 10
    nonisolated(unsafe) static var file = (ArtifactStore.isRunningTests ? FileManager.default.temporaryDirectory.appendingPathComponent("cuyscout-tests-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true) : ReplayDiagnostics.directory).appendingPathComponent("historial.json")
    private static let lock = NSLock()

    @discardableResult
    static func record(id: String, success: Bool, failedStep: Int?, now: Date = Date()) -> Stability {
        lock.lock(); defer { lock.unlock() }
        var all = (try? JSONDecoder().decode([String: [Entry]].self, from: Data(contentsOf: file))) ?? [:]
        var entries = (all[id] ?? []) + [Entry(date: now, success: success, failedStep: failedStep)]
        entries = Array(entries.suffix(keep))
        all[id] = entries
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(all).write(to: file, options: .atomic)
        return stability(entries)
    }

    static func stability(_ entries: [Entry]) -> Stability {
        let passes = entries.filter(\.success).count
        let label: String
        if entries.count < 2 { label = "nueva" }
        else if passes == entries.count { label = "estable" }
        else if passes == 0 { label = "falla siempre" }
        else { label = "inestable" }
        return Stability(label: label, runs: entries.count, passes: passes)
    }
}
