import XCTest
@testable import CuyScoutCore

final class AndroidSessionTests: XCTestCase {
    private func engine(_ fake: SessionADB, launcher: SessionLauncher = SessionLauncher()) -> ScoutEngine {
        let controller = AndroidController(environment: ["ANDROID_HOME": "/sdk"], homeDirectory: "/missing", isExecutable: { ["/sdk/platform-tools/adb", "/sdk/emulator/emulator"].contains($0) }, executor: fake.execute)
        return ScoutEngine(artifactStore: ArtifactStore(directory: fake.root), androidController: controller, runnerLaunchers: [.android: launcher])
    }
    private func open(_ engine: ScoutEngine, _ input: [String: Any]) throws -> Session {
        let caps = try CapabilityNegotiator.negotiate(input)
        let driver = try engine.sessionDriverID(capabilities: caps)
        return try engine.createSession(deviceID: caps["appium:udid"] as? String, bundleIdentifier: caps["appium:appPackage"] as? String, deviceName: (caps["appium:avd"] ?? caps["appium:deviceName"]) as? String, runtime: caps["appium:platformVersion"] as? String, driverID: driver, appActivity: caps["appium:appActivity"] as? String)
    }
    func testAndroidAliasesSelectEmulatorAndExposeActualCapabilities() throws {
        let fake = SessionADB(); defer { fake.cleanup() }
        let e = engine(fake)
        let session = try open(e, ["appium:platformName": "Android", "avd": "Pixel", "appPackage": "com.example.wallet", "appActivity": ".LoginActivity"])
        defer { try? e.deleteSession(session.id) }
        XCTAssertEqual(session.driverID, "android-emulator")
        XCTAssertEqual(session.device.id, "emulator-5554")
        let caps = try e.sessionCapabilities(sessionID: session.id)
        XCTAssertEqual(caps["platformName"] as? String, "Android")
        XCTAssertEqual(caps["appium:automationName"] as? String, "UiAutomator2")
        XCTAssertEqual(caps["appium:appPackage"] as? String, "com.example.wallet")
        XCTAssertEqual(caps["appium:appActivity"] as? String, ".LoginActivity")
        XCTAssertEqual(caps["appium:bundleId"] as? String, "com.example.wallet")
    }
    func testPhysicalSerialSelectsDeviceDriverAndDispatchesAndroidRunner() throws {
        let fake = SessionADB(), launcher = SessionLauncher(); defer { fake.cleanup() }
        let e = engine(fake, launcher: launcher)
        let session = try open(e, ["platformName": "Android", "udid": "USB_FAKE", "appPackage": "com.example.wallet"])
        XCTAssertEqual(session.driverID, "android-device")
        try e.launchRunner(sessionID: session.id, preserveRunningApp: true)
        XCTAssertEqual(launcher.contexts.first?.session.device.platform, .android)
        XCTAssertEqual(launcher.contexts.first?.preserveRunningApp, true)
        try e.deleteSession(session.id)
        XCTAssertEqual(launcher.stopped, [session.id]); XCTAssertTrue(e.schedulerLeases().isEmpty)
    }
    /// El runner responde `not_visible` cuando el campo real es transparente bajo un texto dibujado (React Native).
    private func typeWithRunnerRejecting(_ action: ScoutAction, keyboardOpen: Bool, fake: SessionADB) throws -> Result<Void, Error> {
        fake.keyboardOpen = keyboardOpen
        let e = engine(fake)
        let session = try open(e, ["platformName": "Android", "udid": "USB_FAKE", "appPackage": "com.example.wallet"])
        defer { try? e.deleteSession(session.id) }
        try e.registerBridge(sessionID: session.id); _ = try e.pollBridge(sessionID: session.id)
        let worker = expectation(description: "runner rejects")
        DispatchQueue.global().async {
            defer { worker.fulfill() }
            let deadline = Date().addingTimeInterval(5)
            while Date() < deadline {
                if let command = try? e.pollBridge(sessionID: session.id) {
                    try? e.completeBridge(sessionID: session.id, result: BridgeResult(commandID: command.id, success: false, payloadBase64: nil, error: "not_visible: el elemento está oculto", errorCode: 10)); return
                }
                Thread.sleep(forTimeInterval: 0.01)
            }
        }
        defer { wait(for: [worker], timeout: 6) }
        do { _ = try e.perform(action, sessionID: session.id); return .success(()) } catch { return .failure(error) }
    }
    func testTypingFallsBackToAdbWhenTheFieldIsNotEditableAndTheKeyboardIsOpen() throws {
        let fake = SessionADB(); defer { fake.cleanup() }
        let amount = ScoutSelector(strategy: .accessibilityIdentifier, value: "amount-input.input")
        let result = try typeWithRunnerRejecting(.typeElement(amount, text: "10.00"), keyboardOpen: true, fake: fake)
        if case .failure(let error) = result { XCTFail("debía escribir por adb: \(error)") }
        let shell = fake.commands.compactMap { $0.arguments.last }
        XCTAssertTrue(shell.contains("'input' 'text' '10.00'"))
        XCTAssertTrue(shell.contains("'input' 'keyevent' 'KEYCODE_BACK'"), "debe cerrar el teclado como lo hace el runner")
    }
    func testTypingDoesNotUseAdbWithoutAnOpenKeyboardOrOnSecretFields() throws {
        let amount = ScoutSelector(strategy: .accessibilityIdentifier, value: "amount-input.input")
        let closed = SessionADB(); defer { closed.cleanup() }
        let noKeyboard = try typeWithRunnerRejecting(.typeElement(amount, text: "10.00"), keyboardOpen: false, fake: closed)
        guard case .failure(let error) = noKeyboard else { return XCTFail("sin teclado abierto no hay campo enfocado: debe fallar") }
        XCTAssertTrue("\(error)".contains("not_visible") && "\(error)".contains("abrir el teclado"))
        XCTAssertFalse(closed.commands.contains { ($0.arguments.last ?? "").contains("'input' 'text'") })
        let secret = SessionADB(); defer { secret.cleanup() }
        let password = ScoutSelector(strategy: .accessibilityIdentifier, value: "login-password")
        guard case .failure = try typeWithRunnerRejecting(.typeElement(password, text: "s3cret"), keyboardOpen: true, fake: secret) else { return XCTFail("un campo de clave no debe escribirse por adb") }
        XCTAssertFalse(secret.commands.contains { ($0.arguments.last ?? "").contains("'input' 'text'") }, "la clave no debe pasar por adb: queda en el log del dispositivo")
    }
    // MARK: pressKey, hideKeyboard, eraseText y scrollUntilVisible

    private func androidSession(_ fake: SessionADB) throws -> (ScoutEngine, Session) {
        let e = engine(fake)
        return (e, try open(e, ["platformName": "Android", "udid": "USB_FAKE", "appPackage": "com.example.wallet"]))
    }
    func testKeyboardActionsRunThroughAdbAndOnlyWhenTheyMakeSense() throws {
        let fake = SessionADB(); defer { fake.cleanup() }
        let (e, session) = try androidSession(fake); defer { try? e.deleteSession(session.id) }
        _ = try e.perform(.pressKey("enter"), sessionID: session.id)
        XCTAssertTrue(fake.commands.contains { $0.arguments.last == "'input' 'keyevent' 'KEYCODE_ENTER'" })
        XCTAssertThrowsError(try e.perform(.pressKey("volumeup"), sessionID: session.id)) { XCTAssertTrue("\($0)".contains("Tecla no admitida")) }
        // Con el teclado abierto, hideKeyboard envía Atrás; con el teclado cerrado no hace nada (Atrás haría navegar).
        fake.keyboardOpen = true; fake.commands = []
        _ = try e.perform(.hideKeyboard, sessionID: session.id)
        XCTAssertEqual(fake.commands.filter { ($0.arguments.last ?? "").contains("KEYCODE_BACK") }.count, 1)
        fake.commands = []
        _ = try e.perform(.hideKeyboard, sessionID: session.id)
        XCTAssertFalse(fake.commands.contains { ($0.arguments.last ?? "").contains("KEYCODE_BACK") })
    }
    func testEraseTextNeedsAFocusedFieldAndSendsOneCommand() throws {
        let fake = SessionADB(); defer { fake.cleanup() }
        let (e, session) = try androidSession(fake); defer { try? e.deleteSession(session.id) }
        fake.keyboardOpen = false
        XCTAssertThrowsError(try e.perform(.eraseText(count: 5), sessionID: session.id)) { XCTAssertTrue("\($0)".contains("teclado abierto")) }
        fake.keyboardOpen = true; fake.commands = []
        _ = try e.perform(.eraseText(count: 3), sessionID: session.id)
        let erase = fake.commands.compactMap { $0.arguments.last }.filter { $0.contains("KEYCODE_MOVE_END") }
        XCTAssertEqual(erase, ["'input' 'keyevent' 'KEYCODE_MOVE_END' 'KEYCODE_DEL' 'KEYCODE_DEL' 'KEYCODE_DEL'"])
        XCTAssertThrowsError(try e.perform(.eraseText(count: 0), sessionID: session.id))
        XCTAssertThrowsError(try e.perform(.eraseText(count: 201), sessionID: session.id))
    }
    private final class Scroller: @unchecked Sendable { var finds = 0, scrolls: [Double] = [] }
    private func scrollRunner(_ e: ScoutEngine, _ session: Session, foundOnFind: Int, _ state: Scroller) -> XCTestExpectation {
        let worker = expectation(description: "runner")
        DispatchQueue.global().async {
            defer { worker.fulfill() }
            let deadline = Date().addingTimeInterval(8)
            while Date() < deadline {
                guard let command = try? e.pollBridge(sessionID: session.id) else { Thread.sleep(forTimeInterval: 0.005); continue }
                switch command.action {
                case .findElement:
                    state.finds += 1
                    let found = state.finds >= foundOnFind
                    let payload = found ? Data("{\"element\":{\"type\":\"button\",\"identifier\":\"target\"}}".utf8).base64EncodedString() : nil
                    try? e.completeBridge(sessionID: session.id, result: BridgeResult(commandID: command.id, success: found, payloadBase64: payload, error: found ? nil : "no existe", errorCode: found ? nil : 8))
                    if found { return }
                case .scroll(_, let y):
                    state.scrolls.append(y)
                    try? e.completeBridge(sessionID: session.id, result: BridgeResult(commandID: command.id, success: true, payloadBase64: nil))
                default:
                    try? e.completeBridge(sessionID: session.id, result: BridgeResult(commandID: command.id, success: true, payloadBase64: nil))
                }
            }
        }
        return worker
    }
    func testScrollUntilVisibleScrollsUntilTheElementAppears() throws {
        let fake = SessionADB(); defer { fake.cleanup() }
        let (e, session) = try androidSession(fake); defer { try? e.deleteSession(session.id) }
        try e.registerBridge(sessionID: session.id); _ = try e.pollBridge(sessionID: session.id)
        let state = Scroller(); let worker = scrollRunner(e, session, foundOnFind: 3, state)
        let target = ScoutSelector(strategy: .accessibilityIdentifier, value: "target")
        XCTAssertNotNil(try e.perform(.scrollUntilVisible(target, direction: "down", maxScrolls: 5), sessionID: session.id))
        wait(for: [worker], timeout: 10)
        XCTAssertEqual(state.finds, 3); XCTAssertEqual(state.scrolls, [400, 400], "dos desplazamientos hacia abajo antes de encontrarlo")
    }
    func testScrollUntilVisibleGivesUpWithAUsefulMessageAndSupportsUp() throws {
        let fake = SessionADB(); defer { fake.cleanup() }
        let (e, session) = try androidSession(fake); defer { try? e.deleteSession(session.id) }
        try e.registerBridge(sessionID: session.id); _ = try e.pollBridge(sessionID: session.id)
        let state = Scroller(); let worker = scrollRunner(e, session, foundOnFind: 99, state)
        let missing = ScoutSelector(strategy: .label, value: "No existe")
        XCTAssertThrowsError(try e.perform(.scrollUntilVisible(missing, direction: "up", maxScrolls: 2), sessionID: session.id)) {
            XCTAssertTrue("\($0)".contains("tras 2 desplazamientos hacia arriba"), "\($0)")
        }
        XCTAssertEqual(state.scrolls, [-400, -400]); XCTAssertEqual(state.finds, 3)
        XCTAssertThrowsError(try e.perform(.scrollUntilVisible(missing, direction: "left", maxScrolls: 2), sessionID: session.id))
        XCTAssertThrowsError(try e.perform(.scrollUntilVisible(missing, direction: "down", maxScrolls: 31), sessionID: session.id))
        try? e.deleteSession(session.id); wait(for: [worker], timeout: 10)
    }
    func testNewActionsRoundTripAndTakeDefaults() throws {
        let decode = { (json: String) throws -> ScoutAction in try JSONDecoder().decode(ScoutAction.self, from: Data(json.utf8)) }
        XCTAssertEqual(try decode(#"{"type":"pressKey","key":"enter"}"#), .pressKey("enter"))
        XCTAssertEqual(try decode(#"{"type":"hideKeyboard"}"#), .hideKeyboard)
        XCTAssertEqual(try decode(#"{"type":"eraseText"}"#), .eraseText(count: 50))
        XCTAssertEqual(try decode(#"{"type":"eraseText","count":8}"#), .eraseText(count: 8))
        let target = ScoutSelector(strategy: .label, value: "Ver más")
        XCTAssertEqual(try decode(#"{"type":"scrollUntilVisible","selector":{"strategy":"label","value":"Ver más"}}"#), .scrollUntilVisible(target, direction: "down", maxScrolls: 8))
        for action in [ScoutAction.pressKey("back"), .hideKeyboard, .eraseText(count: 3), .scrollUntilVisible(target, direction: "up", maxScrolls: 4)] {
            XCTAssertEqual(try JSONDecoder().decode(ScoutAction.self, from: JSONEncoder().encode(action)), action)
        }
    }
    func testConflictingDriverPlatformIsRejectedBeforeAnyCommand() throws {
        let fake = SessionADB(); defer { fake.cleanup() }
        let e = engine(fake)
        XCTAssertThrowsError(try e.sessionDriverID(capabilities: ["platformName": "Android", "appium:driverId": "ios-device"]))
        XCTAssertTrue(fake.commands.isEmpty)
    }
    func testBootRebindsAVDLeaseToSerialAndPreventsSecondSession() throws {
        let fake = SessionADB(); fake.booted = false; defer { fake.cleanup() }
        let e = engine(fake)
        let session = try open(e, ["platformName": "Android", "avd": "Pixel"])
        XCTAssertEqual(session.device.id, "emulator-5554")
        XCTAssertEqual(e.schedulerLeases().map(\.deviceID), ["emulator-5554"])
        XCTAssertTrue(fake.commands.contains { $0.arguments == ["-avd", "Pixel"] })
        XCTAssertThrowsError(try open(e, ["platformName": "Android", "avd": "Pixel"]))
        try e.deleteSession(session.id)
        XCTAssertTrue(e.schedulerLeases().isEmpty)
    }
    func testStoppedAVDValidatesRequestedRuntimeAfterBoot() throws {
        let fake = SessionADB(); fake.booted = false; defer { fake.cleanup() }
        let e = engine(fake)
        XCTAssertThrowsError(try open(e, ["platformName": "Android", "avd": "Pixel", "platformVersion": "99"]))
        XCTAssertTrue(e.schedulerLeases().isEmpty)
        let session = try open(e, ["platformName": "Android", "avd": "Pixel", "platformVersion": "15"])
        try e.deleteSession(session.id)
    }
    func testInstallAPKGoesToTheEmulatorOrThePhoneWithoutOpeningASession() throws {
        let fake = SessionADB(); defer { fake.cleanup() }
        let e = engine(fake), apk = try fake.apk()
        XCTAssertEqual(try e.installAPK(deviceID: "emulator-5554", apkPath: apk).name, "Pixel")
        XCTAssertEqual(try e.installAPK(deviceID: "Pixel", apkPath: apk).id, "emulator-5554", "también por el nombre del AVD")
        XCTAssertEqual(try e.installAPK(deviceID: "USB_FAKE", apkPath: apk).name, "Demo")
        let installs = fake.commands.filter { $0.arguments.contains("install") }.map(\.arguments)
        XCTAssertEqual(installs.map { Array($0.prefix(2)) }, [["-s", "emulator-5554"], ["-s", "emulator-5554"], ["-s", "USB_FAKE"]])
        XCTAssertTrue(e.activeSessions().isEmpty, "instalar no abre ni deja sesiones")
    }
    func testInstallAPKRefusesWhatWouldReplaceTheAppUnderTest() throws {
        let fake = SessionADB(); defer { fake.cleanup() }
        let e = engine(fake), apk = try fake.apk()
        let session = try open(e, ["platformName": "Android", "avd": "Pixel"])
        let before = fake.commands.count
        XCTAssertThrowsError(try e.installAPK(deviceID: "emulator-5554", apkPath: apk)) { XCTAssertTrue("\($0)".contains("sesión activa"), "\($0)") }
        XCTAssertEqual(fake.commands.dropFirst(before).filter { $0.arguments.contains("install") }.count, 0)
        try e.deleteSession(session.id)
        XCTAssertNoThrow(try e.installAPK(deviceID: "emulator-5554", apkPath: apk), "con la sesión cerrada, sí")
    }
    func testInstallAPKRejectsAStoppedAVDAnUnknownDeviceAndANonAPK() throws {
        let stopped = SessionADB(); stopped.booted = false; defer { stopped.cleanup() }
        let apk = try stopped.apk()
        XCTAssertThrowsError(try engine(stopped).installAPK(deviceID: "Pixel", apkPath: apk), "un AVD apagado hay que encenderlo antes")
        XCTAssertFalse(stopped.commands.contains { $0.arguments.contains("install") })
        let running = SessionADB(); defer { running.cleanup() }
        let e = engine(running)
        XCTAssertThrowsError(try e.installAPK(deviceID: "NoExiste", apkPath: try running.apk())) { XCTAssertTrue("\($0)".contains("NoExiste"), "\($0)") }
        let notAPK = running.root.appendingPathComponent("wallet.txt"); try Data().write(to: notAPK)
        XCTAssertThrowsError(try e.installAPK(deviceID: "emulator-5554", apkPath: notAPK.path))
        XCTAssertThrowsError(try e.installAPK(deviceID: "emulator-5554", apkPath: running.root.appendingPathComponent("falta.apk").path))
    }
    func testEngineBootsAStoppedAVDByNameThroughTheAndroidController() throws {
        let fake = SessionADB(); fake.booted = false; defer { fake.cleanup() }
        let e = engine(fake)
        try e.bootDevice(deviceID: "Pixel")
        XCTAssertEqual(fake.commands.filter { $0.arguments == ["-avd", "Pixel"] }.count, 1, "se lanza el emulador una vez")
        XCTAssertFalse(fake.commands.contains { $0.arguments.first == "simctl" }, "un AVD no pasa por simctl")
    }
    func testBootingARunningAVDDoesNotLaunchAnotherEmulator() throws {
        let fake = SessionADB(); fake.booted = true; defer { fake.cleanup() }
        let e = engine(fake)
        try e.bootDevice(deviceID: "Pixel")
        XCTAssertFalse(fake.commands.contains { $0.arguments.first == "-avd" })
    }
    func testBootFailureReleasesReservation() throws {
        let fake = SessionADB(); fake.booted = false; fake.failBoot = true; defer { fake.cleanup() }
        let e = engine(fake)
        XCTAssertThrowsError(try open(e, ["platformName": "Android", "avd": "Pixel"]))
        XCTAssertTrue(e.schedulerLeases().isEmpty)
    }
    func testIOSOnlyCapabilitiesAreDroppedWithValueFreeWarnings() throws {
        let caps = try CapabilityNegotiator.negotiate(["platformName": "Android", "xcodeOrgId": "private-team", "appium:wdaLocalPort": 8000, "appium:automationName": "UiAutomator2"])
        XCTAssertNil(caps["xcodeOrgId"]); XCTAssertNil(caps["appium:xcodeOrgId"]); XCTAssertNil(caps["appium:wdaLocalPort"])
        let warnings = try XCTUnwrap(caps["cuyscout:capabilityWarnings"] as? [String])
        XCTAssertEqual(warnings.count, 2); XCTAssertFalse(warnings.joined().contains("private-team"))
        XCTAssertThrowsError(try CapabilityNegotiator.negotiate(["platformName": "Android", "appium:automationName": "XCUITest"]))
        XCTAssertThrowsError(try CapabilityNegotiator.negotiate(["platformName": "Android", "appium:appActivity": 1]))
    }
    func testReadinessAddsNeutralAliasesAndDecodesLegacySnapshot() throws {
        let fake = SessionADB(); defer { fake.cleanup() }
        let e = engine(fake), session = try open(e, ["platformName": "Android"])
        defer { try? e.deleteSession(session.id) }
        try e.registerBridge(sessionID: session.id)
        let readiness = try e.sessionReadiness(sessionID: session.id)
        XCTAssertTrue(readiness.blockers.contains("xctest_runner_starting"))
        XCTAssertTrue(readiness.blockers.contains("runner_starting"))
        XCTAssertEqual(readiness.bridgeConnected, readiness.xctestBridgeConnected)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(readiness)) as? [String: Any])
        XCTAssertEqual(json["bridgeConnected"] as? Bool, true)
        XCTAssertEqual(json["xctestBridgeConnected"] as? Bool, true)
        json.removeValue(forKey: "bridgeConnected")
        XCTAssertEqual(try JSONDecoder().decode(SessionReadiness.self, from: JSONSerialization.data(withJSONObject: json)), readiness)
        _ = try e.pollBridge(sessionID: session.id)
        XCTAssertTrue(try e.sessionReadiness(sessionID: session.id).interactionReady)
    }
    func testAndroidAppInstallResetAndUninstallNeverUseIOSHostTools() throws {
        let fake = SessionADB(); defer { fake.cleanup() }
        let e = engine(fake), session = try open(e, ["platformName": "Android", "appPackage": "com.example.wallet"])
        defer { try? e.deleteSession(session.id) }
        let path = try fake.apk()
        try e.installApp(sessionID: session.id, path: path)
        XCTAssertTrue(try e.isAppInstalled(sessionID: session.id))
        try e.resetApp(sessionID: session.id, bundleIdentifier: "com.example.wallet")
        try e.uninstallApp(sessionID: session.id, bundleIdentifier: "com.example.wallet")
        XCTAssertFalse(try e.isAppInstalled(sessionID: session.id))
        XCTAssertTrue(fake.commands.allSatisfy { $0.executable.hasPrefix("/sdk/") })
    }
    func testPrepareAPKRequiresPackageAndPreservesDeviceSelection() throws {
        let fake = SessionADB(); defer { fake.cleanup() }
        let e = engine(fake), path = try fake.apk()
        XCTAssertThrowsError(try e.prepareInstaller(appPath: path, deviceID: nil, bundleIdentifier: nil, driverID: "android-emulator"))
        let installer = try e.prepareInstaller(appPath: path, deviceID: "USB_FAKE", bundleIdentifier: "com.example.wallet", driverID: "android-device")
        XCTAssertEqual(installer.deviceID, "USB_FAKE"); XCTAssertEqual(installer.appPath, path)
        XCTAssertThrowsError(try e.prepareInstaller(appPath: "/missing.app", deviceID: nil, bundleIdentifier: "com.example.wallet", driverID: "android-emulator"))
    }
    func testReplayPreserveDoesNotInstallOrClearExistingApp() throws {
        try assertPreparation(.preserve, withAPK: true, expected: [])
    }
    func testReplayRestartDoesNotClearData() throws {
        try assertPreparation(.restart, withAPK: false, expected: [])
    }
    func testReplayReinstallWithoutAPKClearsData() throws {
        try assertPreparation(.reinstall, withAPK: false, expected: ["clear"])
    }
    func testReplayReinstallWithAPKUninstallsThenInstalls() throws {
        try assertPreparation(.reinstall, withAPK: true, expected: ["uninstall", "install"])
    }
    private func assertPreparation(_ mode: ReplayPreparationMode, withAPK: Bool, expected: [String]) throws {
        let fake = SessionADB(); defer { fake.cleanup() }
        let e = engine(fake), session = try open(e, ["platformName": "Android", "appPackage": "com.example.wallet"])
        defer { try? e.deleteSession(session.id) }
        fake.commands.removeAll()
        try e.prepareAndroidReplay(session: session, mode: mode, appPath: withAPK ? try fake.apk() : nil)
        let mutations = fake.commands.compactMap { command -> String? in
            if command.arguments.contains("uninstall") { return "uninstall" }
            if command.arguments.contains("install") { return "install" }
            if command.arguments.last?.contains("'pm' 'clear'") == true { return "clear" }
            return nil
        }
        XCTAssertEqual(mutations, expected)
    }
    func testFailedClearCannotSilentlyContinueReplay() throws {
        let fake = SessionADB(); fake.failClear = true; defer { fake.cleanup() }
        let e = engine(fake), session = try open(e, ["platformName": "Android", "appPackage": "com.example.wallet"])
        defer { try? e.deleteSession(session.id) }
        XCTAssertThrowsError(try e.prepareAndroidReplay(session: session, mode: .reinstall, appPath: nil))
    }
    func testArtifactRestoreKeepsAndroidActivityAndPlatform() throws {
        let fake = SessionADB(); defer { fake.cleanup() }
        let e = engine(fake), session = try open(e, ["platformName": "Android", "appPackage": "com.example.wallet", "appActivity": ".PayActivity"])
        _ = try e.perform(.launch(bundleIdentifier: "com.example.wallet"), sessionID: session.id)
        let artifact = try JSONEncoder().encode(e.sessionArtifactBundle(sessionID: session.id))
        try e.deleteSession(session.id)
        let restored = try e.restoreSessionArtifact(artifact)
        XCTAssertEqual(restored.appActivity, ".PayActivity"); XCTAssertEqual(restored.device.platform, .android)
        try e.deleteSession(restored.id)
    }
}

private final class SessionADB: @unchecked Sendable {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    var booted = true, failBoot = false, installed = true, failClear = false, keyboardOpen = true
    var commands: [AndroidController.Command] = []
    func cleanup() { try? FileManager.default.removeItem(at: root) }
    func apk() throws -> String {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("wallet.apk"); try Data().write(to: file); return file.path
    }
    func execute(_ command: AndroidController.Command) throws -> AndroidController.Output {
        commands.append(command)
        let args = command.arguments, last = args.last ?? ""
        var out = ""
        if args == ["devices", "-l"] { out = "List of devices attached\nUSB_FAKE device model:Demo\n" + (booted ? "emulator-5554 device model:Pixel\n" : "") }
        else if args == ["-list-avds"] { out = "Pixel\n" }
        else if args == ["-avd", "Pixel"] { if failBoot { throw ScoutError.commandFailed("boot failed") }; booted = true }
        else if args.suffix(3) == ["emu", "avd", "name"] { out = "Pixel\nOK\n" }
        else if last.contains("ro.kernel.qemu") { out = "0" }
        else if last.contains("ro.build.version.release") { out = "15" }
        else if last.contains("sys.boot_completed") { out = "1" }
        else if last.contains("'pm' 'list' 'packages'") { out = installed ? "package:com.example.wallet\n" : "" }
        else if last.contains("'pm' 'clear'") { out = failClear ? "Failed" : "Success" }
        else if last.contains("'dumpsys' 'input_method'") { out = keyboardOpen ? "  mInputShown=true\n" : "  mInputShown=false\n" }
        else if last.contains("'input' 'keyevent' 'KEYCODE_BACK'") { keyboardOpen = false }
        else if args.contains("uninstall") { installed = false }
        else if args.contains("install") { installed = true }
        return .init(stdout: Data(out.utf8))
    }
}
private final class SessionLauncher: RunnerLaunching, @unchecked Sendable {
    var contexts: [RunnerLaunchContext] = [], stopped: [String] = []
    func launch(_ context: RunnerLaunchContext) throws -> Process { contexts.append(context); return Process() }
    func stop(session: Session, process: Process?) { stopped.append(session.id) }
}
