import XCTest
@testable import CuyScoutCore

final class RunnerTimeoutMessageTests: XCTestCase {
    func testExplainsARunnerThatNeverPollsAfterLaunch() throws {
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("runner-idle-\(UUID()).log")
        try "    t =     0.66s         Wait for com.demo.app to idle\n** BUILD INTERRUPTED **\n".write(to: log, atomically: true, encoding: .utf8)
        let message = ScoutEngine.runnerTimeoutMessage(logPath: log.path)
        XCTAssertTrue(message.contains("nunca pidió comandos"))
        XCTAssertTrue(message.contains("autenticarse"))
        XCTAssertTrue(message.contains(log.path))
    }

    func testKeepsTheGenericMessageOtherwise() {
        XCTAssertEqual(ScoutEngine.runnerTimeoutMessage(logPath: "/nonexistent.log"), "Timed out waiting for XCTest runner; see /nonexistent.log")
    }
}

final class ProcessOutputTests: XCTestCase {
    /// Más de 64 KB por stdout y por stderr: sin leer mientras corre, esto se bloqueaba.
    func testLargeOutputDoesNotDeadlock() throws {
        let (status, stdout, stderr) = try SimulatorController.execute("/bin/sh", ["-c", "head -c 300000 /dev/zero; head -c 200000 /dev/zero >&2"])
        XCTAssertEqual(status, 0)
        XCTAssertEqual(stdout.count, 300000)
        XCTAssertEqual(stderr.count, 200000)
    }
}
