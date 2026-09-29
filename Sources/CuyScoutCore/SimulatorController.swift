import Foundation
import CryptoKit

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
            DoctorCheck(name: "ios_webkit_debug_proxy", available: proxy != nil, detail: proxy ?? "No instalado; necesario solo para el adaptador WebKit clásico"),
            { let laya = LayaSwitch.shared.settings; return LayaService.check(url: URL(string: laya.url), enabled: laya.enabled) }()
        ]
        let optional: Set<String> = ["ios_webkit_debug_proxy", "laya"]
        let recommendations = checks.filter { !$0.available }.map { check in
            switch check.name {
            case "ios_webkit_debug_proxy": return "Conecta WebKit Inspector mediante un adaptador compatible para habilitar WEBVIEW real."
            case "laya": return "Opcional: Laya acelera decisiones acotadas. Instálalo con Scripts/laya/install_laya.sh y actívalo con decision.layaEnabled o POST /decision/laya."
            default: return "Corrige la dependencia \(check.name) antes de iniciar una sesión automatizada."
            }
        }
        return DoctorReport(ready: checks.filter { !optional.contains($0.name) }.allSatisfy(\.available), checks: checks, recommendations: recommendations)
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

    /// CoreDevice's documented machine-readable output is a JSON file, not stdout.
    /// A missing/unavailable CoreDevice service must not hide working simulators.
    public func physicalDevices() -> [Device] {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("cuyscout-devices-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: output) }
        guard (try? run("/usr/bin/xcrun", ["devicectl", "list", "devices", "--json-output", output.path, "--quiet", "--timeout", "10"])) != nil,
              let data = try? Data(contentsOf: output) else { return [] }
        return Self.physicalDevices(from: data)
    }

    static func physicalDevices(from data: Data) -> [Device] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = root["result"] as? [String: Any],
              let entries = result["devices"] as? [[String: Any]] else { return [] }
        return entries.compactMap { item -> Device? in
            let hardware = item["hardwareProperties"] as? [String: Any] ?? [:]
            guard hardware["platform"] as? String == "iOS",
                  let udid = hardware["udid"] as? String, !udid.isEmpty else { return nil }
            let properties = item["deviceProperties"] as? [String: Any] ?? [:]
            let connection = item["connectionProperties"] as? [String: Any] ?? [:]
            let state = connection["tunnelState"] as? String ?? "unavailable"
            let paired = connection["pairingState"] as? String == "paired"
            return Device(id: udid, name: properties["name"] as? String ?? "iPhone", runtime: properties["osVersionNumber"] as? String ?? "iOS", state: state, isAvailable: paired && state != "unavailable", kind: .physical)
        }.sorted { $0.name < $1.name }
    }

    public func simulatorStorage() throws -> [SimulatorStorageItem] {
        let data = try run("/usr/bin/xcrun", ["simctl", "list", "devices", "--json"]).data(using: .utf8) ?? Data()
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let runtimes = root?["devices"] as? [String: [[String: Any]]] ?? [:]
        return runtimes.flatMap { runtime, entries in entries.compactMap { item -> SimulatorStorageItem? in
            guard let id = item["udid"] as? String, let name = item["name"] as? String,
                  let state = item["state"] as? String else { return nil }
            let bytes = (item["dataPathSize"] as? NSNumber)?.int64Value ?? 0
            return SimulatorStorageItem(id: id, name: name, runtime: runtime, state: state, dataBytes: bytes)
        }}.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func installApp(_ path: String, on device: Device) throws {
        let args = device.kind == .physical ? ["devicectl", "device", "install", "app", "--device", device.id, path] : ["simctl", "install", device.id, path]
        _ = try run("/usr/bin/xcrun", args)
    }
    public func isAppInstalled(_ bundleIdentifier: String, on device: Device) -> Bool {
        if device.kind == .physical {
            let output = FileManager.default.temporaryDirectory.appendingPathComponent("cuyscout-apps-\(UUID().uuidString).json")
            defer { try? FileManager.default.removeItem(at: output) }
            guard (try? run("/usr/bin/xcrun", ["devicectl", "device", "info", "apps", "--device", device.id, "--bundle-id", bundleIdentifier, "--json-output", output.path, "--quiet"])) != nil,
                  let data = try? Data(contentsOf: output),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let result = root["result"] as? [String: Any],
                  let apps = result["apps"] as? [[String: Any]] else { return false }
            return apps.contains { $0["bundleIdentifier"] as? String == bundleIdentifier }
        }
        return (try? run("/usr/bin/xcrun", ["simctl", "get_app_container", device.id, bundleIdentifier, "app"])) != nil
    }
    /// Desactiva "Connect Hardware Keyboard" del simulador: con teclado hardware el teclado
    /// software no aparece y el `typeText` de XCUITest no puede sintetizar escritura. Es el
    /// mismo ajuste que `connectHardwareKeyboard=false` de Appium.
    ///
    /// `ConnectHardwareKeyboard` es una preferencia del Mac host (dominio `com.apple.iphonesimulator`
    /// de `~/Library/Preferences`), no del simulador: escribirla con `simctl spawn` dentro del
    /// dispositivo no tiene efecto. Se escribe en el host con `defaults write` y Simulator.app
    /// la aplica a los simuladores que arranquen después.
    public func enableSoftwareKeyboard(on device: Device) {
        guard device.kind == .simulator else { return }
        _ = try? run("/usr/bin/defaults", ["write", "com.apple.iphonesimulator", "ConnectHardwareKeyboard", "-bool", "false"])
    }
    public func uninstallApp(_ bundleIdentifier: String, on device: Device) throws {
        let args = device.kind == .physical ? ["devicectl", "device", "uninstall", "app", "--device", device.id, bundleIdentifier] : ["simctl", "uninstall", device.id, bundleIdentifier]
        _ = try run("/usr/bin/xcrun", args)
    }

    /// Resuelve la ruta del `.app` que se puede instalar a partir de un instalador cualquiera:
    /// un `.app` se usa tal cual y un `.ipa` se descomprime para tomar su `Payload/*.app`.
    /// Es lo que permite automatizar una app teniendo solo el entregable, sin su código fuente.
    public func resolveInstaller(at path: String) throws -> String {
        let expanded = (path as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expanded) else { throw ScoutError.invalidRequest("El instalador no existe: \(expanded)") }
        guard expanded.lowercased().hasSuffix(".ipa") else { return expanded }
        // Identify actual content, not name/size/mtime. Validate cached bundles before reuse:
        // simulator installation or interrupted extraction can leave a partial directory.
        let digest = SHA256.hash(data: try Data(contentsOf: URL(fileURLWithPath: expanded), options: .mappedIfSafe))
        let key = digest.map { String(format: "%02x", $0) }.joined()
        let destination = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("CuyScoutInstallers/\(key)")
        if let cached = try? payloadApp(in: destination) { return cached }
        // Extract privately, then publish only a complete bundle. Never delete an existing
        // cache another session may be using. Preserve a recovered private copy if needed.
        let staging = destination.deletingLastPathComponent().appendingPathComponent("extract-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        var keepStaging = false
        defer { if !keepStaging { try? FileManager.default.removeItem(at: staging) } }
        _ = try run("/usr/bin/unzip", ["-qo", expanded, "-d", staging.path])
        let app = try payloadApp(in: staging)
        do {
            try FileManager.default.moveItem(at: staging, to: destination)
            return destination.appendingPathComponent("Payload").appendingPathComponent(URL(fileURLWithPath: app).lastPathComponent).path
        } catch {
            if let cached = try? payloadApp(in: destination) { return cached }
            keepStaging = true
            return app
        }
    }

    private func payloadApp(in directory: URL) throws -> String {
        let payload = directory.appendingPathComponent("Payload")
        let entries = try FileManager.default.contentsOfDirectory(atPath: payload.path)
        let apps = entries.filter { $0.hasSuffix(".app") }
        guard apps.count == 1, let app = apps.first else { throw ScoutError.invalidRequest("Payload debe contener exactamente un .app") }
        let bundle = payload.appendingPathComponent(app)
        let data = try Data(contentsOf: bundle.appendingPathComponent("Info.plist"))
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let executable = plist["CFBundleExecutable"] as? String,
              !executable.isEmpty, executable != ".", executable != "..", !executable.contains("/"),
              FileManager.default.isExecutableFile(atPath: bundle.appendingPathComponent(executable).path),
              (try bundle.appendingPathComponent(executable).resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])).isRegularFile == true,
              (try bundle.appendingPathComponent(executable).resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0 > 0
        else { throw ScoutError.invalidRequest("El .ipa contiene un .app incompleto: falta CFBundleExecutable o su ejecutable") }
        return bundle.path
    }

    /// Lee CFBundleIdentifier del Info.plist de un instalador .app, sin necesidad de su código fuente.
    public func bundleIdentifier(ofAppAt path: String) throws -> String {
        let infoPath = (path as NSString).appendingPathComponent("Info.plist")
        guard FileManager.default.fileExists(atPath: infoPath) else { throw ScoutError.invalidRequest("El instalador no contiene Info.plist: \(path)") }
        let data = try Data(contentsOf: URL(fileURLWithPath: infoPath))
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any], let bundle = plist["CFBundleIdentifier"] as? String, !bundle.isEmpty else { throw ScoutError.invalidRequest("No se pudo leer CFBundleIdentifier de \(infoPath)") }
        return bundle
    }
    public func resetApp(_ bundleIdentifier: String, on device: Device) throws {
        guard device.kind == .simulator else { throw ScoutError.unsupported("resetApp en iPhone físico requiere un instalador firmado; usa replay preparation=reinstall") }
        try? uninstallApp(bundleIdentifier, on: device); _ = try run("/usr/bin/xcrun", ["simctl", "launch", device.id, bundleIdentifier])
    }

    public func boot(deviceID: String) throws { _ = try run("/usr/bin/xcrun", ["simctl", "boot", deviceID]) }
    public func shutdown(deviceID: String) throws { _ = try run("/usr/bin/xcrun", ["simctl", "shutdown", deviceID]) }
    public func erase(deviceID: String) throws { _ = try run("/usr/bin/xcrun", ["simctl", "erase", deviceID]) }
    public func clone(sourceDeviceID: String, name: String) throws -> Device { let output = try run("/usr/bin/xcrun", ["simctl", "clone", sourceDeviceID, name]); let id = output.trimmingCharacters(in: .whitespacesAndNewlines); return Device(id: id.isEmpty ? sourceDeviceID : id, name: name, runtime: "", state: "Shutdown", isAvailable: true) }
    public func delete(deviceID: String) throws { _ = try run("/usr/bin/xcrun", ["simctl", "delete", deviceID]) }
    public func create(name: String, runtime: String) throws -> Device { let output = try run("/usr/bin/xcrun", ["simctl", "create", name, runtime]); let id = output.trimmingCharacters(in: .whitespacesAndNewlines); return Device(id: id, name: name, runtime: runtime, state: "Shutdown", isAvailable: true) }
    public func rename(deviceID: String, name: String) throws { _ = try run("/usr/bin/xcrun", ["simctl", "rename", deviceID, name]) }
    public func pbsync(deviceID: String) throws { _ = try run("/usr/bin/xcrun", ["simctl", "pbsync", deviceID]) }

    public func execute(_ action: ScoutAction, on device: Device) throws -> Data? {
        if device.kind == .physical {
            switch action {
            case .launch(let bundle): _ = try run("/usr/bin/xcrun", ["devicectl", "device", "process", "launch", "--device", device.id, "--terminate-existing", bundle]); return nil
            default: throw ScoutError.unsupported("Esta acción no está disponible mediante CoreDevice en iPhone físico; usa el puente XCTest")
            }
        }
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
        let (status, stdout, stderr) = try Self.execute(executable, arguments)
        guard status == 0 else { throw ScoutError.commandFailed(String(data: stderr, encoding: .utf8) ?? "simctl command failed") }
        return stdout
    }
    public func runCommand(_ executable: String, _ arguments: [String]) throws -> String {
        let (_, stdout, stderr) = try Self.execute(executable, arguments)
        return (String(data: stdout, encoding: .utf8) ?? "") + (String(data: stderr, encoding: .utf8) ?? "")
    }

    /// Lee stdout y stderr MIENTRAS el proceso corre. Esperar a que termine antes de leer
    /// provoca un deadlock cuando la salida supera el búfer del pipe (64 KB): `simctl list
    /// --json` en una Mac con cientos de simuladores (p. ej. los runners de CI) se quedaba
    /// bloqueado escribiendo y CuyScout esperándolo para siempre.
    static func execute(_ executable: String, _ arguments: [String]) throws -> (Int32, Data, Data) {
        let process = Process(); process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        let output = Pipe(); let errors = Pipe(); process.standardOutput = output; process.standardError = errors
        try process.run()
        var stderr = Data()
        let errorsRead = DispatchSemaphore(value: 0)
        DispatchQueue.global().async { stderr = errors.fileHandleForReading.readDataToEndOfFile(); errorsRead.signal() }
        let stdout = output.fileHandleForReading.readDataToEndOfFile()
        errorsRead.wait()
        process.waitUntilExit()
        return (process.terminationStatus, stdout, stderr)
    }
}
