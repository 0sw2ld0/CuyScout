import XCTest
@testable import CuyScoutCore

final class RecordingCompletenessTests: XCTestCase {
    /// (types, success, expected offending position).
    private let cases: [([String], [Bool], Int?)] = [
        ([], [], -1),
        (["tapElement"], [true], nil),
        (["tapElement", "tapElement"], [true, false], 1),
        // A read that failed at the end changed nothing.
        (["tapElement", "accessibilityTree"], [true, false], nil),
        // Extra checks that failed after one that verified the end are dropped.
        (["tapElement", "assertText", "assertVisible", "assertText"], [true, true, false, false], nil),
        // Without a passing check after the last action, the failed check may be the scenario failing.
        (["tapElement", "assertText"], [true, false], 1),
        (["tapElement", "assertText", "tapElement", "assertVisible"], [true, true, true, false], 3),
        (["assertText"], [false], -1),
    ]

    func testEndsWithFailedChecksOnlyWhenTheEndWasVerified() {
        for (types, success, expected) in cases {
            XCTAssertEqual(RecordingCompleteness.incompleteStep(types: types, success: success), expected, "\(types) \(success)")
        }
    }

    func testTheScriptsApplyTheSameRule() throws {
        let input = cases.map { types, success, _ in zip(types, success).map { ["action": ["type": $0.0], "success": $0.1] } }
        let program = RecordingCompleteness.python + "\nimport json, sys\nprint(json.dumps([incomplete(s) for s in json.load(sys.stdin)]))\n"
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/env"); process.arguments = ["python3", "-c", program]
        let stdin = Pipe(), stdout = Pipe(); process.standardInput = stdin; process.standardOutput = stdout
        try process.run()
        stdin.fileHandleForWriting.write(try JSONSerialization.data(withJSONObject: input)); try stdin.fileHandleForWriting.close()
        process.waitUntilExit()
        let output = try JSONSerialization.jsonObject(with: stdout.fileHandleForReading.readDataToEndOfFile()) as? [Any] ?? []
        XCTAssertEqual(output.map { $0 as? Int }, cases.map(\.2))
    }

    func testTheCloseAndReplayScriptsUseTheSharedRule() throws {
        let scripts = ProjectScaffolder.files(for: ProjectScaffolder.Options(appName: "Demo", appPath: "", cuyscoutRepoPath: ""))
        for name in ["scripts/close-session.sh", "scripts/replay-cuyscout.sh"] {
            XCTAssertTrue(scripts[name]?.contains("def incomplete(steps):") == true, name)
        }
    }

    func testAScrollIsExportedAndKeepsThePlanExecutable() {
        let phone = Device(id: "phone", name: "Phone", runtime: "Android 14", state: "Booted", isAvailable: true, kind: .physical, platform: .android)
        let steps = [RecordedStep(index: 0, action: .scroll(x: 0, y: 400), startedAt: Date(), durationMilliseconds: 1, success: true),
                     RecordedStep(index: 1, action: .tapElement(ScoutSelector(strategy: .label, value: "Configurar")), startedAt: Date(), durationMilliseconds: 1, success: true)]
        let script = TypeScriptReplayExporter.make(steps: steps, session: Session(id: "s", device: phone, bundleIdentifier: "com.example.app", createdAt: Date(), driverID: "android-device"))
        XCTAssertTrue(script.contains("const gestures = new Set(['tap', 'swipe', 'scroll', 'type']);"))
        XCTAssertTrue(script.contains("action.type === 'scroll'") && script.contains("driver.getWindowSize()"))
        let plan = TestPlan(sessionID: "s", steps: steps.map { TestPlanStep(id: "step-\($0.index)", action: $0.action, success: $0.success, durationMilliseconds: 1) }, warnings: [])
        XCTAssertTrue(TestPlanValidator.validate(plan).executable, "un desplazamiento se reproduce en Appium")
    }

    func testAndroidLabelsMatchAsAPersonReadsThem() {
        let phone = Device(id: "phone", name: "Phone", runtime: "Android 14", state: "Booted", isAvailable: true, kind: .physical, platform: .android)
        let step = RecordedStep(index: 0, action: .assertVisible(ScoutSelector(strategy: .label, value: "15.00")), startedAt: Date(), durationMilliseconds: 1, success: true)
        let script = TypeScriptReplayExporter.make(steps: [step], session: Session(id: "s", device: phone, bundleIdentifier: "com.example.app", createdAt: Date(), driverID: "android-device"))
        XCTAssertTrue(script.contains("normalize-space(translate(${attribute}, '\\u00a0\\u202f', '  '))"), "un texto con espacios de relleno o sin separación se encuentra igual")
    }
}
