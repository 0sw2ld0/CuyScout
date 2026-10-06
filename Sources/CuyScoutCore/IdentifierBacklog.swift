import CryptoKit
import Foundation

/// Un elemento de la app que dificulta automatizar: sin `accessibilityIdentifier`, sin texto ni
/// identificador, con un identificador repetido o con un texto que cambia entre corridas.
/// Es el backlog que el equipo de front resuelve agregando identificadores.
public struct IdentifierFinding: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case missingIdentifier = "sin_identificador"
        case noTextNoIdentifier = "sin_texto_ni_identificador"
        case duplicateIdentifier = "identificador_repetido"
        case changingText = "texto_variable"

        public var title: String {
            switch self {
            case .missingIdentifier: "Sin identificador"
            case .noTextNoIdentifier: "Sin texto ni identificador"
            case .duplicateIdentifier: "Identificador repetido"
            case .changingText: "Texto que cambia"
            }
        }
    }
    public enum Status: String, Codable, Sendable { case pending = "pendiente", resolved = "resuelto" }

    public var key: String
    public var kind: Kind
    public var screenKey: String
    public var screen: String
    public var type: String
    /// Texto visible, sin datos personales.
    public var label: String
    public var identifier: String?
    /// x, y, ancho, alto en puntos.
    public var frame: [Double]
    /// Sesión → cómo la usó una prueba («texto» o «coordenadas»). Vacío: solo se vio.
    public var usedBy: [String: String]
    public var timesSeen: Int
    public var firstSeen: Date
    public var lastSeen: Date
    public var status: Status
    public var resolvedIdentifier: String?

    /// Alta si una prueba ya depende de él (por texto o coordenadas): hoy la hace frágil.
    public var isHighPriority: Bool { !usedBy.isEmpty || kind == .duplicateIdentifier }
}

public struct IdentifierScreen: Codable, Sendable, Equatable {
    public var key: String
    public var title: String
    /// Captura guardada junto al backlog (`pantallas/<key>.png`), si se tomó.
    public var screenshot: String?
    /// Ancho de la pantalla en puntos: la captura está en píxeles.
    public var widthPoints: Double
}

public struct IdentifierBacklog: Codable, Sendable, Equatable {
    public var findings: [String: IdentifierFinding] = [:]
    public var screens: [String: IdentifierScreen] = [:]
    /// Identificadores que ya usa la app: de ahí sale la convención para sugerir nombres.
    public var knownIdentifiers: [String] = []
    /// Pantalla + tipo + posición → textos vistos (para detectar textos que cambian).
    public var slotLabels: [String: [String]] = [:]
    public init() {}
}

/// Recolecta el backlog de un proyecto mientras el agente observa y actúa. Se guarda en
/// `<proyecto>/.cuyscout/identificadores/` y no envía nada fuera de la Mac.
public final class IdentifierBacklogStore: @unchecked Sendable {
    public let directory: URL
    private let lock = NSLock()
    private var backlog: IdentifierBacklog

    public init(projectDirectory: URL) {
        directory = projectDirectory.appendingPathComponent(".cuyscout/identificadores", isDirectory: true)
        backlog = (try? Data(contentsOf: directory.appendingPathComponent("backlog.json")))
            .flatMap { try? Self.decoder.decode(IdentifierBacklog.self, from: $0) } ?? IdentifierBacklog()
    }

    public var snapshot: IdentifierBacklog { lock.lock(); defer { lock.unlock() }; return backlog }

    static let interactiveTypes = ["button", "textfield", "securetextfield", "textview", "searchfield", "link", "cell", "switch", "toggle", "slider", "stepper", "checkbox", "menuitem", "picker", "tab"]
    static func isInteractive(_ type: String) -> Bool { let value = type.lowercased(); return interactiveTypes.contains { value.contains($0) } }

    /// Procesa una observación. Devuelve `true` si la pantalla es nueva y conviene guardar su
    /// captura (`saveScreenshot`).
    @discardableResult
    public func observe(elements: [[String: Any]], sessionID: String, now: Date = Date()) -> (screenKey: String, needsScreenshot: Bool) {
        let screen = Self.screenIdentity(elements)
        lock.lock(); defer { lock.unlock() }
        let width = elements.compactMap { ScoutEngine.frame(of: $0)?.maxX }.max() ?? 0
        if backlog.screens[screen.key] == nil { backlog.screens[screen.key] = IdentifierScreen(key: screen.key, title: screen.title, screenshot: nil, widthPoints: width) }

        var identifierCounts: [String: [[String: Any]]] = [:]
        for element in elements {
            let type = String(describing: element["type"] ?? "")
            guard Self.isInteractive(type), let frame = ScoutEngine.frame(of: element) else { continue }
            let identifier = (element["identifier"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let label = Self.redact((element["label"] as? String) ?? "")
            if let identifier {
                identifierCounts[identifier, default: []].append(element)
                if !backlog.knownIdentifiers.contains(identifier) { backlog.knownIdentifiers.append(identifier) }
                // Ya tiene identificador: si estaba en el backlog, queda resuelto.
                for kind in [IdentifierFinding.Kind.missingIdentifier, .noTextNoIdentifier, .changingText] {
                    let key = Self.findingKey(kind: kind, screenKey: screen.key, type: type, label: label, frame: frame)
                    if var finding = backlog.findings[key], finding.status == .pending {
                        finding.status = .resolved; finding.resolvedIdentifier = identifier; finding.lastSeen = now
                        backlog.findings[key] = finding
                    }
                }
                continue
            }
            // Textos que cambian en el mismo lugar (monto, contador, estado).
            let slot = "\(screen.key)|\(type.lowercased())|\(Int(frame.minX / 10))|\(Int(frame.minY / 10))"
            var labels = backlog.slotLabels[slot] ?? []
            if !label.isEmpty, !labels.contains(label) { labels.append(label); backlog.slotLabels[slot] = Array(labels.suffix(5)) }
            let kind: IdentifierFinding.Kind = label.isEmpty ? .noTextNoIdentifier : (labels.count > 1 ? .changingText : .missingIdentifier)
            let shownLabel = kind == .changingText ? Self.pattern(of: labels) : label
            if kind == .changingText {
                // El hallazgo «sin identificador» de ese mismo lugar pasa a ser «texto que cambia».
                for old in labels { backlog.findings.removeValue(forKey: Self.findingKey(kind: .missingIdentifier, screenKey: screen.key, type: type, label: old, frame: frame)) }
            }
            upsert(kind: kind, screen: screen, type: type, label: shownLabel, identifier: nil, frame: frame, sessionID: nil, how: nil, now: now)
        }
        for (identifier, owners) in identifierCounts where owners.count > 1 {
            guard let first = owners.first, let frame = ScoutEngine.frame(of: first) else { continue }
            upsert(kind: .duplicateIdentifier, screen: screen, type: String(describing: first["type"] ?? ""), label: Self.redact((first["label"] as? String) ?? ""),
                   identifier: identifier, frame: frame, sessionID: nil, how: nil, now: now)
        }
        let needsScreenshot = backlog.screens[screen.key]?.screenshot == nil
            && backlog.findings.values.contains { $0.screenKey == screen.key && $0.status == .pending }
        return (screen.key, needsScreenshot)
    }

    /// Una prueba usó un elemento por texto (`label`/`value`) o por coordenadas: sube a prioridad alta.
    public func markUsed(element: [String: Any], elements: [[String: Any]], sessionID: String, how: String, now: Date = Date()) {
        let screen = Self.screenIdentity(elements)
        let type = String(describing: element["type"] ?? "")
        guard let frame = ScoutEngine.frame(of: element) else { return }
        let label = Self.redact((element["label"] as? String) ?? "")
        lock.lock(); defer { lock.unlock() }
        let slot = "\(screen.key)|\(type.lowercased())|\(Int(frame.minX / 10))|\(Int(frame.minY / 10))"
        let labels = backlog.slotLabels[slot] ?? []
        let kind: IdentifierFinding.Kind = label.isEmpty ? .noTextNoIdentifier : (labels.count > 1 ? .changingText : .missingIdentifier)
        upsert(kind: kind, screen: screen, type: type, label: kind == .changingText ? Self.pattern(of: labels) : label,
               identifier: nil, frame: frame, sessionID: sessionID, how: how, now: now)
    }

    public func saveScreenshot(_ png: Data, screenKey: String) {
        lock.lock(); defer { lock.unlock() }
        let folder = directory.appendingPathComponent("pantallas", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Las capturas completas pueden mostrar datos reales: nunca van al repositorio. El
        // informe usa solo recortes con el entorno difuminado.
        let ignore = directory.appendingPathComponent(".gitignore")
        if !FileManager.default.fileExists(atPath: ignore.path) { try? "pantallas/\n".write(to: ignore, atomically: true, encoding: .utf8) }
        let name = "\(screenKey).png"
        guard (try? png.write(to: folder.appendingPathComponent(name))) != nil else { return }
        backlog.screens[screenKey]?.screenshot = "pantallas/\(name)"
    }

    public func save() {
        lock.lock(); let current = backlog; lock.unlock()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? Self.encoder.encode(current) else { return }
        try? data.write(to: directory.appendingPathComponent("backlog.json"), options: .atomic)
    }

    private func upsert(kind: IdentifierFinding.Kind, screen: (key: String, title: String), type: String, label: String, identifier: String?,
                        frame: CGRect, sessionID: String?, how: String?, now: Date) {
        let key = kind == .duplicateIdentifier ? "dup|\(screen.key)|\(identifier ?? "")" : Self.findingKey(kind: kind, screenKey: screen.key, type: type, label: label, frame: frame)
        var finding = backlog.findings[key] ?? IdentifierFinding(
            key: key, kind: kind, screenKey: screen.key, screen: screen.title, type: type, label: label, identifier: identifier,
            frame: [frame.minX, frame.minY, frame.width, frame.height], usedBy: [:], timesSeen: 0, firstSeen: now, lastSeen: now,
            status: .pending, resolvedIdentifier: nil)
        finding.timesSeen += 1
        finding.lastSeen = now
        finding.frame = [frame.minX, frame.minY, frame.width, frame.height]
        if finding.status == .resolved && kind != .duplicateIdentifier { finding.status = .pending; finding.resolvedIdentifier = nil }
        if let sessionID, let how { finding.usedBy[sessionID] = how }
        backlog.findings[key] = finding
    }

    // MARK: - Identidad de pantalla, claves y datos personales

    /// Título de la pantalla: el texto de la barra de navegación o el texto más alto.
    static func screenIdentity(_ elements: [[String: Any]]) -> (key: String, title: String) {
        let texts = elements.compactMap { element -> (CGRect, String)? in
            let type = String(describing: element["type"] ?? "").lowercased()
            guard type.contains("statictext"), let frame = ScoutEngine.frame(of: element),
                  let label = element["label"] as? String, !label.trimmingCharacters(in: .whitespaces).isEmpty, label.count <= 60 else { return nil }
            return (frame, label)
        }
        let navigation = elements.first { String(describing: $0["type"] ?? "").lowercased().contains("navigationbar") }
            .flatMap { ($0["identifier"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? ($0["label"] as? String).flatMap { $0.isEmpty ? nil : $0 } }
        let title = redact(navigation ?? texts.min { $0.0.minY < $1.0.minY }?.1 ?? "Pantalla sin título")
        return (slug(title).isEmpty ? "pantalla" : slug(title), title)
    }

    static func findingKey(kind: IdentifierFinding.Kind, screenKey: String, type: String, label: String, frame: CGRect) -> String {
        // Con texto, el texto identifica al elemento; sin texto, su posición (redondeada).
        let anchor = label.isEmpty || kind == .changingText ? "@\(Int(frame.minX / 10)),\(Int(frame.minY / 10))" : label
        let digest = SHA256.hash(data: Data("\(kind.rawValue)|\(screenKey)|\(type.lowercased())|\(anchor)".utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// Lo que se comparte con otros equipos no lleva datos personales: correos, números
    /// (cuentas, montos, documentos) y nombres tras un saludo.
    public static func redact(_ text: String) -> String {
        var value = LessonRedactor.redact(text)
        value = value.replacingOccurrences(of: #"\d[\d .,*-]{2,}\d|\d{3,}"#, with: "•••", options: .regularExpression)
        value = value.replacingOccurrences(of: #"(?i)\b(hola|bienvenid[oa]|hi|hello)\s*,?\s+[^\n,.!¡?¿]+"#, with: "$1, <nombre>", options: .regularExpression)
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Patrón de textos que cambian: «Saldo S/ •••» a partir de las variantes vistas.
    static func pattern(of labels: [String]) -> String {
        guard let first = labels.first else { return "" }
        let normalized = first.replacingOccurrences(of: #"\d+"#, with: "#", options: .regularExpression)
        return labels.count > 1 ? "\(normalized) (cambia: \(labels.prefix(3).joined(separator: " · ")))" : normalized
    }

    static func slug(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es"))
        let words = folded.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        return words.prefix(6).joined(separator: "-")
    }

    static let encoder: JSONEncoder = { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601; return encoder }()
    static let decoder: JSONDecoder = { let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; return decoder }()
}
