import XCTest
@testable import CuyScoutCore

final class ExporterRegressionTests: XCTestCase {
    func testValidatorAcceptsStandaloneExportWithObservationsWithoutClaimingReplay() {
        let source = recording()
        let plan = TestPlan(sessionID: source.sessionID, steps: source.steps.map {
            TestPlanStep(id: "step-\($0.index)", action: $0.action, success: $0.success, durationMilliseconds: $0.durationMilliseconds)
        }, warnings: [])
        let result = TestPlanValidator.validate(plan, exports: [source.generatedXCTest, source.generatedAppium,
            source.generatedAppiumTypeScript, source.generatedAppiumPython, source.generatedAppiumJava,
            source.generatedGherkin, source.portableJSON])
        XCTAssertTrue(result.valid, result.errors.joined(separator: "\n"))
        XCTAssertFalse(result.executable, "Observations still require review; structural validation is not a verified replay")
    }
    func testStandaloneExportCompilesWithObservationMetadataAndRejectsMissingParameters() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/luna-replay")
        let tsc = root.appendingPathComponent("node_modules/.bin/tsc")
        let tsx = root.appendingPathComponent("node_modules/.bin/tsx")
        guard FileManager.default.isExecutableFile(atPath: tsc.path), FileManager.default.isExecutableFile(atPath: tsx.path) else {
            throw XCTSkip("Install webdriverio/typescript/tsx in .build/luna-replay for executable exporter conformance")
        }
        let directory = root.appendingPathComponent("export-regression-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = recording()
        let redacted = RecordedSession(sessionID: source.sessionID, startedAt: source.startedAt, stoppedAt: nil,
            steps: source.steps.map { RecordedStep(index: $0.index, action: $0.action.redactedSensitiveData(),
                startedAt: $0.startedAt, durationMilliseconds: $0.durationMilliseconds, success: $0.success) })
        let file = directory.appendingPathComponent("export.mts")
        try redacted.generatedAppiumTypeScript.write(to: file, atomically: true, encoding: .utf8)
        func run(_ executable: URL, _ args: [String]) throws -> (Int32, String) {
            let process = Process(); process.executableURL = executable; process.arguments = args
            process.environment = ProcessInfo.processInfo.environment.merging([
                "CUYSCOUT_REPLAY_AUTHORIZED":"yes", "IOS_UDID":"invalid-fixture", "IOS_BUNDLE_ID":"example.fixture",
                "APPIUM_HOST":"127.0.0.1", "APPIUM_PORT":"1", "CUYSCOUT_REPLAY_VALUES":"{}"
            ]) { _, new in new }
            let pipe = Pipe(); process.standardOutput = pipe; process.standardError = pipe
            try process.run(); let output = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
            return (process.terminationStatus, String(decoding: output, as: UTF8.self))
        }
        let compiled = try run(tsc, ["--noEmit", "--target", "es2022", "--module", "nodenext", "--moduleResolution", "nodenext", "--skipLibCheck", file.path])
        XCTAssertEqual(compiled.0, 0, compiled.1)
        let missing = try run(tsx, [file.path])
        XCTAssertNotEqual(missing.0, 0)
        XCTAssertTrue(missing.1.contains("Set CUYSCOUT_REPLAY_VALUES"), missing.1)
        XCTAssertFalse(missing.1.contains("ECONNREFUSED"), "Must fail before connecting to the driver")
    }
    func testTypeScriptExportWaitsForLiveControlsAndExplainsReplayLimits() {
        let source = recording().generatedAppiumTypeScript
        XCTAssertTrue(source.contains("{ timeout, interval: 500, timeoutMsg: `Element not found: ${locator}` }"))
        // WDIO 9 strict $() rejects a button plus its own label; like CuyScout, take the displayed one.
        XCTAssertTrue(source.contains("matches = Array.from(await driver.$$(locator));"))
        XCTAssertTrue(source.contains("candidate.isDisplayed()"))
        XCTAssertTrue(source.contains("not a verified replay"))
        XCTAssertTrue(source.contains("Never blindly retry irreversible actions"))
        XCTAssertFalse(source.contains("import { expect }"))
        XCTAssertFalse(source.contains("describe("))
        XCTAssertTrue(source.contains("connectionRetryCount: 0"))
        XCTAssertTrue(source.contains("finally { await driver.deleteSession(); }"))
        XCTAssertTrue(source.contains("preflight(actions);"))
        XCTAssertTrue(source.contains("element.addValue"), "Match native typeText append semantics")
        XCTAssertTrue(source.contains("getAttribute('label')"))
        XCTAssertTrue(source.contains("[key: string]: unknown"), "Recorded observations include options and other metadata")
    }
    func testFailedAttemptsAreSkippedNotReplayed() {
        let recording = RecordedSession(sessionID: "failed", startedAt: Date(), stoppedAt: nil,
            steps: [RecordedStep(index: 0, action: .tapElement(.init(strategy: .accessibilityIdentifier, value: "pay")),
                startedAt: Date(), durationMilliseconds: 1, success: false)])
        XCTAssertTrue(recording.generatedAppiumTypeScript.contains("const failedAttempts = new Set<number>([0]);"))
    }
    func testRedactedValuesStayOutOfGeneratedSourceAndAssertionsArePreserved() {
        let field = ScoutSelector(strategy: .accessibilityIdentifier, value: "summary")
        let session = RecordedSession(sessionID: "redacted", startedAt: Date(), stoppedAt: nil,
            steps: [RecordedStep(index: 0, action: ScoutAction.assertText(field, expected: "private").redactedSensitiveData(),
                startedAt: Date(), durationMilliseconds: 1, success: true)])
        XCTAssertFalse(session.generatedAppiumTypeScript.contains("private"))
        XCTAssertTrue(session.generatedAppiumTypeScript.contains("<redacted>"))
        XCTAssertTrue(session.generatedAppiumTypeScript.contains("CUYSCOUT_REPLAY_VALUES"))
    }
    private func recording() -> RecordedSession {
        let field = ScoutSelector(strategy: .accessibilityIdentifier, value: "input_email")
        let actions: [ScoutAction] = [.accessibilityTreeWithOptions(AccessibilityOptions()), .typeElement(field, text: "first"),
            .sequence([.typeElement(field, text: "second"),
                       .sequence([.waitFor(field, timeout: 5), .assertVisible(field)])]),
            .assertText(field, expected: "second")]
        return RecordedSession(sessionID: "fixture", startedAt: Date(), stoppedAt: nil,
            steps: actions.enumerated().map {
                RecordedStep(index: $0.offset, action: $0.element, startedAt: Date(),
                             durationMilliseconds: 1, success: true)
            })
    }

    func testGeneratedXCTestParsesWithNestedSequencesAndAssertions() throws {
        let source = recording().generatedXCTest
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("cuyscout-export-\(UUID().uuidString).swift")
        try source.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["swiftc", "-frontend", "-parse", file.path]
        let diagnostics = Pipe()
        process.standardError = diagnostics
        try process.run()
        let output = diagnostics.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, String(decoding: output, as: UTF8.self))
        XCTAssertEqual(source.components(separatedBy: "func testRecordedFlow").count - 1, 1)
        XCTAssertEqual(source.components(separatedBy: "private func element").count - 1, 1)
        XCTAssertEqual(source.components(separatedBy: "do { let field").count - 1, 2)
        XCTAssertFalse(source.contains("XCTSkip"), "Missing elements must fail assertions, not skip the test")
        XCTAssertFalse(source.contains("allElementsBoundByIndex"), "Waits must use a live query")
    }

    func testJavaScriptLocatorAndHooksShareDriverScope() throws {
        let source = recording().generatedAppium
        let declaration = try XCTUnwrap(source.range(of: "let driver;"))
        let finder = try XCTUnwrap(source.range(of: "async function find"))
        let suite = try XCTUnwrap(source.range(of: "describe("))
        XCTAssertLessThan(declaration.lowerBound, finder.lowerBound)
        XCTAssertLessThan(finder.lowerBound, suite.lowerBound)
        XCTAssertEqual(source.components(separatedBy: "let driver;").count - 1, 1)
    }
}

final class TypeScriptGesturesTests: XCTestCase {
    func testScreenshotsAreSkippedAndCoordinateGesturesReplay() {
        let now = Date()
        let recording = RecordedSession(sessionID: "g", startedAt: now, stoppedAt: now, steps: [
            RecordedStep(index: 0, action: .screenshot, startedAt: now, durationMilliseconds: 1, success: true),
            RecordedStep(index: 1, action: .tap(x: 201, y: 800), startedAt: now, durationMilliseconds: 1, success: true),
            RecordedStep(index: 2, action: .swipe(fromX: 200, fromY: 700, toX: 200, toY: 300, duration: 0.3), startedAt: now, durationMilliseconds: 1, success: true)])
        let source = recording.generatedAppiumTypeScript
        XCTAssertTrue(source.contains("'screenshot', 'elementScreenshot'"), "una captura es observación: se salta")
        XCTAssertTrue(source.contains("const gestures = new Set(['tap', 'swipe', 'type']);"))
        XCTAssertTrue(source.contains("await waitForSettledScreen();"), "como CuyScout, espera a que la pantalla quede quieta")
        XCTAssertTrue(source.contains("pointerType: 'touch'"))
    }
}
