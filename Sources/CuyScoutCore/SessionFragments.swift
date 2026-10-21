import Foundation

/// Un tramo de una ejecución ya validado (p. ej. el login) que el agente llama como una herramienta dentro de su sesión.
/// Vive en `fragments/<nombre>.<plataforma>.json` del proyecto. Lo escrito en los campos nunca se guarda: se sustituye por
/// una variable que apunta a un campo de `fixtures/credentials.test.json`, y el gateway lo resuelve al ejecutarlo.
public struct SessionFragment: Codable, Sendable, Equatable {
    public struct Check: Codable, Sendable, Equatable {
        public let selector: ScoutSelector
        public let timeout: Double
        public init(selector: ScoutSelector, timeout: Double = 10) { self.selector = selector; self.timeout = timeout }
    }
    public let name: String
    public let platform: Device.Platform
    public let bundleIdentifier: String?
    public let createdAt: Date
    /// Alias de `credentials.test.json` con el que se grabó; se puede cambiar al ejecutar.
    public let defaultAlias: String?
    /// `"<índice>.text"` → nombre del campo del alias (p. ej. `"2.text": "password_android"`).
    public let variables: [String: String]
    /// Lo que debe verse al terminar; si falla, el fragmento falló aunque todos los pasos se hayan ejecutado.
    /// Opcional: sin él, el fragmento termina tras sus pasos y `waitAfterSeconds`.
    public let exitCheck: Check?
    /// Segundos que se esperan al terminar los pasos (p. ej. a que cargue la pantalla tras el login).
    public let waitAfterSeconds: Double?
    /// Si la comprobación de salida ya se cumple antes de empezar (p. ej. ya hay sesión iniciada), no se ejecuta nada.
    public let skipIfAlreadyDone: Bool
    public let steps: [ScoutAction]

    public init(name: String, platform: Device.Platform, bundleIdentifier: String?, createdAt: Date = Date(), defaultAlias: String?, variables: [String: String], exitCheck: Check?, waitAfterSeconds: Double? = nil, skipIfAlreadyDone: Bool, steps: [ScoutAction]) {
        self.name = name; self.platform = platform; self.bundleIdentifier = bundleIdentifier; self.createdAt = createdAt; self.defaultAlias = defaultAlias
        self.variables = variables; self.exitCheck = exitCheck; self.waitAfterSeconds = waitAfterSeconds; self.skipIfAlreadyDone = skipIfAlreadyDone; self.steps = steps
    }

    /// «label: Transferir», o qué hace al terminar cuando no tiene comprobación.
    public var exitDescription: String {
        if let exitCheck { return "\(exitCheck.selector.strategy.rawValue): \(exitCheck.selector.value)" }
        let wait = Int(waitAfterSeconds ?? 0)
        return wait > 0 ? "sin comprobación (espera \(wait) s)" : "sin comprobación"
    }
}

public struct FragmentSummary: Codable, Sendable, Equatable {
    public let name: String
    public let platform: Device.Platform
    public let steps: Int
    public let exitCheck: String
    public let defaultAlias: String?
    public let skipIfAlreadyDone: Bool
}

public struct FragmentSaveResult: Codable, Sendable, Equatable {
    public let name: String
    public let path: String
    public let steps: Int
    /// Pasos de la grabación que no entran en el fragmento: lecturas, aserciones, pasos fallidos y otros fragmentos.
    public let dropped: Int
    /// Campos de credenciales que el fragmento usará (nunca sus valores).
    public let credentialFields: [String]
    public let warnings: [String]
}

public struct FragmentRunResult: Codable, Sendable, Equatable {
    public let name: String
    public let ok: Bool
    public let skipped: Bool
    public let stepsRun: Int
    public let stepsTotal: Int
    public let exitCheck: String
    /// Unos pocos textos de la pantalla final, para que el agente sepa dónde quedó sin pedir un `observe` completo.
    public let texts: [String]
}

public enum FragmentStore {
    public static func validate(name: String) throws {
        guard name.range(of: "^[a-z0-9][a-z0-9_-]{0,39}$", options: .regularExpression) != nil else {
            throw ScoutError.invalidRequest("Nombre de fragmento no válido: usa minúsculas, números, guion y guion bajo (hasta 40 caracteres), p. ej. login")
        }
    }
    static func directory(in project: URL) -> URL { project.appendingPathComponent("fragments", isDirectory: true) }
    static func url(name: String, platform: Device.Platform, in project: URL) -> URL {
        directory(in: project).appendingPathComponent("\(name).\(platform.rawValue).json")
    }
    public static func relativePath(name: String, platform: Device.Platform) -> String { "fragments/\(name).\(platform.rawValue).json" }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; e.dateEncodingStrategy = .iso8601; return e
    }
    private static var decoder: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }

    public static func save(_ fragment: SessionFragment, in project: URL, overwrite: Bool) throws {
        try validate(name: fragment.name)
        let file = url(name: fragment.name, platform: fragment.platform, in: project)
        if !overwrite, FileManager.default.fileExists(atPath: file.path) {
            throw ScoutError.invalidRequest("Ya existe el fragmento «\(fragment.name)» para \(fragment.platform.rawValue); usa overwrite: true para reemplazarlo")
        }
        try FileManager.default.createDirectory(at: directory(in: project), withIntermediateDirectories: true)
        try encoder.encode(fragment).write(to: file, options: .atomic)
    }

    public static func load(name: String, platform: Device.Platform, in project: URL) throws -> SessionFragment {
        try validate(name: name)
        let file = url(name: name, platform: platform, in: project)
        guard let data = try? Data(contentsOf: file) else {
            let known = list(in: project, platform: platform).map(\.name)
            throw ScoutError.invalidRequest("No hay un fragmento «\(name)» para \(platform.rawValue) en este proyecto" + (known.isEmpty ? "." : ". Disponibles: \(known.joined(separator: ", "))."))
        }
        do { return try decoder.decode(SessionFragment.self, from: data) }
        catch { throw ScoutError.invalidRequest("El fragmento «\(name)» no se puede leer (¿versión distinta?); vuelve a guardarlo con overwrite: true") }
    }

    public static func delete(name: String, platform: Device.Platform, in project: URL) throws {
        try validate(name: name)
        let file = url(name: name, platform: platform, in: project)
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        try FileManager.default.removeItem(at: file)
    }

    public static func list(in project: URL, platform: Device.Platform? = nil) -> [SessionFragment] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory(in: project), includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { try? decoder.decode(SessionFragment.self, from: Data(contentsOf: $0)) }
            .filter { platform == nil || $0.platform == platform }
    }

    // MARK: credenciales

    /// `fixtures/credentials.test.json`: `{ "alias": { "campo": "valor" } }`. Solo cuentan los valores de texto.
    public static func credentials(in project: URL) throws -> [String: [String: String]] {
        let file = project.appendingPathComponent("fixtures/credentials.test.json")
        guard let data = try? Data(contentsOf: file), let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw ScoutError.invalidRequest("No se pudo leer fixtures/credentials.test.json del proyecto: el fragmento necesita las credenciales por alias")
        }
        return object.compactMapValues { ($0 as? [String: Any])?.compactMapValues { $0 as? String } }
    }

    /// Sustituye lo escrito en los pasos por variables que apuntan a campos de credenciales. Un texto que no está en
    /// las credenciales no se guarda en disco, salvo `allowLiteral` y solo si el campo no parece guardar un secreto.
    public static func prepare(steps: [ScoutAction], credentials: [String: [String: String]], alias: String?, allowLiteral: Bool) throws -> (steps: [ScoutAction], variables: [String: String], alias: String?) {
        var prepared: [ScoutAction] = [], variables: [String: String] = [:], chosenAlias = alias
        func field(for text: String) -> (alias: String, field: String)? {
            let aliases = chosenAlias.map { [$0] } ?? credentials.keys.sorted()
            for candidate in aliases {
                if let match = credentials[candidate]?.sorted(by: { $0.key < $1.key }).first(where: { $0.value == text }) { return (candidate, match.key) }
            }
            return nil
        }
        for (index, step) in steps.enumerated() {
            switch step {
            case .typeElement(let selector, let text):
                prepared.append(.typeElement(selector, text: try replacement(text, index: index, label: "«\(selector.value)»", sensitive: AndroidController.isSensitiveField(selector))))
            case .type(let text):
                prepared.append(.type(try replacement(text, index: index, label: "el campo enfocado", sensitive: false)))
            case .sequence(let children):
                if children.contains(where: { if case .typeElement = $0 { return true }; if case .type = $0 { return true }; return false }) {
                    throw ScoutError.invalidRequest("El paso \(index + 1) es una secuencia con texto escrito: no se puede guardar en un fragmento")
                }
                prepared.append(step)
            default: prepared.append(step)
            }
        }
        func replacement(_ text: String, index: Int, label: String, sensitive: Bool) throws -> String {
            if let match = field(for: text) {
                chosenAlias = match.alias; variables["\(index).text"] = match.field
                return "<redacted>"
            }
            if allowLiteral && !sensitive { return text }
            throw ScoutError.invalidRequest("El texto escrito en el paso \(index + 1) (\(label)) no está en fixtures/credentials.test.json: añádelo como campo de un alias para que no se guarde en el fragmento" + (sensitive ? "." : ", o usa allowLiteral: true si no es un dato sensible."))
        }
        return (prepared, variables, chosenAlias)
    }

    /// Valores de las variables para un alias. Los mensajes de error nombran alias y campo, nunca el valor.
    public static func values(for fragment: SessionFragment, alias: String?, credentials: [String: [String: String]]) throws -> [String: String] {
        guard !fragment.variables.isEmpty else { return [:] }
        guard let name = alias ?? fragment.defaultAlias else { throw ScoutError.invalidRequest("El fragmento «\(fragment.name)» necesita un alias de credenciales (alias)") }
        guard let fields = credentials[name] else {
            throw ScoutError.invalidRequest("No hay un alias «\(name)» en fixtures/credentials.test.json. Disponibles: \(credentials.keys.sorted().joined(separator: ", "))")
        }
        var result: [String: String] = [:]
        for (path, field) in fragment.variables {
            guard let value = fields[field], !value.isEmpty else { throw ScoutError.invalidRequest("El alias «\(name)» no tiene el campo «\(field)» que usa el fragmento «\(fragment.name)»") }
            result[path] = value
        }
        return result
    }

    public static func summary(_ fragment: SessionFragment) -> FragmentSummary {
        FragmentSummary(name: fragment.name, platform: fragment.platform, steps: fragment.steps.count, exitCheck: fragment.exitDescription, defaultAlias: fragment.defaultAlias, skipIfAlreadyDone: fragment.skipIfAlreadyDone)
    }
}
