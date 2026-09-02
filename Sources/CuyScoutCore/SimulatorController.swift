import Foundation

public final class SimulatorController: @unchecked Sendable {
    public init() {}

    public func doctor() -> DoctorReport {
        let fileManager = FileManager.default
        let xcrun = fileManager.isExecutableFile(atPath: "/usr/bin/xcrun")
        let swift = fileManager.isExecutableFile(atPath: "/usr/bin/swift") || fileManager.isExecutableFile(atPath: "/opt/homebrew/bin/swift")
        let xcodebuild = fileManager.isExecutableFile(atPath: "/usr/bin/xcodebuild")
        let proxy = ["/opt/homebrew/bin/ios_webkit_debug_proxy", "/usr/local/bin/ios_webkit_debug_proxy"].first { fileManager.isExecutableFile(atPath: $0) }
        let checks = [
            DoctorCheck(name: "xcrun", available: xcrun, detail: xcrun ? "/usr/bin/xcrun disponible" : "Instala Xcode Command Line Tools"),
            DoctorCheck(name: "swift", available: swift, detail: swift ? "Swift disponible" : "Swift no encontrado"),
            DoctorCheck(name: "xcodebuild", available: xcodebuild, detail: xcodebuild ? "Permite preparar el runner XCTest" : "Instala Xcode completo para usar XCTest"),
            DoctorCheck(name: "ios_webkit_debug_proxy", available: proxy != nil, detail: proxy ?? "No instalado; necesario solo para el adaptador WebKit clásico")
        ]
        let recommendations = checks.filter { !$0.available }.map { check in
            check.name == "ios_webkit_debug_proxy" ? "Conecta WebKit Inspector mediante un adaptador compatible para habilitar WEBVIEW real." : "Corrige la dependencia \(check.name) antes de iniciar una sesión automatizada."
        }
        return DoctorReport(ready: checks.filter { $0.name != "ios_webkit_debug_proxy" }.allSatisfy(\.available), checks: checks, recommendations: recommendations)
    }

    public func devices() throws -> [Device] {
        let data = try run("/usr/bin/xcrun", ["simctl", "list", "devices", "available", "--json"]).data(using: .utf8) ?? Data()
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let runtimes = root?["devices"] as? [String: [[String: Any]]] ?? [:]
        return runtimes.flatMap { runtime, entries in entries.compactMap { item in
            guard let udid = item["udid"] as? String, let name = item["name"] as? String, let state = item["state"] as? String else { return nil }
            return Device(id: udid, name: name, runtime: runtime, state: state, isAvailable: (item["isAvailable"] as? Bool) ?? true)
        }}.sorted { $0.name < $1.name }
    }

    public func installApp(_ path: String, on device: Device) throws { _ = try run("/usr/bin/xcrun", ["simctl", "install", device.id, path]) }
    /// Desactiva "Connect Hardware Keyboard" del simulador: con teclado hardware el teclado
    /// software no aparece y el `typeText` de XCUITest no puede sintetizar escritura. Es el
    /// mismo ajuste que `connectHardwareKeyboard=false` de Appium.
    ///
    /// `ConnectHardwareKeyboard` es una preferencia del Mac host (dominio `com.apple.iphonesimulator`
    /// de `~/Library/Preferences`), no del simulador: escribirla con `simctl spawn` dentro del
    /// dispositivo no tiene efecto. Se escribe en el host con `defaults write` y Simulator.app
    /// la aplica a los simuladores que arranquen después.
    public func enableSoftwareKeyboard(on device: Device) {
        _ = try? run("/usr/bin/defaults", ["write", "com.apple.iphonesimulator", "ConnectHardwareKeyboard", "-bool", "false"])
    }
    public func uninstallApp(_ bundleIdentifier: String, on device: Device) throws { _ = try run("/usr/bin/xcrun", ["simctl", "uninstall", device.id, bundleIdentifier]) }

    /// Resuelve la ruta del `.app` que se puede instalar a partir de un instalador cualquiera:
    /// un `.app` se usa tal cual y un `.ipa` se descomprime para tomar su `Payload/*.app`.
    /// Es lo que permite automatizar una app teniendo solo el entregable, sin su código fuente.
    public func resolveInstaller(at path: String) throws -> String {
        let expanded = (path as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expanded) else { throw ScoutError.invalidRequest("El instalador no existe: \(expanded)") }
        guard expanded.lowercased().hasSuffix(".ipa") else { return expanded }
        // El .ipa se extrae una sola vez por contenido: reinstalar el mismo entregable no
        // paga otra descompresión, y dos instaladores distintos nunca comparten caché.
        let attributes = try? FileManager.default.attributesOfItem(atPath: expanded)
        let size = (attributes?[.size] as? Int) ?? 0
        let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let key = "\(URL(fileURLWithPath: expanded).lastPathComponent)-\(size)-\(Int(modified))"
        let destination = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("CuyScoutInstallers/\(key)")
        if let cached = try? payloadApp(in: destination) { return cached }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        _ = try run("/usr/bin/unzip", ["-qo", expanded, "-d", destination.path])
        guard let app = try? payloadApp(in: destination) else { throw ScoutError.invalidRequest("El .ipa no contiene Payload/<app>.app: \(expanded)") }
        return app
    }

    private func payloadApp(in directory: URL) throws -> String {
        let payload = directory.appendingPathComponent("Payload")
        let entries = try FileManager.default.contentsOfDirectory(atPath: payload.path)
        guard let app = entries.first(where: { $0.hasSuffix(".app") }) else { throw ScoutError.invalidRequest("Payload sin .app") }
        return payload.appendingPathComponent(app).path
    }

    /// Lee CFBundleIdentifier del Info.plist de un instalador .app, sin necesidad de su código fuente.
    public func bundleIdentifier(ofAppAt path: String) throws -> String {
        let infoPath = (path as NSString).appendingPathComponent("Info.plist")
        guard FileManager.default.fileExists(atPath: infoPath) else { throw ScoutError.invalidRequest("El instalador no contiene Info.plist: \(path)") }
        let data = try Data(contentsOf: URL(fileURLWithPath: infoPath))
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any], let bundle = plist["CFBundleIdentifier"] as? String, !bundle.isEmpty else { throw ScoutError.invalidRequest("No se pudo leer CFBundleIdentifier de \(infoPath)") }
        return bundle
    }
    public func resetApp(_ bundleIdentifier: String, on device: Device) throws { try? uninstallApp(bundleIdentifier, on: device); _ = try run("/usr/bin/xcrun", ["simctl", "launch", device.id, bundleIdentifier]) }

    public func boot(deviceID: String) throws { _ = try run("/usr/bin/xcrun", ["simctl", "boot", deviceID]) }
    public func shutdown(deviceID: String) throws { _ = try run("/usr/bin/xcrun", ["simctl", "shutdown", deviceID]) }
    public func erase(deviceID: String) throws { _ = try run("/usr/bin/xcrun", ["simctl", "erase", deviceID]) }
    public func clone(sourceDeviceID: String, name: String) throws -> Device { let output = try run("/usr/bin/xcrun", ["simctl", "clone", sourceDeviceID, name]); let id = output.trimmingCharacters(in: .whitespacesAndNewlines); return Device(id: id.isEmpty ? sourceDeviceID : id, name: name, runtime: "", state: "Shutdown", isAvailable: true) }
    public func delete(deviceID: String) throws { _ = try run("/usr/bin/xcrun", ["simctl", "delete", deviceID]) }
    public func create(name: String, runtime: String) throws -> Device { let output = try run("/usr/bin/xcrun", ["simctl", "create", name, runtime]); let id = output.trimmingCharacters(in: .whitespacesAndNewlines); return Device(id: id, name: name, runtime: runtime, state: "Shutdown", isAvailable: true) }
    public func rename(deviceID: String, name: String) throws { _ = try run("/usr/bin/xcrun", ["simctl", "rename", deviceID, name]) }
    public func pbsync(deviceID: String) throws { _ = try run("/usr/bin/xcrun", ["simctl", "pbsync", deviceID]) }

    public func execute(_ action: ScoutAction, on device: Device) throws -> Data? {
        switch action {
        case .launch(let bundle): _ = try run("/usr/bin/xcrun", ["simctl", "launch", device.id, bundle]); return nil
        case .terminate(let bundle): _ = try run("/usr/bin/xcrun", ["simctl", "terminate", device.id, bundle]); return nil
        case .backgroundApp: throw ScoutError.unsupported("background_app requiere el puente XCTest/XCUITest.")
        case .openURL(let url): _ = try run("/usr/bin/xcrun", ["simctl", "openurl", device.id, url]); return nil
        case .navigateBack, .navigateForward, .refresh: throw ScoutError.unsupported("La navegación requiere un contexto WebView o una sesión web.")
        case .acceptAlert, .dismissAlert: throw ScoutError.unsupported("El control de alertas requiere el puente XCTest/XCUITest.")
        case .rotate(let orientation): _ = try run("/usr/bin/xcrun", ["simctl", "ui", device.id, "orientation", orientation.rawValue]); return nil
        case .getClipboard, .setClipboard: throw ScoutError.unsupported("El clipboard requiere el puente XCTest/XCUITest.")
        case .screenshot: return try screenshotData(on: device)
        case .tap, .swipe, .type, .accessibilityTree, .findElement, .findElements, .findElementFromElement, .findElementsFromElement, .tapElement, .typeElement, .waitFor, .assertVisible, .assertText, .accessibilityTreeWithOptions, .accessibilityDiff, .sequence, .clearElement, .elementAttribute, .elementDisplayed, .elementEnabled, .elementRect, .elementScreenshot, .elementSelected, .elementName, .scroll, .alertText, .elementProperty, .activeElement, .visualDiff, .submit: throw ScoutError.unsupported("Esta acción requiere el puente XCTest/XCUITest registrado para la sesión.")
        case .grantPermission(let bundle, let service): _ = try run("/usr/bin/xcrun", ["simctl", "privacy", device.id, "grant", service, bundle]); return nil
        case .setBiometry(let enrolled, let enabled): if enrolled { _ = try run("/usr/bin/xcrun", ["simctl", "biometry", device.id, "enable"]) } else { _ = try run("/usr/bin/xcrun", ["simctl", "biometry", device.id, "disable"]) }; return nil
        case .setLocation(let latitude, let longitude): _ = try run("/usr/bin/xcrun", ["simctl", "location", device.id, "set", "\(latitude),\(longitude)"]); return nil
        case .setAppearance(let mode): _ = try run("/usr/bin/xcrun", ["simctl", "ui", device.id, "appearance", mode == "dark" ? "dark" : "light"]); return nil
        case .setStatusBar(let time, let dataNetwork, let wifiMode, let batteryLevel, let batteryState): var args = ["simctl", "status_bar", device.id, "override"]; if let time { args += ["--time", time] }; if let dataNetwork { args += ["--dataNetwork", dataNetwork] }; if let wifiMode { args += ["--wifiMode", wifiMode] }; if let batteryLevel { args += ["--batteryLevel", String(batteryLevel)] }; if let batteryState { args += ["--batteryState", batteryState] }; _ = try run("/usr/bin/xcrun", args); return nil
        case .startVideoRecording(let path): _ = try run("/usr/bin/xcrun", ["simctl", "io", device.id, "recordVideo", path]); return nil
        case .stopVideoRecording: return nil
        case .listApps: return try runData("/usr/bin/xcrun", ["simctl", "list", "apps", "--json"])
        case .resetKeychain: _ = try run("/usr/bin/xcrun", ["simctl", "keychain", device.id, "reset"]); return nil
        case .deepLink(let url): _ = try run("/usr/bin/xcrun", ["simctl", "openurl", device.id, url]); return nil
        case .pushNotification(let bundle, let payloadPath): _ = try run("/usr/bin/xcrun", ["simctl", "push", device.id, bundle, payloadPath]); return nil
        case .setContentSize(let size): _ = try run("/usr/bin/xcrun", ["simctl", "ui", device.id, "content_size", size]); return nil
        case .addMedia(let path): _ = try run("/usr/bin/xcrun", ["simctl", "addmedia", device.id, path]); return nil
        case .spawnProcess(let bundle, let args): var cmd = ["simctl", "spawn", device.id, bundle]; cmd += args; return try runData("/usr/bin/xcrun", cmd)
        case .icloudSync: _ = try? run("/usr/bin/xcrun", ["simctl", "icloud", device.id, "sync"]); return nil
        case .shake: _ = try run("/usr/bin/xcrun", ["simctl", "ui", device.id, "shake"]); return nil
        case .enumerateFiles(let path): return try runData("/usr/bin/xcrun", ["simctl", "io", device.id, "enumerate", path])
        case .downloadFile(let source, let destination): _ = try run("/usr/bin/xcrun", ["simctl", "io", device.id, "download", source, destination]); return nil
        case .uploadFile(let source, let destination): _ = try run("/usr/bin/xcrun", ["simctl", "io", device.id, "upload", source, destination]); return nil
        case .getAppContainer(let bundle, let container): return try runData("/usr/bin/xcrun", ["simctl", "get_app_container", device.id, bundle, "--container", container])
        case .getConfig(let key): return try runData("/usr/bin/xcrun", ["simctl", "config", "get", key])
        case .setConfig(let key, let value): _ = try run("/usr/bin/xcrun", ["simctl", "config", "set", key, value]); return nil
        case .doubleTap, .longPress, .pinch: throw ScoutError.unsupported("Esta acción requiere el puente XCTest/XCUITest registrado para la sesión.")
        }
    }

    /// `simctl io <udid> screenshot -` no escribe en stdout: crea un archivo llamado `-`
    /// en el directorio actual y devuelve exit 0, así que leer el pipe daba una imagen
    /// vacía. La captura se pide a un archivo temporal y se lee de ahí.
    private func screenshotData(on device: Device) throws -> Data {
        let path = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("cuyscout-shot-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: path) }
        _ = try run("/usr/bin/xcrun", ["simctl", "io", device.id, "screenshot", path.path])
        return try Data(contentsOf: path)
    }

    private func run(_ executable: String, _ arguments: [String]) throws -> String {
        String(data: try runData(executable, arguments), encoding: .utf8) ?? ""
    }
    private func runData(_ executable: String, _ arguments: [String]) throws -> Data {
        let process = Process(); process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        let output = Pipe(); let errors = Pipe(); process.standardOutput = output; process.standardError = errors
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw ScoutError.commandFailed(String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "simctl command failed") }
        return output.fileHandleForReading.readDataToEndOfFile()
    }
    public func runCommand(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process(); process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        let output = Pipe(); let errors = Pipe(); process.standardOutput = output; process.standardError = errors
        try process.run(); process.waitUntilExit()
        let stdout = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return stdout + stderr
    }
}
