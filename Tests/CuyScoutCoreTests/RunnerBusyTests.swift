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

    func testAgentsExplainsRunnerBusy() {
        let options = ProjectScaffolder.Options(appName: "Demo", appPath: "/tmp/Demo.app", cuyscoutRepoPath: "")
        XCTAssertTrue(ProjectScaffolder.agentsMarkdownBlock(for: options).contains("`runner_busy`"))
    }
}
