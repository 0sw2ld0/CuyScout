import XCTest
@testable import CuyScoutCore

final class RunnerBusyTests: XCTestCase {
    override func tearDown() { BridgeState.timeout = 30; super.tearDown() }

    func testATimedOutCommandIsCancelledInsteadOfRunningLate() throws {
        BridgeState.timeout = 0.3
        let bridge = BridgeState(sessionID: "s")
        _ = bridge.poll() // el runner se conecta
        XCTAssertThrowsError(try bridge.execute(BridgeCommand(action: .tapElement(.init(strategy: .accessibilityIdentifier, value: "btn"))))) { error in
            XCTAssertTrue(error.localizedDescription.contains("runner_busy"))
        }
        XCTAssertNil(bridge.poll(), "el toque vencido no queda en cola para ejecutarse tarde")
    }

    func testALateResultOfAnAbandonedCommandIsIgnoredAndBusyIsReported() throws {
        BridgeState.timeout = 0.3
        let bridge = BridgeState(sessionID: "s")
        _ = bridge.poll()
        let command = BridgeCommand(action: .accessibilityTree)
        let runner = DispatchQueue(label: "runner")
        runner.async {
            // El runner toma el comando pero tarda más que el timeout.
            while bridge.poll() == nil { Thread.sleep(forTimeInterval: 0.01) }
        }
        XCTAssertThrowsError(try bridge.execute(command))
        XCTAssertTrue(bridge.isBusy(longerThan: 0.1))
        bridge.complete(BridgeResult(commandID: command.id, success: true))
        XCTAssertFalse(bridge.isBusy(longerThan: 0), "al responder deja de estar ocupado")
    }

    func testARunnerWhoseProcessEndedIsReportedAsStoppedNotAsBusyForever() throws {
        final class EndedRunner: RunnerLaunching, @unchecked Sendable {
            func launch(_ context: RunnerLaunchContext) throws -> Process {
                let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/true")
                try process.run(); process.waitUntilExit(); return process
            }
            func stop(session: Session, process: Process?) {}
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let engine = ScoutEngine(artifactStore: ArtifactStore(directory: root), runnerLaunchers: [.ios: EndedRunner()])
        let session = try engine.createSession(deviceID: nil, bundleIdentifier: "com.example.wallet")
        try engine.registerBridge(sessionID: session.id)
        try engine.launchRunner(sessionID: session.id)
        let before = try engine.sessionReadiness(sessionID: session.id)
        XCTAssertFalse(before.blockers.contains("runner_stopped"), "sin haberse conectado nunca, solo está arrancando")
        _ = try engine.pollBridge(sessionID: session.id) // el runner llegó a conectarse
        let after = try engine.sessionReadiness(sessionID: session.id)
        XCTAssertTrue(after.blockers.contains("runner_stopped"), "\(after.blockers)")
        XCTAssertFalse(after.blockers.contains("runner_busy"))
    }

    func testTheCloseScriptIgnoresReadsThatFailedAfterTheLastRealStep() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try ProjectUpdater.write(options: .init(appName: "Demo", appPath: "/apps/Demo.app", cuyscoutRepoPath: "", platform: .ios), vscode: false, to: root, simulatorApp: "/apps/Demo.app")
        let script = try String(contentsOf: root.appendingPathComponent("scripts/close-session.sh"), encoding: .utf8)
        let start = try XCTUnwrap(script.range(of: "READS = {"))
        let end = try XCTUnwrap(script.range(of: "print(steps[bad].get(\"id\", \"último paso\"))", range: start.upperBound..<script.endIndex))
        let code = "import json, sys\n" + script[start.lowerBound..<end.upperBound]
        func run(_ steps: String) throws -> String {
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            process.arguments = ["-c", code]
            let input = Pipe(), output = Pipe(); process.standardInput = input; process.standardOutput = output
            try process.run(); input.fileHandleForWriting.write(Data("{\"steps\": \(steps)}".utf8)); try input.fileHandleForWriting.close()
            let data = output.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
            return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let tap = #"{"id":"step-1","success":true,"action":{"type":"tapElement"}}"#
        let failedRead = #"{"id":"step-2","success":false,"action":{"type":"accessibilityTreeWithOptions"}}"#
        let failedTap = #"{"id":"step-3","success":false,"action":{"type":"tapElement"}}"#
        XCTAssertEqual(try run("[\(tap), \(failedRead), \(failedRead)]"), "", "las lecturas fallidas del final no impiden exportar")
        XCTAssertEqual(try run("[\(tap), \(failedTap), \(failedRead)]"), "step-3", "un paso que actúa y falló sí")
        XCTAssertEqual(try run("[\(failedRead)]"), "sin pasos", "solo lecturas: no hay nada que exportar")
        let passedCheck = #"{"id":"step-4","success":true,"action":{"type":"assertText"}}"#
        let failedCheck = #"{"id":"step-5","success":false,"action":{"type":"assertVisible"}}"#
        XCTAssertEqual(try run("[\(tap), \(passedCheck), \(failedCheck), \(failedCheck)]"), "", "verificaciones extra que fallan tras una que comprobó el final no impiden exportar")
        XCTAssertEqual(try run("[\(tap), \(failedCheck)]"), "step-5", "si ninguna verificación comprobó el final, la que falló es el escenario fallando")
    }

    func testAgentsExplainsRunnerBusy() {
        let options = ProjectScaffolder.Options(appName: "Demo", appPath: "/tmp/Demo.app", cuyscoutRepoPath: "")
        XCTAssertTrue(ProjectScaffolder.agentsMarkdownBlock(for: options).contains("`runner_busy`"))
    }
}
