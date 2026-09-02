import XCTest

final class ScoutBridgeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Ejecuta el puente CuyScout: levanta la app y atiende comandos del gateway
    /// hasta que el cliente toque /tmp/cuyscout-bridge-stop o venza maxSeconds.
    func testRunCuyScoutBridge() throws {
        try ScoutBridgeRunner().run()
    }
}