import Foundation
import CuyScoutCore

/// `cuyscout init <directorio> --app-path <ruta> [--app-name X] [--cuyscout-repo ruta] [--port 4723] [--vscode]`
///
/// Escribe el andamiaje de `ProjectScaffolder` bajo `<directorio>`:
/// - `scripts/*.sh` se regeneran siempre (son generados, no contenido del usuario).
/// - `fixtures/credentials.test.json` se crea solo si no existe — nunca pisa
///   credenciales que alguien ya rellenó.
/// - `AGENTS.md` se crea si no existe, o se actualiza si ya existe (reemplaza solo
///   el bloque delimitado por marcadores, preservando el resto).
/// - `--vscode` agrega prompts de Copilot (`.github/prompts/`) y fusiona `.vscode/` sin pisar
///   la configuración existente (ver `VSCodeScaffolder`).
/// - `features/` nunca se toca: es contenido propio del proyecto, no algo que
///   CuyScout pueda generar sin conocer el negocio.
enum InitCommand {
    struct Error: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func run(arguments: [String]) throws {
        guard let targetDirectory = arguments.first, !targetDirectory.hasPrefix("--") else {
            throw Error(message: "Uso: cuyscout init <directorio> --app-path <ruta/al/App.app> [--app-name Nombre] [--cuyscout-repo ruta] [--port 4723] [--vscode]")
        }
        var flags: [String: String] = [:]
        var vscode = false
        var index = arguments.index(after: arguments.startIndex)
        while index < arguments.endIndex {
            let flag = arguments[index]
            guard flag.hasPrefix("--") else { index = arguments.index(after: index); continue }
            let key = String(flag.dropFirst(2))
            if key == "vscode" { vscode = true; index = arguments.index(after: index); continue }
            let next = arguments.index(after: index)
            guard next < arguments.endIndex else { throw Error(message: "Falta el valor de --\(key)") }
            flags[key] = arguments[next]
            index = arguments.index(after: next)
        }

        guard let appPath = flags["app-path"] else {
            throw Error(message: "--app-path es obligatorio: ruta al .app o .ipa que CuyScout va a automatizar")
        }
        let appName = flags["app-name"] ?? URL(fileURLWithPath: appPath).deletingPathExtension().lastPathComponent
        let current = FileManager.default.currentDirectoryPath
        let cuyscoutRepo = flags["cuyscout-repo"] ?? (FileManager.default.fileExists(atPath: current + "/Package.swift") ? current : "")
        let port = flags["port"].flatMap(Int.init) ?? 4723

        let options = ProjectScaffolder.Options(appName: appName, appPath: appPath,
            cuyscoutRepoPath: cuyscoutRepo, port: port)

        let root = URL(fileURLWithPath: targetDirectory)
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        for (relativePath, content) in ProjectScaffolder.files(for: options).sorted(by: { $0.key < $1.key }) {
            let fileURL = root.appendingPathComponent(relativePath)
            try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            if ProjectScaffolder.executablePaths.contains(relativePath) {
                try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fileURL.path)
            }
            print("  \(relativePath) (regenerado)")
        }

        let credentialsURL = root.appendingPathComponent("fixtures/credentials.test.json")
        if fileManager.fileExists(atPath: credentialsURL.path) {
            print("  fixtures/credentials.test.json (ya existía, no se toca)")
        } else {
            try fileManager.createDirectory(at: credentialsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try ProjectScaffolder.credentialsFixture().write(to: credentialsURL, atomically: true, encoding: .utf8)
            print("  fixtures/credentials.test.json (creado — rellena los datos de prueba)")
        }

        try fileManager.createDirectory(at: root.appendingPathComponent("output"), withIntermediateDirectories: true)

        let projectConfig = root.appendingPathComponent(".cuyscout-project.json")
        if !fileManager.fileExists(atPath: projectConfig.path) {
            let installers = ["simulator": appPath, "physical": ""]
            try JSONSerialization.data(withJSONObject: installers, options: [.prettyPrinted, .sortedKeys])
                .write(to: projectConfig, options: .atomic)
            print("  .cuyscout-project.json (creado; el instalador físico se elige una vez en CuyScout.app)")
        }

        let agentsURL = root.appendingPathComponent("AGENTS.md")
        let existingAgents = try? String(contentsOf: agentsURL, encoding: .utf8)
        let merged = ProjectScaffolder.mergedAgentsMarkdown(existingContent: existingAgents, options: options)
        try merged.write(to: agentsURL, atomically: true, encoding: .utf8)
        print(existingAgents == nil ? "  AGENTS.md (creado)" : "  AGENTS.md (actualizado)")

        if vscode { for line in try VSCodeScaffolder.apply(to: root) { print("  \(line)") } }

        print("Listo en \(root.path). features/ no se tocó: agrega o edita tus .feature ahí.")
    }
}
