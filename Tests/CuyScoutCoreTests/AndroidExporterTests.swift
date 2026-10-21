import XCTest
@testable import CuyScoutCore

final class AndroidExporterTests: XCTestCase {
    private func session(_ platform: Device.Platform = .android, activity: String? = ".LoginActivity") -> Session {
        Session(id: "export", device: Device(id: "FAKE_USB", name: "Demo", runtime: "Android 15", state: "Booted", kind: .physical, platform: platform), bundleIdentifier: "com.example.wallet", createdAt: Date(), driverID: platform == .android ? "android-device" : "ios-device", appActivity: platform == .android ? activity : nil)
    }
    private func recording(_ actions: [ScoutAction], session: Session? = nil) -> RecordedSession {
        RecordedSession(sessionID: "export", startedAt: Date(), stoppedAt: nil, steps: actions.enumerated().map {
            RecordedStep(index: $0.offset, action: $0.element, startedAt: Date(), durationMilliseconds: 1, success: true)
        }, session: session)
    }
    private func artifact(_ session: Session, recording: RecordedSession, redact: Bool = false) -> SessionArtifactBundle {
        SessionArtifactBundle(session: session, events: [], metrics: SessionMetrics(totalCommands: 0, successfulCommands: 0, failedCommands: 0, failureRate: 0, averageDurationMilliseconds: 0, p95DurationMilliseconds: 0, commandCounts: [:]), checkpoints: [], testPlan: nil, recording: recording, redactSensitiveData: redact)
    }
    func testAndroidExportEmitsPackageActivityAndNoAppleCapabilities() {
        let code = recording([.tapElement(.init(strategy: .accessibilityIdentifier, value: "login"))], session: session()).generatedAppiumTypeScript
        XCTAssertTrue(code.contains("platformName: 'Android'")); XCTAssertTrue(code.contains("'appium:automationName': 'UiAutomator2'"))
        XCTAssertTrue(code.contains("com.example.wallet")); XCTAssertTrue(code.contains(".LoginActivity"))
        XCTAssertTrue(code.contains("APPIUM_SESSION_TIMEOUT_MS")); XCTAssertTrue(code.contains("CUYSCOUT_REPLAY_PREPARATION"))
        for key in ["XCUITest", "wdaLaunchTimeout", "showXcodeLog", "xcodeOrgId", "prebuiltWDAPath", "-ios predicate string", "IOS_UDID"] { XCTAssertFalse(code.contains(key), key) }
    }
    func testArtifactRegeneratesAndroidCodeEvenWhenStoredRecordingWasIOS() throws {
        let original = recording([.assertVisible(.init(strategy: .label, value: "Pay"))])
        let bundle = artifact(session(), recording: original)
        XCTAssertTrue(bundle.recording!.generatedAppiumTypeScript.contains("platformName: 'Android'"))
        let code = try AppiumExportFormat.typescript.source(fromArtifactData: JSONEncoder().encode(bundle))
        XCTAssertEqual(code, bundle.recording!.generatedAppiumTypeScript)
    }
    func testRedactedAndroidArtifactKeepsPlatformAndHidesValues() throws {
        let input = recording([.typeElement(.init(strategy: .accessibilityIdentifier, value: "password"), text: "private-value")])
        let bundle = artifact(session(), recording: input, redact: true)
        let code = try AppiumExportFormat.typescript.source(fromArtifactData: JSONEncoder().encode(bundle))
        XCTAssertFalse(code.contains("private-value")); XCTAssertTrue(code.contains("<redacted>")); XCTAssertTrue(code.contains("platformName: 'Android'"))
    }
    func testLegacyArtifactStillExportsIOS() throws {
        let file = try XCTUnwrap(Bundle.module.url(forResource: "legacy-ios", withExtension: "cuyscout.json", subdirectory: "Fixtures"))
        let code = try AppiumExportFormat.typescript.source(fromArtifactData: Data(contentsOf: file))
        XCTAssertTrue(code.contains("platformName: 'iOS'")); XCTAssertTrue(code.contains("'appium:automationName': 'XCUITest'"))
        XCTAssertTrue(code.contains("APPIUM_WDA_LAUNCH_TIMEOUT_MS")); XCTAssertFalse(code.contains("ANDROID_UDID"))
    }
    func testMaestroAndroidPackageAndOtherLaunchAppIDs() throws {
        let input = recording([.launch(bundleIdentifier: "com.example.wallet"), .sequence([.launch(bundleIdentifier: "com.example.settings"), .terminate(bundleIdentifier: "com.example.settings")])])
        let yaml = try MaestroFlowExporter.source(fromArtifactData: JSONEncoder().encode(artifact(session(), recording: input)))
        XCTAssertTrue(yaml.contains("appId: \"com.example.wallet\""))
        XCTAssertTrue(yaml.contains("- launchApp\n"))
        XCTAssertTrue(yaml.contains("- launchApp:\n    appId: \"com.example.settings\""))
        XCTAssertTrue(yaml.contains("- stopApp: \"com.example.settings\""))
    }
    func testMaestroAddsDefaultLaunchForAndroidAssertionRecording() throws {
        let yaml = try MaestroFlowExporter.source(fromArtifactData: JSONEncoder().encode(artifact(session(), recording: recording([.assertVisible(.init(strategy: .accessibilityIdentifier, value: "login"))]))))
        XCTAssertTrue(yaml.contains("appId: \"com.example.wallet\"\n")); XCTAssertTrue(yaml.contains("---\n- launchApp\n- assertVisible:"))
    }
    func testGeneratedExportsCompileAndReplayAgainstW3CDouble() throws {
        let runtime = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Tests/ExporterRuntime")
        guard FileManager.default.fileExists(atPath: runtime.appendingPathComponent("node_modules/.bin/tsx").path) else { throw XCTSkip("Run npm ci --prefix Tests/ExporterRuntime to run generated-export conformance") }
        let output = runtime.appendingPathComponent(".generated-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: output) }
        let actions: [ScoutAction] = [
            .tapElement(.init(strategy: .accessibilityIdentifier, value: "login")),
            .typeElement(.init(strategy: .accessibilityIdentifier, value: "email"), text: "demo"),
            .assertText(.init(strategy: .accessibilityIdentifier, value: "email"), expected: "demo"),
            .assertVisible(.init(strategy: .label, value: "Bob's \"Pay\"")),
            .assertVisible(.init(strategy: .value, value: "true")),
            .tap(x: 10, y: 20), .swipe(fromX: 10, fromY: 20, toX: 20, toY: 40, duration: 0.1)]
        for platform in [Device.Platform.android, .ios] {
            let platformActions = platform == .android ? actions + [
                .assertText(.init(strategy: .accessibilityIdentifier, value: "receipt"), expected: "DEMO-0001"),
                .assertText(.init(strategy: .accessibilityIdentifier, value: "literal_null"), expected: "null"),
                .assertText(.init(strategy: .label, value: "Bob's \"Pay\""), expected: "Bob's \"Pay\""),
                .assertVisible(.init(strategy: .label, value: "Test user")),
                .assertText(.init(strategy: .label, value: "Test user"), expected: ""),
                .typeElement(.init(strategy: .label, value: "Test user"), text: "demo"),
                .assertText(.init(strategy: .label, value: "Test user"), expected: "demo"),
                .assertText(.init(strategy: .accessibilityIdentifier, value: "checked"), expected: "true"),
                .assertText(.init(strategy: .value, value: "false"), expected: "false"),
                .assertText(.init(strategy: .accessibilityIdentifier, value: "checked_only"), expected: "true"),
                .tapElement(.init(strategy: .value, value: "true")),
                .eraseText(count: 3)
            ] : actions
            try recording(platformActions, session: session(platform)).generatedAppiumTypeScript.write(to: output.appendingPathComponent(platform.rawValue + ".mts"), atomically: true, encoding: .utf8)
        }
        let bad = recording([.assertVisible(.init(strategy: .predicate, value: "label == 'Pay'"))], session: session()).generatedAppiumTypeScript
        try bad.write(to: output.appendingPathComponent("predicate.mts"), atomically: true, encoding: .utf8)
        try recording([.assertVisible(.init(strategy: .label, value: "Pay"))], session: session(activity: nil)).generatedAppiumTypeScript.write(to: output.appendingPathComponent("missing-activity.mts"), atomically: true, encoding: .utf8)
        let redacted = recording([.typeElement(.init(strategy: .accessibilityIdentifier, value: "email"), text: "<redacted>")], session: session()).generatedAppiumTypeScript
        try redacted.write(to: output.appendingPathComponent("redacted.mts"), atomically: true, encoding: .utf8)
        try recording([.assertText(.init(strategy: .accessibilityIdentifier, value: "literal_null"), expected: "Different text")], session: session()).generatedAppiumTypeScript.write(to: output.appendingPathComponent("wrong-description.mts"), atomically: true, encoding: .utf8)
        try recording([.assertText(.init(strategy: .accessibilityIdentifier, value: "container"), expected: "Child text")], session: session()).generatedAppiumTypeScript.write(to: output.appendingPathComponent("wrong-descendant.mts"), atomically: true, encoding: .utf8)
        try recording([.assertText(.init(strategy: .accessibilityIdentifier, value: "checked"), expected: "false")], session: session()).generatedAppiumTypeScript.write(to: output.appendingPathComponent("wrong-selected.mts"), atomically: true, encoding: .utf8)
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/env"); process.arguments = ["node", runtime.appendingPathComponent("verify.mjs").path, output.path]
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = pipe
        try process.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, String(decoding: data, as: UTF8.self))
    }
}
