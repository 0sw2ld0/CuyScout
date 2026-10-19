import Foundation

public struct RunnerLaunchContext: Sendable {
    public let session: Session
    public let gatewayURL: String
    public let preserveRunningApp: Bool
    public let environment: [String: String]
    public init(session: Session, gatewayURL: String, preserveRunningApp: Bool = false, environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.session = session; self.gatewayURL = gatewayURL; self.preserveRunningApp = preserveRunningApp; self.environment = environment
    }
}

/// Platform-specific lifecycle; engine/bridge/session contracts stay shared.
public protocol RunnerLaunching: Sendable {
    func launch(_ context: RunnerLaunchContext) throws -> Process
    func stop(session: Session, process: Process?)
}
extension RunnerLaunching {
    public func stop(session: Session, process: Process?) { if let process, process.isRunning { process.terminate() } }
}

final class IOSRunnerLauncher: RunnerLaunching {
    private let start: @Sendable (RunnerLaunchContext) throws -> Process
    init(start: @escaping @Sendable (RunnerLaunchContext) throws -> Process) { self.start = start }
    func launch(_ context: RunnerLaunchContext) throws -> Process { try start(context) }
}

public final class AndroidRunnerLauncher: RunnerLaunching, @unchecked Sendable {
    public typealias StartProcess = @Sendable (String, [String]) throws -> Process
    private let controller: AndroidController
    private let start: StartProcess
    private let lock = NSLock()
    private struct State { let device: Device; let config: String; let reversePort: Int? }
    private var states: [String: State] = [:]
    public init(controller: AndroidController = AndroidController(), start: @escaping StartProcess = AndroidRunnerLauncher.startProcess) {
        self.controller = controller; self.start = start
    }
    public struct Connection: Sendable, Equatable {
        public let url: String
        public let reversePort: Int?
    }
    public static func connection(device: Device, gatewayURL: String, environment: [String: String]) throws -> Connection {
        guard device.platform == .android, var url = URLComponents(string: gatewayURL),
              ["http", "https"].contains(url.scheme), url.host != nil,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { throw ScoutError.invalidRequest("URL de gateway Android inválida") }
        // adb TCP/IP serials include a port; USB serials do not. An explicit Wi-Fi override
        // is also available for OEM transports whose serial does not identify the network.
        let wifi = device.kind == .physical && (device.id.contains(":") || device.id.hasSuffix("._adb-tls-connect._tcp") || environment["CUYSCOUT_ANDROID_TRANSPORT"] == "wifi")
        if wifi {
            guard let address = environment["CUYSCOUT_DEVICE_GATEWAY_URL"], let remote = URLComponents(string: address),
                  ["http", "https"].contains(remote.scheme), let host = remote.host,
                  !["localhost", "127.0.0.1", "0.0.0.0", "::1"].contains(host), remote.user == nil, remote.password == nil, remote.query == nil, remote.fragment == nil,
                  let bind = environment["CUYSCOUT_BIND_ADDRESS"], !["localhost", "127.0.0.1", "::1"].contains(bind), !bind.isEmpty,
                  environment["CUYSCOUT_TOKEN"]?.isEmpty == false else {
                throw ScoutError.invalidRequest("Android Wi-Fi requiere CUYSCOUT_BIND_ADDRESS, CUYSCOUT_DEVICE_GATEWAY_URL alcanzable y CUYSCOUT_TOKEN")
            }
            return Connection(url: address, reversePort: nil)
        }
        let port = url.port ?? (url.scheme == "https" ? 443 : 80)
        url.host = device.kind == .simulator ? "10.0.2.2" : "127.0.0.1"
        guard let address = url.string else { throw ScoutError.invalidRequest("URL de gateway Android inválida") }
        return Connection(url: address, reversePort: device.kind == .physical ? port : nil)
    }
    public func launch(_ context: RunnerLaunchContext) throws -> Process {
        let session = context.session, env = context.environment
        guard session.device.platform == .android, session.device.isAvailable, session.device.state != "Shutdown", let package = session.bundleIdentifier, !package.isEmpty,
              session.id.range(of: "^[a-zA-Z0-9_-]+$", options: .regularExpression) != nil else { throw ScoutError.invalidRequest("El runner requiere una sesión Android conectada con applicationId y session ID válidos") }
        guard let adb = controller.toolPath("adb") else { throw ScoutError.unsupported("Falta adb; instala Android SDK platform-tools y configura ANDROID_HOME") }
        let connection = try Self.connection(device: session.device, gatewayURL: context.gatewayURL, environment: env)
        let apk = try Self.apkPaths(environment: env)
        try controller.installApp(apk.host, on: session.device)
        try controller.installApp(apk.test, on: session.device)
        let remote = "/data/local/tmp/cuyscout-\(UUID().uuidString).json"
        let state = State(device: session.device, config: remote, reversePort: connection.reversePort)
        let local = FileManager.default.temporaryDirectory.appendingPathComponent("cuyscout-android-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: local) }
        var config: [String: Any] = ["url": connection.url, "sessionId": session.id, "bundleId": package, "maxSeconds": 600, "preserveRunningApp": context.preserveRunningApp]
        if let activity = session.appActivity { config["appActivity"] = activity }
        if let token = env["CUYSCOUT_TOKEN"], !token.isEmpty { config["token"] = token }
        let data = try JSONSerialization.data(withJSONObject: config)
        guard FileManager.default.createFile(atPath: local.path, contents: data, attributes: [.posixPermissions: 0o600]) else { throw ScoutError.commandFailed("No se pudo guardar la configuración privada del runner") }
        do {
            if let port = connection.reversePort { _ = try controller.adbCommand(["-s", session.device.id, "reverse", "tcp:\(port)", "tcp:\(port)"]) }
            _ = try controller.adbCommand(["-s", session.device.id, "push", local.path, remote])
            _ = try controller.adbCommand(["-s", session.device.id, "shell", "chmod 600 " + AndroidController.quote(remote)])
            if !context.preserveRunningApp { _ = try controller.execute(.terminate(bundleIdentifier: package), on: session.device) }
            let arguments = ["-s", session.device.id, "shell", "am instrument --user " + AndroidController.ownerUser + " -w -e class com.cuycoders.cuyscout.runner.ScoutBridgeTest -e cuyscoutConfig " + AndroidController.quote(remote) + " com.cuycoders.cuyscout.host.test/androidx.test.runner.AndroidJUnitRunner"]
            let process = try start(adb, arguments)
            lock.lock(); states[session.id] = state; lock.unlock()
            return process
        } catch { cleanup(state); throw error }
    }
    public func stop(session: Session, process: Process?) {
        if let process, process.isRunning { process.terminate() }
        lock.lock(); let state = states.removeValue(forKey: session.id); lock.unlock()
        guard let state else { return }
        // Killing the host adb client alone does not stop remote instrumentation.
        _ = try? controller.execute(.terminate(bundleIdentifier: "com.cuycoders.cuyscout.host"), on: state.device)
        cleanup(state)
    }
    private func cleanup(_ state: State) {
        _ = try? controller.adbCommand(["-s", state.device.id, "shell", "rm -f " + AndroidController.quote(state.config)])
        if let port = state.reversePort { _ = try? controller.adbCommand(["-s", state.device.id, "reverse", "--remove", "tcp:\(port)"]) }
    }
    static func apkPaths(environment: [String: String]) throws -> (host: String, test: String) {
        let executable = URL(fileURLWithPath: CommandLine.arguments.first ?? "/").deletingLastPathComponent()
        let bundled = executable.deletingLastPathComponent().appendingPathComponent("Resources/Runner/AndroidRunner/apks")
        let repository = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Runner/AndroidRunner/host/build/outputs/apk")
        let host = environment["CUYSCOUT_ANDROID_HOST_APK"] ?? (FileManager.default.fileExists(atPath: bundled.appendingPathComponent("host-debug.apk").path) ? bundled.appendingPathComponent("host-debug.apk").path : repository.appendingPathComponent("debug/host-debug.apk").path)
        let test = environment["CUYSCOUT_ANDROID_TEST_APK"] ?? (FileManager.default.fileExists(atPath: bundled.appendingPathComponent("host-debug-androidTest.apk").path) ? bundled.appendingPathComponent("host-debug-androidTest.apk").path : repository.appendingPathComponent("androidTest/debug/host-debug-androidTest.apk").path)
        guard FileManager.default.fileExists(atPath: host), FileManager.default.fileExists(atPath: test) else { throw ScoutError.unsupported("Faltan los APK del runner Android: ejecuta Scripts/build_android_runner.sh o configura CUYSCOUT_ANDROID_HOST_APK y CUYSCOUT_ANDROID_TEST_APK") }
        return (host, test)
    }
    public static func startProcess(_ executable: String, _ arguments: [String]) throws -> Process {
        let process = Process(); process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice; process.standardInput = FileHandle.nullDevice
        try process.run(); return process
    }
}
