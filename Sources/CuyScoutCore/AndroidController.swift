import Foundation
import CryptoKit

/// Host-side Android operations. UI queries and input belong to the Android bridge runner.
public final class AndroidController: @unchecked Sendable {
    public struct Command: Sendable, Equatable {
        public enum Mode: Sendable { case wait, background }
        public let executable: String
        public let arguments: [String]
        public let mode: Mode
        public let inputFile: String?
        public init(executable: String, arguments: [String], mode: Mode = .wait, inputFile: String? = nil) {
            self.executable = executable; self.arguments = arguments; self.mode = mode; self.inputFile = inputFile
        }
    }
    public struct Output: Sendable {
        public let status: Int32
        public let stdout: Data
        public let stderr: Data
        public init(status: Int32 = 0, stdout: Data = Data(), stderr: Data = Data()) {
            self.status = status; self.stdout = stdout; self.stderr = stderr
        }
    }
    public typealias Executor = @Sendable (Command) throws -> Output

    private let environment: [String: String]
    private let homeDirectory: String
    private let isExecutable: @Sendable (String) -> Bool
    private let executor: Executor
    private let recordingLock = NSLock()
    private struct Recording { let pid: String; let remotePath: String; let localPath: String }
    private var recordings: [String: Recording] = [:]

    public init(environment: [String: String] = ProcessInfo.processInfo.environment,
                homeDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path,
                isExecutable: @escaping @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
                executor: @escaping Executor = AndroidController.executeCommand) {
        self.environment = environment; self.homeDirectory = homeDirectory
        self.isExecutable = isExecutable; self.executor = executor
    }

    /// Carpetas donde se instala adb y que un .app abierto desde Finder no ve: no hereda el PATH ni el
    /// ANDROID_HOME del shell, solo `/usr/bin:/bin:/usr/sbin:/sbin`.
    static let fallbackToolDirectories = ["/opt/homebrew/bin", "/usr/local/bin"]
    static let fallbackSDKRoots = ["/Library/Android/sdk", "/opt/homebrew/share/android-commandlinetools", "/opt/homebrew/share/android-sdk",
                                   "/usr/local/share/android-commandlinetools", "/usr/local/share/android-sdk"]

    /// SDK variables take precedence, then PATH, then Android Studio's macOS SDK location, then the usual
    /// Homebrew prefixes (the PATH of an app opened from Finder does not include them).
    public func toolPath(_ tool: String) -> String? {
        let relative: String
        switch tool {
        case "adb": relative = "platform-tools/adb"
        case "emulator": relative = "emulator/emulator"
        case "avdmanager": relative = "cmdline-tools/latest/bin/avdmanager"
        default: return nil
        }
        let roots = [environment["ANDROID_HOME"], environment["ANDROID_SDK_ROOT"]].compactMap { $0 }.filter { !$0.isEmpty }
        let candidates = roots.map { ($0 as NSString).appendingPathComponent(relative) }
            + (environment["PATH"] ?? "").split(separator: ":").map { String($0) + "/" + tool }
            + [homeDirectory + "/Library/Android/sdk/" + relative]
            + (tool == "adb" ? Self.fallbackToolDirectories.map { $0 + "/adb" } : [])
            + Self.fallbackSDKRoots.map { ($0.hasPrefix("/Library") ? homeDirectory + $0 : $0) + "/" + relative }
        return candidates.first(where: isExecutable)
    }

    /// Por qué no aparece ningún Android utilizable, en lenguaje llano; nil si hay alguno.
    public static func destinationHint(devices: [Device], adbFound: Bool, physical: Bool) -> String? {
        guard adbFound else { return "No encuentro adb en esta Mac. Instálalo con «brew install --cask android-platform-tools» (o Android Studio) y vuelve a pulsar Actualizar." }
        let android = devices.filter { $0.platform == .android && $0.kind == (physical ? .physical : .simulator) }
        if android.contains(where: isUsable) { return nil }
        if physical {
            if android.contains(where: { $0.state == "unauthorized" }) { return "El celular está conectado pero no autorizó la depuración USB: desbloquéalo y acepta «¿Permitir depuración USB?»." }
            if android.contains(where: { $0.state == "offline" }) { return "El celular aparece offline: desconecta y vuelve a conectar el cable, o ejecuta «adb reconnect offline»." }
            if android.contains(where: { $0.state == "no permissions" }) { return "adb no tiene permisos sobre el celular: reconecta el cable y acepta la autorización en la pantalla." }
            return "adb no ve ningún celular. Activa «Depuración USB» en Opciones de desarrollador, usa un cable de datos y acepta la autorización en el celular."
        }
        return android.isEmpty ? "No hay AVD creados ni encendidos: crea uno en Android Studio › Device Manager." : nil
    }

    public func doctor() -> DoctorReport {
        var checks = ["adb", "emulator", "avdmanager"].map { tool in
            DoctorCheck(name: "android_\(tool)", available: toolPath(tool) != nil,
                        detail: toolPath(tool) ?? "Instala \(tool) con Android Studio › SDK Manager")
        }
        let sdk = toolPath("adb").flatMap { $0.hasSuffix("/platform-tools/adb") ? URL(fileURLWithPath: $0).deletingLastPathComponent().deletingLastPathComponent().path : nil }
        checks.append(DoctorCheck(name: "android_sdk", available: sdk != nil, detail: sdk ?? "SDK completo no localizado; platform-tools por PATH permite dispositivos físicos"))
        var recommendations: [String] = []
        if toolPath("adb") == nil { recommendations.append("Instala Android SDK Command-line Tools y ejecuta sdkmanager \"platform-tools\"; configura ANDROID_HOME o añade platform-tools a PATH.") }
        if toolPath("emulator") == nil { recommendations.append("Para usar AVD, ejecuta sdkmanager \"emulator\" e instala una imagen de sistema desde Android Studio › Device Manager.") }
        if toolPath("avdmanager") == nil { recommendations.append("Para crear AVD, instala Android SDK Command-line Tools desde SDK Manager; después ejecuta avdmanager list avd.") }
        if toolPath("adb") != nil {
            do {
                let devices = Self.adbDevices(from: try run("adb", ["devices", "-l"]))
                let unauthorized = devices.filter { $0.state == "unauthorized" }
                let offline = devices.filter { $0.state == "offline" }
                checks.append(DoctorCheck(name: "android_devices", available: unauthorized.isEmpty && offline.isEmpty,
                                          detail: "\(devices.count) dispositivos; \(unauthorized.count) sin autorizar; \(offline.count) offline"))
                if !unauthorized.isEmpty { recommendations.append("Desbloquea el dispositivo, activa Depuración USB y acepta la huella RSA de esta Mac; comprueba adb devices -l.") }
                if !offline.isEmpty { recommendations.append("Reconecta los dispositivos offline y comprueba adb devices -l; si persiste, ejecuta adb reconnect offline.") }
            } catch {
                checks.append(DoctorCheck(name: "android_devices", available: false, detail: error.localizedDescription))
                recommendations.append("Comprueba la conexión con adb start-server y adb devices -l.")
            }
        }
        // emulator/avdmanager are optional when using a physical device with platform-tools.
        return DoctorReport(ready: checks.filter { $0.name == "android_adb" || $0.name == "android_devices" }.allSatisfy(\.available), checks: checks, recommendations: recommendations)
    }

    struct ADBDevice: Equatable {
        let serial: String
        let state: String
        let model: String?
    }
    static func adbDevices(from output: String) -> [ADBDevice] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard fields.count >= 2, !line.hasPrefix("List of devices"), !line.hasPrefix("*"),
                  ["device", "offline", "unauthorized", "recovery", "sideload", "bootloader", "no"].contains(fields[1]) else { return nil }
            return ADBDevice(serial: fields[0], state: fields[1] == "no" ? "no permissions" : fields[1],
                             model: fields.first { $0.hasPrefix("model:") }.map { String($0.dropFirst(6)).replacingOccurrences(of: "_", with: " ") })
        }
    }

    public func devices() throws -> [Device] {
        let entries = Self.adbDevices(from: try run("adb", ["devices", "-l"]))
        var runningAVDs = Set<String>()
        var result: [Device] = []
        for entry in entries {
            let online = entry.state == "device"
            let qemu = online && !entry.serial.hasPrefix("emulator-") ? (try? shell(entry.serial, ["getprop", "ro.kernel.qemu"])) : nil
            let isEmulator = entry.serial.hasPrefix("emulator-") || qemu?.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
            var name = entry.model ?? entry.serial
            if isEmulator, online, let avd = try? run("adb", ["-s", entry.serial, "emu", "avd", "name"]),
               let avdName = avd.split(whereSeparator: \.isNewline).map(String.init).first(where: { !$0.isEmpty && $0 != "OK" }) {
                name = avdName; runningAVDs.insert(avdName)
            }
            let release = online ? (try? shell(entry.serial, ["getprop", "ro.build.version.release"]).trimmingCharacters(in: .whitespacesAndNewlines)) : nil
            result.append(Device(id: entry.serial, name: name, runtime: release.map { "Android \($0)" } ?? "Android", state: online ? "Booted" : entry.state,
                                 isAvailable: online, kind: isEmulator ? .simulator : .physical, platform: .android))
        }
        if toolPath("emulator") != nil {
            for name in try run("emulator", ["-list-avds"]).split(whereSeparator: \.isNewline).map(String.init) where !runningAVDs.contains(name) {
                result.append(Device(id: name, name: name, runtime: "Android", state: "Shutdown", kind: .simulator, platform: .android))
            }
        }
        return result.sorted { ($0.name, $0.id) < ($1.name, $1.id) }
    }

    public func installApp(_ path: String, on device: Device) throws {
        try requireAndroid(device)
        let expanded = (path as NSString).expandingTildeInPath
        guard expanded.lowercased().hasSuffix(".apk"), FileManager.default.fileExists(atPath: expanded) else { throw ScoutError.invalidRequest("Se requiere un APK existente: \(expanded)") }
        let output = try run("adb", ["-s", device.id, "install", "-r", expanded])
        // Según la versión de adb, un rechazo (versión de SDK, firma distinta…) sale con código 0.
        if let failure = output.split(whereSeparator: \.isNewline).first(where: { $0.contains("Failure [") }) {
            throw ScoutError.commandFailed("No se pudo instalar \((expanded as NSString).lastPathComponent): \(failure.trimmingCharacters(in: .whitespaces))")
        }
    }

    /// Instala un APK solo si el del teléfono no es ya este. Cada `adb install` de una app desconocida hace que
    /// Google Play Protect pregunte «¿Quieres enviar una app para un control de seguridad?» en el teléfono, así que
    /// el runner (que no cambia entre sesiones) se instala una vez y se reutiliza. Se recuerda en el teléfono el
    /// SHA-256 del APK instalado; si el paquete ya no está o el APK cambió, se instala de nuevo.
    /// Devuelve `true` si instaló y `false` si reutilizó el que había.
    @discardableResult
    public func installIfChanged(_ path: String, package: String, on device: Device) throws -> Bool {
        try requireAndroid(device); try validatePackage(package)
        let expanded = (path as NSString).expandingTildeInPath
        guard expanded.lowercased().hasSuffix(".apk"), let data = FileManager.default.contents(atPath: expanded) else { throw ScoutError.invalidRequest("Se requiere un APK existente: \(expanded)") }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let marker = "/data/local/tmp/cuyscout-installed-\(package).sha256"
        if (try? isAppInstalled(package, on: device)) == true,
           let recorded = try? shell(device.id, ["cat", marker]), recorded.trimmingCharacters(in: .whitespacesAndNewlines) == digest { return false }
        try installApp(expanded, on: device)
        _ = try? adbCommand(["-s", device.id, "shell", "echo \(digest) > " + Self.quote(marker)])
        return true
    }

    // MARK: Pantalla encendida durante una sesión (ver AndroidScreenKeeper)
    static let stayOnMarker = "/data/local/tmp/cuyscout-stayon-original"
    /// Activa «pantalla encendida al cargar» recordando el valor de la persona. El valor original se guarda una sola vez: si ya hay
    /// uno guardado (una sesión anterior que no pudo restaurarlo), manda ese y no el que dejamos nosotros.
    func keepScreenOn(on device: Device) throws {
        try requireAndroid(device)
        let script = "m=\(Self.stayOnMarker); [ -f $m ] || { v=$(settings get global stay_on_while_plugged_in); case \"$v\" in [0-9]*) echo \"$v\" > $m;; *) echo 0 > $m;; esac; }; settings put global stay_on_while_plugged_in 7"
        _ = try adbCommand(["-s", device.id, "shell", "sh -c " + Self.quote(script)])
    }
    func restoreScreenTimeout(on device: Device) throws {
        try requireAndroid(device)
        let script = "m=\(Self.stayOnMarker); if [ -f $m ]; then settings put global stay_on_while_plugged_in $(cat $m); rm -f $m; fi"
        _ = try adbCommand(["-s", device.id, "shell", "sh -c " + Self.quote(script)])
    }
    func wakefulness(on device: Device) throws -> String {
        try requireAndroid(device)
        return String(decoding: try adbCommand(["-s", device.id, "shell", "sh -c " + Self.quote("dumpsys power | grep -m1 mWakefulness=")]), as: UTF8.self)
    }
    func wakeUp(on device: Device) throws { try requireAndroid(device); _ = try adbCommand(["-s", device.id, "shell", "input keyevent KEYCODE_WAKEUP"]) }
    func dismissKeyguard(on device: Device) throws { try requireAndroid(device); _ = try adbCommand(["-s", device.id, "shell", "cmd window dismiss-keyguard"]) }
    func focusedWindow(on device: Device) throws -> String {
        try requireAndroid(device)
        return String(decoding: try adbCommand(["-s", device.id, "shell", "sh -c " + Self.quote("dumpsys window | grep -m1 mCurrentFocus")]), as: UTF8.self)
    }
    static func isAsleep(_ wakefulness: String) -> Bool { wakefulness.contains("mWakefulness=Asleep") || wakefulness.contains("mWakefulness=Dozing") }
    static func isLockScreen(_ focus: String) -> Bool {
        let value = focus.lowercased()
        return value.contains("keyguard") || value.contains("notificationshade") || value.contains("lockscreen")
    }

    /// Un Android al que se le puede ordenar algo: en marcha y autorizado. Un AVD apagado, un
    /// teléfono sin autorizar la depuración o uno desconectado no lo son.
    public static func isUsable(_ device: Device) -> Bool {
        device.platform == .android && device.isAvailable && !["Shutdown", "offline", "unauthorized", "no permissions"].contains(device.state)
    }
    /// Un teléfono con perfil de trabajo o espacio privado tiene más de un usuario (el de trabajo suele ser el 10).
    /// `pm`/`am` sin `--user` recorren todos y el shell de adb no puede acceder al del perfil de trabajo
    /// (`SecurityException: Shell does not have permission to access user 10`): se acota al usuario principal.
    static let ownerUser = "0"
    public func clearAppData(_ package: String, on device: Device) throws {
        try requireAndroid(device); try validatePackage(package)
        guard try shell(device.id, ["pm", "clear", "--user", Self.ownerUser, package]).trimmingCharacters(in: .whitespacesAndNewlines) == "Success" else {
            throw ScoutError.commandFailed("No se pudieron borrar los datos de \(package); comprueba pm clear y que la app esté instalada")
        }
    }
    static func apkPath(_ path: String) throws -> String {
        let expanded = (path as NSString).expandingTildeInPath
        guard expanded.lowercased().hasSuffix(".apk"), FileManager.default.fileExists(atPath: expanded) else { throw ScoutError.invalidRequest("Se requiere un APK existente: \(expanded)") }
        return expanded
    }
    public func uninstallApp(_ bundleIdentifier: String, on device: Device) throws {
        try requireAndroid(device); try validatePackage(bundleIdentifier)
        _ = try run("adb", ["-s", device.id, "uninstall", bundleIdentifier])
    }
    public func isAppInstalled(_ bundleIdentifier: String, on device: Device) throws -> Bool {
        try requireAndroid(device); try validatePackage(bundleIdentifier)
        return Self.packages(from: try shell(device.id, ["pm", "list", "packages", "--user", Self.ownerUser, bundleIdentifier])).contains(bundleIdentifier)
    }
    static func packages(from output: String) -> [String] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            guard line.hasPrefix("package:") else { return nil }
            return String(line.dropFirst(8)).trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }.sorted()
    }

    /// An AVD's ID changes from its name to an adb serial after boot; return that device.
    @discardableResult
    public func boot(deviceID: String, timeout: Double = 120) throws -> Device {
        guard timeout.isFinite && timeout >= 0 else { throw ScoutError.invalidRequest("timeout debe ser finito y positivo") }
        let current = try devices()
        guard let device = current.first(where: { $0.id == deviceID }) else { throw ScoutError.invalidRequest("AVD no encontrado: \(deviceID); comprueba emulator -list-avds") }
        guard device.kind == .simulator else { throw ScoutError.unsupported("boot solo inicia AVD; conecta y desbloquea el dispositivo físico") }
        guard device.state == "Shutdown" || device.isAvailable else { throw ScoutError.invalidRequest("El emulador está \(device.state); reconéctalo antes de arrancar") }
        if device.state == "Shutdown" { _ = try run("emulator", ["-avd", device.name], mode: .background) }
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let running = try devices().first(where: { $0.kind == .simulator && $0.isAvailable && $0.state != "Shutdown" && ($0.id == deviceID || $0.name == device.name) }),
               (try? shell(running.id, ["getprop", "sys.boot_completed"]).trimmingCharacters(in: .whitespacesAndNewlines)) == "1" { return running }
            if Date() >= deadline { break }
            Thread.sleep(forTimeInterval: 0.25)
        } while true
        throw ScoutError.commandFailed("El AVD no terminó de arrancar; comprueba adb devices -l y los logs de emulator")
    }
    public func shutdown(deviceID: String) throws {
        guard let device = try devices().first(where: { $0.id == deviceID || $0.name == deviceID }) else { throw ScoutError.invalidRequest("AVD no encontrado: \(deviceID)") }
        guard device.kind == .simulator else { throw ScoutError.unsupported("shutdown solo detiene AVD; no apaga dispositivos físicos") }
        if device.state == "Shutdown" { return }
        guard device.isAvailable else { throw ScoutError.invalidRequest("El AVD está \(device.state); comprueba adb devices -l") }
        _ = try run("adb", ["-s", device.id, "emu", "kill"])
    }

    public func execute(_ action: ScoutAction, on device: Device) throws -> Data? {
        try requireAndroid(device)
        switch action {
        case .launch(let package):
            try validatePackage(package)
            let output = try shellCombined(device.id, ["monkey", "-p", package, "-c", "android.intent.category.LAUNCHER", "1"])
            guard !output.contains("No activities found"), !output.lowercased().contains("monkey aborted") else { throw ScoutError.commandFailed("No se encontró una actividad de lanzamiento; usa launchApp(_:activity:on:)") }
        case .terminate(let package):
            try validatePackage(package); _ = try shell(device.id, ["am", "force-stop", "--user", Self.ownerUser, package])
        case .openURL(let url), .deepLink(let url):
            try startActivity(["-a", "android.intent.action.VIEW", "-d", url], on: device)
        case .grantPermission(let package, let permission):
            try validatePackage(package); _ = try shell(device.id, ["pm", "grant", "--user", Self.ownerUser, package, permission])
        case .setLocation(let latitude, let longitude):
            guard device.kind == .simulator else { throw ScoutError.unsupported("setLocation por adb emu geo fix solo funciona en emuladores; usa una app de ubicación simulada en el físico") }
            guard latitude.isFinite && longitude.isFinite && abs(latitude) <= 90 && abs(longitude) <= 180 else { throw ScoutError.invalidRequest("Coordenadas GPS fuera de rango") }
            _ = try run("adb", ["-s", device.id, "emu", "geo", "fix", String(longitude), String(latitude)])
        case .screenshot:
            let data = try runData("adb", ["-s", device.id, "exec-out", "screencap", "-p"])
            guard data.starts(with: [0x89, 0x50, 0x4e, 0x47, 13, 10, 0x1a, 10]) else { throw ScoutError.commandFailed("screencap no devolvió una imagen PNG; comprueba la conexión y los permisos de captura") }
            return data
        case .setAppearance(let mode):
            guard ["dark", "light"].contains(mode) else { throw ScoutError.invalidRequest("setAppearance acepta dark o light") }
            _ = try shell(device.id, ["cmd", "uimode", "night", mode == "dark" ? "yes" : "no"])
        case .rotate(let orientation):
            let rotation: Int
            switch orientation { case .portrait: rotation = 0; case .landscapeLeft: rotation = 1; case .portraitUpsideDown: rotation = 2; case .landscapeRight: rotation = 3 }
            _ = try shell(device.id, ["settings", "put", "system", "accelerometer_rotation", "0"])
            _ = try shell(device.id, ["settings", "put", "system", "user_rotation", String(rotation)])
        case .getClipboard, .setClipboard:
            throw ScoutError.unsupported("El clipboard Android requiere el runner; adb no ofrece una API estable")
        case .startVideoRecording(let path): try startRecording(path: path, on: device)
        case .stopVideoRecording: try stopRecording(on: device)
        case .listApps:
            let apps = Self.packages(from: try shell(device.id, ["pm", "list", "packages", "--user", Self.ownerUser, "-3"]))
            return try JSONEncoder().encode(apps.map { InstalledApp(bundleIdentifier: $0, name: $0, version: nil, developerBuild: false) })
        case .getAppContainer(let package, let container):
            try validatePackage(package)
            guard container == "data" else { throw ScoutError.unsupported("Android solo permite container=data en apps depurables; usa run-as o adb pull para almacenamiento compartido") }
            return try shellData(device.id, ["run-as", package, "pwd"])
        case .enumerateFiles(let path):
            if let (package, relative) = try privateAppPath(path) { return try shellData(device.id, ["run-as", package, "ls", "-1", "--", relative]) }
            return try shellData(device.id, ["ls", "-1", "--", path])
        case .downloadFile(let source, let destination):
            let local = (destination as NSString).expandingTildeInPath
            if let (package, relative) = try privateAppPath(source) {
                let data = try runData("adb", ["-s", device.id, "shell", "-T", ["run-as", package, "cat", "--", relative].map(Self.quote).joined(separator: " ")])
                try data.write(to: URL(fileURLWithPath: local), options: .atomic)
            } else { _ = try run("adb", ["-s", device.id, "pull", source, local]) }
        case .uploadFile(let source, let destination):
            let local = (source as NSString).expandingTildeInPath
            guard FileManager.default.fileExists(atPath: local) else { throw ScoutError.invalidRequest("El archivo de origen no existe") }
            if let (package, relative) = try privateAppPath(destination) {
                let remote = ["run-as", package, "sh", "-c", "cat > " + Self.quote(relative)].map(Self.quote).joined(separator: " ")
                _ = try runData("adb", ["-s", device.id, "shell", "-T", remote], inputFile: local)
            } else { _ = try run("adb", ["-s", device.id, "push", local, destination]) }
        case .pushNotification, .icloudSync, .resetKeychain, .setBiometry, .setStatusBar, .setContentSize, .shake, .addMedia:
            throw ScoutError.unsupported("Esta acción de iOS no tiene equivalente directo en Android; usa una API específica de la app o del emulador")
        case .getConfig, .setConfig, .spawnProcess:
            throw ScoutError.unsupported("La configuración y ejecución arbitraria de procesos no está disponible en el host Android; usa adb explícitamente")
        default:
            throw ScoutError.unsupported("Esta acción requiere el runner Android conectado al puente de la sesión")
        }
        return nil
    }

    // MARK: Escribir por adb (respaldo cuando el campo no es editable para accesibilidad)

    static func keyboardShown(from dumpsys: String) -> Bool { dumpsys.contains("mInputShown=true") }
    public func isKeyboardShown(on device: Device) throws -> Bool {
        try requireAndroid(device)
        return Self.keyboardShown(from: try shell(device.id, ["dumpsys", "input_method"]))
    }

    /// `input text` solo escribe ASCII imprimible y toma `%s` como espacio: lo demás no se puede enviar por esta vía.
    static func inputTextArgument(_ text: String) -> String? {
        guard !text.isEmpty, !text.contains("%s"),
              text.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value <= 0x7E }) else { return nil }
        return text.replacingOccurrences(of: " ", with: "%s")
    }

    /// Lo que se escribe por adb queda en el log del dispositivo (adbd registra cada comando de shell): no se usa
    /// para campos que parecen guardar un secreto. Es una heurística sobre el selector, no una garantía.
    public static func isSensitiveField(_ selector: ScoutSelector) -> Bool {
        let tokens = Set(selector.value.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        return !tokens.isDisjoint(with: ["password", "passwd", "passcode", "pass", "pin", "cvv", "cvc", "otp", "token", "secret", "contrasena", "contraseña", "clave", "secure"])
    }

    /// Algunas apps (p. ej. un monto en React Native) no exponen un campo editable para accesibilidad:
    /// la acción de escribir del runner falla con `not_visible`, pero con el teclado abierto el campo enfocado sí recibe
    /// `input text`. Devuelve false, sin tocar nada, si no hay teclado abierto o el texto no se puede enviar así.
    @discardableResult
    public func typeIntoFocusedField(_ text: String, closeKeyboard: Bool = true, on device: Device) throws -> Bool {
        try requireAndroid(device)
        guard let argument = Self.inputTextArgument(text), try isKeyboardShown(on: device) else { return false }
        _ = try shell(device.id, ["input", "text", argument])
        if closeKeyboard {
            Thread.sleep(forTimeInterval: 0.3)
            // Atrás con el teclado abierto solo lo cierra; la app no navega.
            if try isKeyboardShown(on: device) { _ = try shell(device.id, ["input", "keyevent", "KEYCODE_BACK"]) }
        }
        return true
    }
    // MARK: Teclado y teclas (como pressKey/hideKeyboard de Appium y Maestro)

    /// Nombres de tecla aceptados por `pressKey` y su KEYCODE de Android.
    static let namedKeys: [String: String] = [
        "enter": "KEYCODE_ENTER", "back": "KEYCODE_BACK", "home": "KEYCODE_HOME", "delete": "KEYCODE_DEL", "backspace": "KEYCODE_DEL",
        "tab": "KEYCODE_TAB", "search": "KEYCODE_SEARCH", "escape": "KEYCODE_ESCAPE", "space": "KEYCODE_SPACE"
    ]
    public func pressKey(_ name: String, on device: Device) throws {
        try requireAndroid(device)
        guard let code = Self.namedKeys[name.lowercased()] else {
            throw ScoutError.invalidRequest("Tecla no admitida: \(name). Usa una de: \(Self.namedKeys.keys.sorted().joined(separator: ", "))")
        }
        _ = try shell(device.id, ["input", "keyevent", code])
    }
    /// Cierra el teclado solo si está abierto: «Atrás» sin teclado haría navegar a la app.
    @discardableResult
    public func hideKeyboard(on device: Device) throws -> Bool {
        try requireAndroid(device)
        guard try isKeyboardShown(on: device) else { return false }
        _ = try shell(device.id, ["input", "keyevent", "KEYCODE_BACK"])
        return true
    }
    /// Borra hasta `count` caracteres del campo enfocado: va al final del texto y envía Delete `count` veces.
    public func eraseText(count: Int, on device: Device) throws {
        try requireAndroid(device)
        guard (1...200).contains(count) else { throw ScoutError.invalidRequest("eraseText admite de 1 a 200 caracteres") }
        guard try isKeyboardShown(on: device) else {
            throw ScoutError.invalidRequest("eraseText necesita un campo enfocado con el teclado abierto: toca el campo antes")
        }
        _ = try shell(device.id, ["input", "keyevent", "KEYCODE_MOVE_END"] + Array(repeating: "KEYCODE_DEL", count: count))
    }

    /// Paquete de la ventana con el foco (`mCurrentFocus` de `dumpsys window`); nil si no se puede leer o no hay ventana.
    static func foregroundPackage(from dumpsys: String) -> String? {
        for line in dumpsys.split(whereSeparator: \.isNewline) {
            guard let range = line.range(of: "mCurrentFocus=") else { continue }
            let rest = line[range.upperBound...]
            guard rest.hasPrefix("Window{"), let slash = rest.firstIndex(of: "/") else { return nil }
            let before = rest[..<slash]
            guard let token = before.split(whereSeparator: \.isWhitespace).last, token.contains(".") else { return nil }
            return String(token)
        }
        return nil
    }
    public func foregroundPackage(on device: Device) throws -> String? {
        try requireAndroid(device)
        return Self.foregroundPackage(from: try shell(device.id, ["dumpsys", "window"]))
    }
    /// MIUI y otras capas niegan que el runner (instrumentación) arranque una actividad desde segundo plano:
    /// el sistema lo registra como «Permission Denied Activity» y la app se queda sin abrir. Desde adb (shell)
    /// el arranque sí está permitido. Devuelve true si tuvo que lanzarla.
    @discardableResult
    public func bringToForeground(_ package: String, activity: String?, on device: Device, settle: TimeInterval = 3) throws -> Bool {
        try requireAndroid(device); try validatePackage(package)
        let deadline = Date().addingTimeInterval(settle)
        repeat {
            guard let current = try foregroundPackage(on: device) else { return false }  // sin dato fiable no se toca nada
            if current == package { return false }
            if Date() >= deadline { break }
            Thread.sleep(forTimeInterval: 0.5)
        } while true
        if let activity, !activity.isEmpty {
            try launchApp(package, activity: activity.hasPrefix(".") ? package + activity : activity, on: device)
        } else {
            _ = try execute(.launch(bundleIdentifier: package), on: device)
        }
        return true
    }
    /// `bundleIdentifier` means the Android applicationId/package. No change to ScoutAction.
    public func launchApp(_ bundleIdentifier: String, activity: String, on device: Device) throws {
        try requireAndroid(device); try validatePackage(bundleIdentifier)
        guard !activity.isEmpty else { throw ScoutError.invalidRequest("appActivity no puede estar vacía") }
        try startActivity(["-n", "\(bundleIdentifier)/\(activity)"], on: device)
    }
    private func startActivity(_ arguments: [String], on device: Device) throws {
        let output = try shellCombined(device.id, ["am", "start", "-W", "--user", Self.ownerUser] + arguments)
        if output.contains("Error:") || output.contains("Error type") || output.contains("Exception") { throw ScoutError.commandFailed("No se pudo iniciar la actividad Android; comprueba el package, appActivity o el deep link") }
    }

    private func startRecording(path: String, on device: Device) throws {
        recordingLock.lock(); defer { recordingLock.unlock() }
        guard recordings[device.id] == nil else { throw ScoutError.invalidRequest("Ya hay una grabación en este dispositivo; detenla antes de iniciar otra") }
        guard !path.isEmpty else { throw ScoutError.invalidRequest("Indica una ruta local para el MP4") }
        let local = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        try FileManager.default.createDirectory(at: local.deletingLastPathComponent(), withIntermediateDirectories: true)
        let remote = "/sdcard/cuyscout-\(UUID().uuidString).mp4"
        let command = "nohup screenrecord --time-limit 180 \(Self.quote(remote)) </dev/null >/dev/null 2>&1 & echo $!"
        let pid = try run("adb", ["-s", device.id, "shell", command]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pid.isEmpty && pid.allSatisfy(\.isNumber) else { throw ScoutError.commandFailed("No se pudo iniciar screenrecord") }
        let recording = Recording(pid: pid, remotePath: remote, localPath: local.path)
        let deadline = Date().addingTimeInterval(2)
        while try !recordingIsRunning(recording, on: device) {
            guard Date() < deadline else { throw ScoutError.commandFailed("screenrecord terminó al iniciar; comprueba que el dispositivo admita grabación") }
            Thread.sleep(forTimeInterval: 0.05)
        }
        recordings[device.id] = recording
    }
    private func stopRecording(on device: Device) throws {
        recordingLock.lock(); defer { recordingLock.unlock() }
        guard let recording = recordings[device.id] else { throw ScoutError.invalidRequest("No hay una grabación iniciada por este controlador") }
        // It may have finished automatically at the 180-second Android limit.
        if try recordingIsRunning(recording, on: device) {
            _ = try shell(device.id, ["kill", "-2", recording.pid])
            let deadline = Date().addingTimeInterval(10)
            while try recordingIsRunning(recording, on: device) {
                guard Date() < deadline else { throw ScoutError.commandFailed("screenrecord no terminó de guardar el MP4; vuelve a detener la grabación") }
                Thread.sleep(forTimeInterval: 0.1)
            }
        }
        _ = try run("adb", ["-s", device.id, "pull", recording.remotePath, recording.localPath])
        _ = try shell(device.id, ["rm", "--", recording.remotePath])
        recordings.removeValue(forKey: device.id)
    }

    private func privateAppPath(_ path: String) throws -> (String, String)? {
        guard path.hasPrefix("/") && !path.split(separator: "/").contains("..") else { throw ScoutError.invalidRequest("Usa una ruta Android absoluta sin '..'") }
        let prefixes = ["/data/data/", "/data/user/0/"]
        guard let prefix = prefixes.first(where: path.hasPrefix) else { return nil }
        let parts = path.dropFirst(prefix.count).split(separator: "/", maxSplits: 1).map(String.init)
        guard let package = parts.first else { throw ScoutError.invalidRequest("La ruta privada debe incluir el package") }
        try validatePackage(package)
        return (package, parts.count == 2 ? parts[1] : ".")
    }

    private func recordingIsRunning(_ recording: Recording, on device: Device) throws -> Bool {
        // Avoid signaling an unrelated process if Android has already recycled the PID.
        let output = try shell(device.id, ["sh", "-c", "if [ -d /proc/\(recording.pid) ]; then cat /proc/\(recording.pid)/cmdline; fi"])
        return output.contains("screenrecord") && output.contains(recording.remotePath)
    }

    private func requireAndroid(_ device: Device) throws {
        guard device.platform == .android else { throw ScoutError.invalidRequest("AndroidController requiere un dispositivo Android") }
        guard Self.isUsable(device) else { throw ScoutError.invalidRequest("El dispositivo Android no está conectado; arranca el AVD o comprueba adb devices -l") }
    }
    private func validatePackage(_ package: String) throws {
        guard !package.isEmpty, package.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._").contains($0) }), !package.hasPrefix(".") else { throw ScoutError.invalidRequest("applicationId/package Android no válido") }
    }
    /// adb shell joins argv into a remote shell command: quote every argument, including URLs.
    static func quote(_ argument: String) -> String { "'" + argument.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    private func shell(_ serial: String, _ arguments: [String]) throws -> String { String(decoding: try shellData(serial, arguments), as: UTF8.self) }
    private func shellData(_ serial: String, _ arguments: [String]) throws -> Data { try runData("adb", ["-s", serial, "shell", arguments.map(Self.quote).joined(separator: " ")]) }
    func adbCommand(_ arguments: [String]) throws -> Data { try runData("adb", arguments) }
    private func run(_ tool: String, _ arguments: [String], mode: Command.Mode = .wait) throws -> String { String(decoding: try runData(tool, arguments, mode: mode), as: UTF8.self) }
    private func shellCombined(_ serial: String, _ arguments: [String]) throws -> String {
        let result = try runOutput("adb", ["-s", serial, "shell", arguments.map(Self.quote).joined(separator: " ")])
        return String(decoding: result.stdout + result.stderr, as: UTF8.self)
    }
    private func runData(_ tool: String, _ arguments: [String], mode: Command.Mode = .wait, inputFile: String? = nil) throws -> Data {
        try runOutput(tool, arguments, mode: mode, inputFile: inputFile).stdout
    }
    private func runOutput(_ tool: String, _ arguments: [String], mode: Command.Mode = .wait, inputFile: String? = nil) throws -> Output {
        guard let path = toolPath(tool) else { throw ScoutError.commandFailed("Falta \(tool); instala Android SDK con SDK Manager y configura ANDROID_HOME o PATH (sdkmanager \"platform-tools\" \"emulator\")") }
        let output = try executor(Command(executable: path, arguments: arguments, mode: mode, inputFile: inputFile))
        guard output.status == 0 else {
            // Do not echo command arguments/output: URLs, paths and app errors may contain PII.
            let hint = arguments.joined(separator: " ").contains("'run-as'") ? "; run-as requiere una app depurable y una ruta de su contenedor de datos" : "; comprueba la conexión, permisos y AndroidController.doctor()"
            throw ScoutError.commandFailed("\(tool) falló (exit \(output.status))" + hint)
        }
        return output
    }
    private final class ErrorStream: @unchecked Sendable { var data = Data() }

    public static func executeCommand(_ command: Command) throws -> Output {
        if command.mode == .background {
            let process = Process(); process.executableURL = URL(fileURLWithPath: command.executable); process.arguments = command.arguments
            process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice; process.standardInput = FileHandle.nullDevice
            try process.run()
            return Output()
        }
        let process = Process(); process.executableURL = URL(fileURLWithPath: command.executable); process.arguments = command.arguments
        let output = Pipe(); let errors = Pipe()
        process.standardOutput = output; process.standardError = errors
        let input = try command.inputFile.map { try FileHandle(forReadingFrom: URL(fileURLWithPath: $0)) }
        defer { try? input?.close() }
        process.standardInput = input ?? FileHandle.nullDevice
        try process.run()
        // Drain both streams while the process runs so large trees/files cannot fill a pipe.
        let captured = ErrorStream()
        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global().async { captured.data = errors.fileHandleForReading.readDataToEndOfFile(); finished.signal() }
        let stdout = output.fileHandleForReading.readDataToEndOfFile()
        finished.wait(); process.waitUntilExit()
        return Output(status: process.terminationStatus, stdout: stdout, stderr: captured.data)
    }
}
