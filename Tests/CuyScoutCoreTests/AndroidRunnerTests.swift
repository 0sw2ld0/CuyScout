import XCTest
@testable import CuyScoutCore

final class AndroidRunnerTests: XCTestCase {
    private let emulator = Device(id: "emulator-5554", name: "Pixel", runtime: "Android 15", state: "Booted", platform: .android)
    private let usb = Device(id: "FAKE_USB_01", name: "Demo", runtime: "Android 15", state: "Booted", kind: .physical, platform: .android)
    private func context(_ device: Device, environment: [String: String] = [:], preserve: Bool = false) -> RunnerLaunchContext {
        RunnerLaunchContext(session: Session(id: "session-1", device: device, bundleIdentifier: "com.example.wallet", createdAt: Date(), driverID: device.kind == .physical ? "android-device" : "android-emulator"), gatewayURL: "http://127.0.0.1:4799", preserveRunningApp: preserve, environment: environment)
    }
    private func host(_ fake: RunnerCommands) -> AndroidController {
        AndroidController(environment: ["ANDROID_HOME": "/sdk"], isExecutable: { $0 == "/sdk/platform-tools/adb" }, executor: fake.execute)
    }
    private func apks() throws -> (URL, [String: String]) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let host = root.appendingPathComponent("host.apk"), test = root.appendingPathComponent("test.apk")
        try Data().write(to: host); try Data().write(to: test)
        return (root, ["CUYSCOUT_ANDROID_HOST_APK": host.path, "CUYSCOUT_ANDROID_TEST_APK": test.path])
    }

    func testEmulatorUsesSpecialHostAndUSBUsesReverseWithOriginalPort() throws {
        let emu = try AndroidRunnerLauncher.connection(device: emulator, gatewayURL: "http://127.0.0.1:4799", environment: [:])
        XCTAssertEqual(emu.url, "http://10.0.2.2:4799"); XCTAssertNil(emu.reversePort)
        let physical = try AndroidRunnerLauncher.connection(device: usb, gatewayURL: "http://127.0.0.1:4799", environment: [:])
        XCTAssertEqual(physical.url, "http://127.0.0.1:4799"); XCTAssertEqual(physical.reversePort, 4799)
    }
    func testWiFiRequiresLANConfigurationAndBearerToken() throws {
        let wifi = Device(id: "192.0.2.10:5555", name: "Demo", runtime: "Android", state: "Booted", kind: .physical, platform: .android)
        let env = ["CUYSCOUT_DEVICE_GATEWAY_URL": "http://192.0.2.20:4799", "CUYSCOUT_BIND_ADDRESS": "0.0.0.0", "CUYSCOUT_TOKEN": "test-token"]
        let connection = try AndroidRunnerLauncher.connection(device: wifi, gatewayURL: "http://127.0.0.1:4799", environment: env)
        XCTAssertEqual(connection.url, "http://192.0.2.20:4799"); XCTAssertNil(connection.reversePort)
        for key in env.keys { var missing = env; missing.removeValue(forKey: key); XCTAssertThrowsError(try AndroidRunnerLauncher.connection(device: wifi, gatewayURL: "http://127.0.0.1:4799", environment: missing)) }
        XCTAssertThrowsError(try AndroidRunnerLauncher.connection(device: wifi, gatewayURL: "http://user:secret@127.0.0.1:4799", environment: env))
    }
    func testLaunchInstallsBothAPKsProtectsConfigAndKeepsTokenOutOfArguments() throws {
        let (root, env) = try apks(); defer { try? FileManager.default.removeItem(at: root) }
        let fake = RunnerCommands(), starter = RunnerStarter()
        let launcher = AndroidRunnerLauncher(controller: host(fake), start: starter.start)
        var tokenEnv = env; tokenEnv["CUYSCOUT_TOKEN"] = "test-token"
        _ = try launcher.launch(context(usb, environment: tokenEnv))
        XCTAssertEqual(fake.commands.filter { $0.arguments.contains("install") }.count, 2)
        XCTAssertTrue(fake.commands.contains { $0.arguments == ["-s", usb.id, "reverse", "tcp:4799", "tcp:4799"] })
        XCTAssertTrue(fake.commands.contains { $0.arguments.last?.hasPrefix("chmod 600 ") == true })
        XCTAssertEqual(fake.config?["token"] as? String, "test-token")
        XCTAssertEqual(fake.config?["url"] as? String, "http://127.0.0.1:4799")
        XCTAssertEqual(fake.permissions, 0o600)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(fake.localConfig)))
        XCTAssertFalse(starter.arguments.joined().contains("test-token"))
        XCTAssertTrue(starter.arguments.last?.contains("am instrument --user 0 -w") == true)
        XCTAssertTrue(starter.arguments.last?.contains("androidx.test.runner.AndroidJUnitRunner") == true)
        launcher.stop(session: context(usb).session, process: nil)
        XCTAssertTrue(fake.commands.contains { $0.arguments.last == "'am' 'force-stop' '--user' '0' 'com.cuycoders.cuyscout.host'" })
        XCTAssertTrue(fake.commands.contains { $0.arguments == ["-s", usb.id, "reverse", "--remove", "tcp:4799"] })
    }
    func testTheRunnerIsNotReinstalledWhileTheAPKsOnThePhoneAreTheSame() throws {
        let (root, env) = try apks(); defer { try? FileManager.default.removeItem(at: root) }
        let fake = RunnerCommands(), starter = RunnerStarter()
        let launcher = AndroidRunnerLauncher(controller: host(fake), start: starter.start)
        _ = try launcher.launch(context(usb, environment: env))
        XCTAssertEqual(fake.commands.filter { $0.arguments.contains("install") }.count, 2, "la primera vez se instalan los dos")
        let markers = fake.commands.compactMap { $0.arguments.last }.filter { $0.hasPrefix("echo ") && $0.contains("cuyscout-installed-") }
        XCTAssertEqual(markers.count, 2, "recuerda qué APK dejó instalado")
        // El teléfono ya los tiene, con la misma huella: no se vuelve a instalar (Play Protect preguntaría otra vez).
        let installed = RunnerCommands(); installed.installed = ["com.cuycoders.cuyscout.host", "com.cuycoders.cuyscout.host.test"]
        installed.recorded = markers.map { String($0.dropFirst(5).prefix(while: { $0 != " " })) }
        let again = AndroidRunnerLauncher(controller: host(installed), start: starter.start)
        _ = try again.launch(context(usb, environment: env))
        XCTAssertFalse(installed.commands.contains { $0.arguments.contains("install") }, "con el mismo APK no se reinstala")
        // Si el APK cambia, se instala de nuevo.
        try Data([1]).write(to: URL(fileURLWithPath: try XCTUnwrap(env["CUYSCOUT_ANDROID_HOST_APK"])))
        let changed = RunnerCommands(); changed.installed = installed.installed; changed.recorded = installed.recorded
        _ = try AndroidRunnerLauncher(controller: host(changed), start: starter.start).launch(context(usb, environment: env))
        XCTAssertEqual(changed.commands.filter { $0.arguments.contains("install") }.count, 1, "solo el APK que cambió")
    }
    func testPreserveSkipsTargetForceStopAndEmulatorDoesNotUseReverse() throws {
        let (root, env) = try apks(); defer { try? FileManager.default.removeItem(at: root) }
        let fake = RunnerCommands(), starter = RunnerStarter(), launcher = AndroidRunnerLauncher(controller: host(fake), start: starter.start)
        let launch = context(emulator, environment: env, preserve: true)
        _ = try launcher.launch(launch)
        XCTAssertFalse(fake.commands.contains { $0.arguments.contains("reverse") || $0.arguments.last == "'am' 'force-stop' 'com.example.wallet'" })
        XCTAssertEqual(fake.config?["url"] as? String, "http://10.0.2.2:4799")
        launcher.stop(session: launch.session, process: nil)
    }
    func testFailedStartRemovesRemoteConfigAndReverseAndLocalCredentials() throws {
        let (root, env) = try apks(); defer { try? FileManager.default.removeItem(at: root) }
        let fake = RunnerCommands(), launcher = AndroidRunnerLauncher(controller: host(fake), start: { _, _ in throw ScoutError.commandFailed("start failed") })
        XCTAssertThrowsError(try launcher.launch(context(usb, environment: env)))
        XCTAssertTrue(fake.commands.contains { $0.arguments.last?.hasPrefix("rm -f ") == true })
        XCTAssertTrue(fake.commands.contains { $0.arguments == ["-s", usb.id, "reverse", "--remove", "tcp:4799"] })
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(fake.localConfig)))
    }
    func testMissingAPKsAndInvalidSessionsFailBeforeStartingInstrumentation() {
        let fake = RunnerCommands(), starter = RunnerStarter(), launcher = AndroidRunnerLauncher(controller: host(fake), start: starter.start)
        XCTAssertThrowsError(try launcher.launch(context(emulator, environment: ["CUYSCOUT_ANDROID_HOST_APK": "/missing.apk", "CUYSCOUT_ANDROID_TEST_APK": "/missing-test.apk"])))
        let invalid = Session(id: "../bad", device: emulator, bundleIdentifier: "com.example.wallet", createdAt: Date())
        XCTAssertThrowsError(try launcher.launch(RunnerLaunchContext(session: invalid, gatewayURL: "http://127.0.0.1:4799")))
        XCTAssertTrue(fake.commands.isEmpty); XCTAssertTrue(starter.arguments.isEmpty)
    }
    func testEngineDispatchesThroughPlatformInterfaceAndStopsTheChosenLauncher() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let launcher = FakePlatformLauncher()
        let engine = ScoutEngine(artifactStore: ArtifactStore(directory: root), runnerLaunchers: [.ios: launcher])
        let session = try engine.createSession(deviceID: nil, bundleIdentifier: "com.example.wallet")
        try engine.launchRunner(sessionID: session.id, preserveRunningApp: true)
        try engine.launchRunner(sessionID: session.id)
        XCTAssertEqual(launcher.contexts.count, 1)
        XCTAssertEqual(launcher.contexts.first?.session.device.platform, .ios)
        XCTAssertEqual(launcher.contexts.first?.preserveRunningApp, true)
        try engine.deleteSession(session.id); XCTAssertEqual(launcher.stopped, [session.id])
    }
    func testAndroidTreeContractFlowsThroughObserveWithoutChangingAgentShape() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "runner-tree", withExtension: "json", subdirectory: "Fixtures/android"))
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let elements = try XCTUnwrap(object["elements"] as? [[String: Any]])
        XCTAssertEqual(ScoutEngine().visibleTextsForTesting(elements), ["Demo Wallet", "email: Email"])
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let engine = ScoutEngine(artifactStore: ArtifactStore(directory: root))
        let session = try engine.createSession(deviceID: nil, bundleIdentifier: "com.example.wallet")
        defer { try? engine.deleteSession(session.id) }
        try engine.registerBridge(sessionID: session.id); _ = try engine.pollBridge(sessionID: session.id)
        let worker = expectation(description: "Android contract payload")
        DispatchQueue.global().async {
            defer { worker.fulfill() }
            let deadline = Date().addingTimeInterval(5)
            while Date() < deadline {
                if let command = try? engine.pollBridge(sessionID: session.id) {
                    try? engine.completeBridge(sessionID: session.id, result: BridgeResult(commandID: command.id, success: true, payloadBase64: data.base64EncodedString())); return
                }
                Thread.sleep(forTimeInterval: 0.01)
            }
        }
        let observation = try engine.observe(sessionID: session.id)
        wait(for: [worker], timeout: 6)
        XCTAssertTrue(observation.actions.contains { $0.action == .tapElement(.init(strategy: .accessibilityIdentifier, value: "login")) })
        XCTAssertTrue(observation.actions.contains { $0.action == .typeElement(.init(strategy: .accessibilityIdentifier, value: "email"), text: "<text>") })
        XCTAssertEqual(observation.texts, ["Demo Wallet", "email: Email"])
    }
    func testRunnerErrorCodesPreserveW3CUnsupportedAndNoSuchElement() throws {
        for (code, expected) in [(7, "unsupported command"), (8, "no such element"), (10, "element not interactable"), (11, "element not interactable")] {
            let bridge = BridgeState(sessionID: "s"); _ = bridge.poll()
            let worker = expectation(description: "code \(code)")
            DispatchQueue.global().async {
                defer { worker.fulfill() }
                let deadline = Date().addingTimeInterval(3)
                while Date() < deadline {
                    if let command = bridge.poll() { bridge.complete(BridgeResult(commandID: command.id, success: false, error: "Safe error", errorCode: code)); return }
                    Thread.sleep(forTimeInterval: 0.005)
                }
            }
            XCTAssertThrowsError(try bridge.execute(BridgeCommand(action: .accessibilityTree))) { error in XCTAssertEqual((error as? ScoutError)?.w3cCode, expected) }
            wait(for: [worker], timeout: 4)
        }
    }
}

private final class RunnerCommands: @unchecked Sendable {
    var commands: [AndroidController.Command] = []
    var config: [String: Any]?
    var localConfig: String?
    var permissions: Int?
    /// Paquetes que el teléfono simulado ya tiene y huellas recordadas (en orden host, test).
    var installed: [String] = []
    var recorded: [String] = []
    func execute(_ command: AndroidController.Command) throws -> AndroidController.Output {
        commands.append(command)
        if command.arguments.contains(where: { $0.contains("pm' 'list' 'packages") }) { return .init(stdout: Data(installed.map { "package:\($0)" }.joined(separator: "\n").utf8)) }
        if let last = command.arguments.last, last.hasPrefix("'cat' '/data/local/tmp/cuyscout-installed-") {
            let isTest = last.contains("host.test.sha256")
            return .init(stdout: Data((recorded.count == 2 ? recorded[isTest ? 1 : 0] : "").utf8))
        }
        if command.arguments.count >= 5 && command.arguments[2] == "push" {
            let path = command.arguments[3]; localConfig = path
            config = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as? [String: Any]
            permissions = (try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? NSNumber)?.intValue
        }
        return .init()
    }
}
private final class RunnerStarter: @unchecked Sendable {
    var arguments: [String] = []
    func start(_ executable: String, _ arguments: [String]) throws -> Process { self.arguments = arguments; return Process() }
}
private final class FakePlatformLauncher: RunnerLaunching, @unchecked Sendable {
    var contexts: [RunnerLaunchContext] = []
    var stopped: [String] = []
    func launch(_ context: RunnerLaunchContext) throws -> Process { contexts.append(context); return Process() }
    func stop(session: Session, process: Process?) { stopped.append(session.id) }
}

/// Los APK del runner viven dentro de CuyScout.app; el gateway debe hallarlos aunque se lance por un
/// enlace simbólico, por nombre desde el PATH o desde otra carpeta.
final class AndroidRunnerAPKLocationTests: XCTestCase {
    private func makeApp(in root: URL) throws -> URL {
        let apks = root.appendingPathComponent("CuyScout.app/Contents/Resources/Runner/AndroidRunner/apks")
        try FileManager.default.createDirectory(at: apks, withIntermediateDirectories: true)
        for name in ["host-debug.apk", "host-debug-androidTest.apk"] { FileManager.default.createFile(atPath: apks.appendingPathComponent(name).path, contents: Data([0])) }
        let macOS = root.appendingPathComponent("CuyScout.app/Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: macOS.appendingPathComponent("cuyscout").path, contents: Data([0]))
        return macOS.appendingPathComponent("cuyscout")
    }

    func testFindsBundledAPKsWhenLaunchedThroughASymlink() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cuyscout-apk-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let binary = try makeApp(in: root)
        let bin = root.appendingPathComponent("bin"); try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let link = bin.appendingPathComponent("cuyscout")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: binary)
        let direct = try AndroidRunnerLauncher.apkPaths(environment: [:], executablePath: binary.path, currentDirectory: "/nowhere", home: "/nohome")
        let viaLink = try AndroidRunnerLauncher.apkPaths(environment: [:], executablePath: link.path, currentDirectory: "/nowhere", home: "/nohome")
        XCTAssertTrue(direct.host.hasSuffix("Resources/Runner/AndroidRunner/apks/host-debug.apk"))
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), binary.path)
        XCTAssertEqual(URL(fileURLWithPath: viaLink.host).resolvingSymlinksInPath().path, URL(fileURLWithPath: direct.host).resolvingSymlinksInPath().path)
    }

    func testFallsBackToTheInstalledAppAndHonoursEnvironmentOverrides() throws {
        let installed = "/Applications/CuyScout.app/Contents/Resources/Runner/AndroidRunner/apks"
        let found = try AndroidRunnerLauncher.apkPaths(environment: [:], executablePath: "cuyscout", currentDirectory: "/elsewhere", home: "/nohome",
                                                       exists: { $0.hasPrefix(installed) })
        XCTAssertEqual(found.host, installed + "/host-debug.apk")
        XCTAssertEqual(found.test, installed + "/host-debug-androidTest.apk")
        let overridden = try AndroidRunnerLauncher.apkPaths(environment: ["CUYSCOUT_ANDROID_HOST_APK": "/x/h.apk", "CUYSCOUT_ANDROID_TEST_APK": "/x/t.apk"],
                                                            executablePath: "cuyscout", currentDirectory: "/elsewhere", home: "/nohome", exists: { $0.hasPrefix("/x/") })
        XCTAssertEqual(overridden.host, "/x/h.apk")
    }

    func testMissingAPKsExplainHowToFixItForInstalledUsers() {
        XCTAssertThrowsError(try AndroidRunnerLauncher.apkPaths(environment: [:], executablePath: "cuyscout", currentDirectory: "/e", home: "/h", exists: { _ in false })) {
            XCTAssertTrue("\($0)".contains("DMG") && "\($0)".contains("/Applications/CuyScout.app"))
        }
    }
}
