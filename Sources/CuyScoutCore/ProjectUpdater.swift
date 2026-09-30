import CryptoKit
import Foundation

/// Escribe y actualiza los archivos que CuyScout genera en un proyecto de pruebas (scripts,
/// `rules/README.md`, bloque de AGENTS.md, prompts de VS Code) sin tocar lo que es del
/// proyecto (`features/`, `fixtures/`, `rules/*.md`). Lo usan `cuyscout init`, «Nuevo
/// proyecto» de la app y la alerta de proyecto desactualizado.
public enum ProjectUpdater {
    public static let configFile = ".cuyscout-project.json"
    public static let versionKey = "scaffoldVersion"

    /// Huella de las plantillas de esta versión de CuyScout. Cambia sola cuando cambia
    /// cualquier script, prompt o el bloque de AGENTS.md: no hay número que recordar subir.
    public static let currentVersion: String = {
        let canonical = ProjectScaffolder.Options(appName: "App", appPath: "/app", cuyscoutRepoPath: "/repo", port: 4723)
        var withMCP = canonical
        withMCP.useMCP = true
        var parts = ProjectScaffolder.files(for: canonical).sorted { $0.key < $1.key }.map { "\($0.key)\n\($0.value)" }
        parts.append(ProjectScaffolder.agentsMarkdownBlock(for: canonical))
        parts.append(ProjectScaffolder.agentsMarkdownBlock(for: withMCP))
        parts += VSCodeScaffolder.promptFiles().sorted { $0.key < $1.key }.map { "\($0.key)\n\($0.value)" }
        let digest = SHA256.hash(data: Data(parts.joined(separator: "\u{1F}").utf8))
        return digest.prefix(6).map { String(format: "%02x", $0) }.joined()
    }()

    /// Crea o actualiza el proyecto. `simulatorApp` y `physicalBundleID` solo se escriben si
    /// vienen con valor: actualizar no borra los instaladores ya elegidos.
    @discardableResult
    public static func write(options: ProjectScaffolder.Options, vscode: Bool, to root: URL,
                             simulatorApp: String? = nil, physicalBundleID: String? = nil) throws -> [String] {
        let fileManager = FileManager.default
        var summary: [String] = []
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        for (relativePath, content) in ProjectScaffolder.files(for: options).sorted(by: { $0.key < $1.key }) {
            let file = root.appendingPathComponent(relativePath)
            try fileManager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: file, atomically: true, encoding: .utf8)
            if ProjectScaffolder.executablePaths.contains(relativePath) {
                try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
            }
            summary.append("\(relativePath) (regenerado)")
        }
        let credentials = root.appendingPathComponent("fixtures/credentials.test.json")
        if fileManager.fileExists(atPath: credentials.path) {
            summary.append("fixtures/credentials.test.json (ya existía, no se toca)")
        } else {
            try fileManager.createDirectory(at: credentials.deletingLastPathComponent(), withIntermediateDirectories: true)
            try ProjectScaffolder.credentialsFixture().write(to: credentials, atomically: true, encoding: .utf8)
            summary.append("fixtures/credentials.test.json (creado — rellena los datos de prueba)")
        }
        for folder in ["output", "features"] {
            try fileManager.createDirectory(at: root.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        let agents = root.appendingPathComponent("AGENTS.md")
        let existingAgents = try? String(contentsOf: agents, encoding: .utf8)
        try ProjectScaffolder.mergedAgentsMarkdown(existingContent: existingAgents, options: options)
            .write(to: agents, atomically: true, encoding: .utf8)
        summary.append(existingAgents == nil ? "AGENTS.md (creado)" : "AGENTS.md (actualizado)")
        summary.append(options.useMCP ? "AGENTS.md con MCP y HTTP/curl" : "AGENTS.md solo con HTTP/curl")
        if vscode { summary += try VSCodeScaffolder.apply(to: root) }

        var config = readConfig(root) ?? ["simulator": "", "physical": ""]
        if let simulatorApp, !simulatorApp.isEmpty { config["simulator"] = simulatorApp }
        if let physicalBundleID, !physicalBundleID.isEmpty { config["physicalBundleId"] = physicalBundleID }
        config["appName"] = options.appName
        config["cuyscoutRepo"] = options.cuyscoutRepoPath
        config["port"] = options.port
        config["mcp"] = options.useMCP
        config["vscode"] = vscode
        config[versionKey] = currentVersion
        try JSONSerialization.data(withJSONObject: config, options: [.sortedKeys, .prettyPrinted])
            .write(to: root.appendingPathComponent(configFile), options: .atomic)
        ScoutLog.app.info("proyecto", "Archivos de CuyScout escritos", ["proyecto": root.path, "version": currentVersion, "mcp": options.useMCP, "vscode": vscode])
        return summary
    }

    /// Es un proyecto de CuyScout y sus archivos generados no son los de esta versión.
    public static func needsUpdate(_ root: URL) -> Bool {
        let fileManager = FileManager.default
        let isProject = fileManager.fileExists(atPath: root.appendingPathComponent(configFile).path)
            || fileManager.fileExists(atPath: root.appendingPathComponent("scripts/open-session.sh").path)
        guard isProject else { return false }
        return (readConfig(root)?[versionKey] as? String) != currentVersion
    }

    /// Actualiza con la misma configuración con la que se creó el proyecto.
    @discardableResult
    public static func update(_ root: URL) throws -> [String] {
        let (options, vscode) = inferSettings(for: root)
        return try write(options: options, vscode: vscode, to: root)
    }

    /// Reconstruye nombre, repo, puerto, MCP y VS Code: de `.cuyscout-project.json` o, en
    /// proyectos creados antes de guardarlos, de los archivos que ya generó CuyScout.
    public static func inferSettings(for root: URL) -> (ProjectScaffolder.Options, vscode: Bool) {
        let config = readConfig(root) ?? [:]
        let agents = (try? String(contentsOf: root.appendingPathComponent("AGENTS.md"), encoding: .utf8)) ?? ""
        let ensure = (try? String(contentsOf: root.appendingPathComponent("scripts/ensure-cuyscout.sh"), encoding: .utf8)) ?? ""
        let appName = (config["appName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? firstMatch(#"# Pruebas de (.+) con CuyScout"#, in: agents)
            ?? root.lastPathComponent
        let repo = config["cuyscoutRepo"] as? String
            ?? firstMatch(#"CUYSCOUT_REPO="\$\{CUYSCOUT_REPO:-(.*)\}""#, in: ensure) ?? ""
        let port = config["port"] as? Int
            ?? firstMatch(#"CUYSCOUT_PORT="\$\{CUYSCOUT_PORT:-(\d+)\}""#, in: ensure).flatMap(Int.init) ?? 4723
        let useMCP = config["mcp"] as? Bool ?? agents.contains("MCP primero")
        let vscode = config["vscode"] as? Bool
            ?? FileManager.default.fileExists(atPath: root.appendingPathComponent(".github/prompts/ejecutar-escenario.prompt.md").path)
        let options = ProjectScaffolder.Options(appName: appName, appPath: config["simulator"] as? String ?? "",
                                                cuyscoutRepoPath: repo, port: port, useMCP: useMCP)
        return (options, vscode)
    }

    static func readConfig(_ root: URL) -> [String: Any]? {
        (try? Data(contentsOf: root.appendingPathComponent(configFile)))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        let value = String(text[range]).trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }
}
