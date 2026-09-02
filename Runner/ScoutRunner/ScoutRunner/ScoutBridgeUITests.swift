import XCTest

final class ScoutBridgeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Ejecuta el puente CuyScout: lanza la app bajo prueba (por bundle ID) y atiende
    /// comandos del gateway hasta el DELETE de la sesión o el vencimiento de maxSeconds.
    func testRunCuyScoutBridge() throws {
        try ScoutBridgeRunner().run()
    }
}