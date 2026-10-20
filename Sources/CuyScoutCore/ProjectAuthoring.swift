import Foundation

/// Credenciales de prueba del proyecto: `fixtures/credentials.test.json`, `{ "alias": { "campo": "valor" } }`.
/// La app las edita con los valores ocultos; el archivo se escribe con permisos 0600.
public enum CredentialsStore {
    public struct Document: Equatable, Sendable {
        public var aliases: [String: [String: String]]
        /// El archivo tiene algo que no es `alias → campo → texto`: la app no lo reescribe para no perderlo.
        public var hasUnsupportedValues: Bool
        public init(aliases: [String: [String: String]] = [:], hasUnsupportedValues: Bool = false) { self.aliases = aliases; self.hasUnsupportedValues = hasUnsupportedValues }
    }

    public static func url(in project: URL) -> URL { project.appendingPathComponent("fixtures/credentials.test.json") }

    public static func validate(name: String, what: String) throws {
        guard name.range(of: "^[A-Za-z0-9][A-Za-z0-9_.-]{0,39}$", options: .regularExpression) != nil else {
            throw ScoutError.invalidRequest("\(what) no válido: usa letras, números, punto, guion y guion bajo (hasta 40), p. ej. demo_user o password_android")
        }
    }

    /// Un archivo que no existe es un documento vacío; uno que no es JSON se rechaza en vez de pisarlo.
    public static func load(in project: URL) throws -> Document {
        guard let data = try? Data(contentsOf: url(in: project)) else { return Document() }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return Document(aliases: [:], hasUnsupportedValues: true)
        }
        var aliases: [String: [String: String]] = [:], unsupported = false
        for (alias, value) in object {
            guard let fields = value as? [String: Any] else { unsupported = true; continue }
            var strings: [String: String] = [:]
            for (field, raw) in fields { if let text = raw as? String { strings[field] = text } else { unsupported = true } }
            aliases[alias] = strings
        }
        return Document(aliases: aliases, hasUnsupportedValues: unsupported)
    }

    public static func save(_ aliases: [String: [String: String]], in project: URL) throws {
        for (alias, fields) in aliases {
            try validate(name: alias, what: "Alias")
            for field in fields.keys { try validate(name: field, what: "Campo") }
        }
        if let existing = try? load(in: project), existing.hasUnsupportedValues {
            throw ScoutError.invalidRequest("fixtures/credentials.test.json tiene valores que la app no maneja (no son alias → campo → texto); edítalo a mano para no perderlos")
        }
        let file = url(in: project)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: aliases, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    /// ¿El `.gitignore` de la raíz excluye el archivo? Es una comprobación simple de líneas, no un intérprete de gitignore.
    public static func isGitIgnored(in project: URL) -> Bool {
        let text = (try? String(contentsOf: project.appendingPathComponent(".gitignore"), encoding: .utf8)) ?? ""
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        return lines.contains { ["fixtures/credentials.test.json", "credentials.test.json", "/fixtures/credentials.test.json", "fixtures/", "/fixtures/"].contains($0) }
    }
    public static func addToGitIgnore(in project: URL) throws {
        guard !isGitIgnored(in: project) else { return }
        let file = project.appendingPathComponent(".gitignore")
        var text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        if !text.isEmpty && !text.hasSuffix("\n") { text += "\n" }
        text += "fixtures/credentials.test.json\n"
        try text.write(to: file, atomically: true, encoding: .utf8)
    }
}

/// Escenarios `.feature` del proyecto: crear, editar y asociarles un fragmento (p. ej. el login del `Background`).
/// La asociación es una etiqueta Gherkin sobre `Feature:` (`@fragment:login`): visible en cualquier editor y en el diff.
public enum FeatureFile {
    public static func validate(name: String) throws {
        guard name.range(of: "^[a-z0-9][a-z0-9-]{0,59}$", options: .regularExpression) != nil else {
            throw ScoutError.invalidRequest("Nombre de escenario no válido: minúsculas, números y guiones (hasta 60), p. ej. transferencia-propia")
        }
    }
    public static func url(name: String, in project: URL) -> URL { project.appendingPathComponent("features/\(name).feature") }

    public static func template(featureTitle: String, scenarioTitle: String, fragment: String?) -> String {
        var lines: [String] = []
        if let fragment { lines += ["@fragment:\(fragment)"] }
        lines += ["Feature: \(featureTitle)", ""]
        if fragment != nil { lines += ["  Background:", "    Given el usuario ha iniciado sesión", ""] }
        lines += ["  Scenario: \(scenarioTitle)", "    When describe aquí la acción", "    Then describe aquí lo que debes ver", ""]
        return lines.joined(separator: "\n")
    }

    private static let tagPattern = "^\\s*@fragment:([a-z0-9][a-z0-9_-]{0,39})\\s*$"
    private static func featureLineIndex(_ lines: [String]) -> Int? {
        lines.firstIndex { $0.trimmingCharacters(in: .whitespaces).hasPrefix("Feature:") }
    }

    /// El fragmento asociado: `@fragment:<nombre>` en las líneas de etiquetas antes de `Feature:`.
    public static func fragment(in text: String) -> String? {
        let lines = text.components(separatedBy: "\n")
        guard let feature = featureLineIndex(lines) else { return nil }
        for line in lines[..<feature] {
            if let range = line.range(of: tagPattern, options: .regularExpression) {
                return String(line[range]).trimmingCharacters(in: .whitespaces).dropFirst("@fragment:".count).description
            }
        }
        return nil
    }

    /// Pone, cambia o quita la etiqueta de fragmento sin tocar el resto del archivo.
    public static func settingFragment(_ name: String?, in text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        guard let feature = featureLineIndex(lines) else { return text }
        var kept: [String] = []
        for (index, line) in lines.enumerated() {
            if index < feature, line.range(of: tagPattern, options: .regularExpression) != nil { continue }
            kept.append(line)
        }
        lines = kept
        guard let name else { return lines.joined(separator: "\n") }
        if let index = featureLineIndex(lines) { lines.insert("@fragment:\(name)", at: index) }
        return lines.joined(separator: "\n")
    }

    /// Problemas que impedirían usar el archivo como escenario.
    public static func problems(in text: String) -> [String] {
        let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        var problems: [String] = []
        if !lines.contains(where: { $0.hasPrefix("Feature:") }) { problems.append("Falta la línea «Feature: …».") }
        if !lines.contains(where: { $0.hasPrefix("Scenario:") || $0.hasPrefix("Scenario Outline:") }) { problems.append("Falta al menos un «Scenario: …».") }
        if text.contains("describe aquí") { problems.append("Quedan textos de la plantilla («describe aquí…»): reemplázalos por los pasos reales.") }
        return problems
    }

    public static func save(_ text: String, name: String, in project: URL, overwrite: Bool) throws {
        try validate(name: name)
        let file = url(name: name, in: project)
        if !overwrite, FileManager.default.fileExists(atPath: file.path) {
            throw ScoutError.invalidRequest("Ya existe el escenario «\(name)»")
        }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: file, atomically: true, encoding: .utf8)
    }
}
