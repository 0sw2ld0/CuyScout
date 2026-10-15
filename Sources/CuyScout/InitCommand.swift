import Foundation
import CuyScoutCore

/// `cuyscout init <directorio> (--app-path <ruta> | --bundle-id <id>) [--app-name X] [--cuyscout-repo ruta] [--port 4723] [--vscode] [--mcp | --no-mcp]`
///
/// `--bundle-id` crea el proyecto para una app ya instalada en un iPhone, sin instalador.
/// `--mcp` agrega a AGENTS.md las herramientas MCP; sin él, el agente usa solo HTTP/curl.
/// La elección queda en `.cuyscout-project.json` y se respeta al volver a ejecutar init.
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
            throw Error(message: "Uso: cuyscout init <directorio> (--app-path <ruta/al/App.app> | --bundle-id <id-de-app-instalada>) [--platform ios|android] [--application-id package] [--app-activity actividad] [--driver-id driver] [--avd nombre] [--device-id serial] [--app-name Nombre] [--cuyscout-repo ruta] [--port 4723] [--vscode] [--mcp | --no-mcp]")
        }
        var flags: [String: String] = [:]
        var vscode = false
        var mcpFlag: Bool?
        var index = arguments.index(after: arguments.startIndex)
        while index < arguments.endIndex {
            let flag = arguments[index]
            guard flag.hasPrefix("--") else { index = arguments.index(after: index); continue }
            let key = String(flag.dropFirst(2))
            if key == "vscode" { vscode = true; index = arguments.index(after: index); continue }
            if key == "mcp" || key == "no-mcp" { mcpFlag = key == "mcp"; index = arguments.index(after: index); continue }
            let next = arguments.index(after: index)
            guard next < arguments.endIndex else { throw Error(message: "Falta el valor de --\(key)") }
            flags[key] = arguments[next]
            index = arguments.index(after: next)
        }

        let requestedPlatform = flags["platform"] ?? (flags["app-path"]?.lowercased().hasSuffix(".apk") == true || flags["application-id"] != nil ? "android" : "ios")
        guard let platform = Device.Platform(rawValue: requestedPlatform.lowercased()) else { throw Error(message: "--platform debe ser ios o android") }
        let bundleID = (flags["application-id"] ?? flags["bundle-id"])?.trimmingCharacters(in: .whitespaces)
        if platform == .android && bundleID?.isEmpty != false { throw Error(message: "Android requiere --application-id (package), con APK o app instalada") }
        guard let appPath = flags["app-path"] ?? (bundleID?.isEmpty == false ? "" : nil) else {
            throw Error(message: "Indica --app-path (.app/.ipa/.apk) o --bundle-id/--application-id para una app instalada")
        }
        let appName = flags["app-name"] ?? (appPath.isEmpty ? (bundleID ?? "App").split(separator: ".").last.map(String.init) ?? "App" : URL(fileURLWithPath: appPath).deletingPathExtension().lastPathComponent)
        let current = FileManager.default.currentDirectoryPath
        let cuyscoutRepo = flags["cuyscout-repo"] ?? (FileManager.default.fileExists(atPath: current + "/Package.swift") ? current : "")
        let port = flags["port"].flatMap(Int.init) ?? 4723

        let root = URL(fileURLWithPath: targetDirectory)
        // Sin --mcp/--no-mcp se respeta lo que el proyecto ya tenía.
        let previous = ProjectUpdater.inferSettings(for: root)
        let useMCP = mcpFlag ?? previous.0.useMCP
        let options = ProjectScaffolder.Options(appName: appName, appPath: appPath,
            cuyscoutRepoPath: cuyscoutRepo, port: port, useMCP: useMCP, platform: platform,
            android: platform == .android ? AndroidProjectConfiguration(apk: appPath, applicationId: bundleID!, activity: flags["app-activity"], driverId: flags["driver-id"] ?? previous.0.android?.driverId ?? "android-emulator", deviceId: flags["device-id"], avd: flags["avd"]) : nil)
        let summary = try ProjectUpdater.write(options: options, vscode: vscode || previous.vscode, to: root,
                                               simulatorApp: appPath, physicalBundleID: platform == .ios ? bundleID : nil)
        for line in summary { print("  \(line)") }
        if !useMCP { print("  (usa --mcp para agregar MCP a AGENTS.md)") }

        print("Listo en \(root.path). features/ no se tocó: agrega o edita tus .feature ahí.")
    }
}
