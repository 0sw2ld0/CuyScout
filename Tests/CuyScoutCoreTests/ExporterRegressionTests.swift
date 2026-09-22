import XCTest
@testable import CuyScoutCore

final class ExporterRegressionTests: XCTestCase {
    func testTypeScriptExportWaitsForLiveControlsAndExplainsReplayLimits() {
        let source = recording().generatedAppiumTypeScript
        XCTAssertTrue(source.contains("waitForExist({ timeout: 10000 })"))
        XCTAssertTrue(source.contains("not a verified replay"))
        XCTAssertTrue(source.contains("Never blindly retry irreversible actions"))
    }
    private func recording() -> RecordedSession {
        let field = ScoutSelector(strategy: .accessibilityIdentifier, value: "input_email")
        let actions: [ScoutAction] = [.typeElement(field, text: "first"),
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
