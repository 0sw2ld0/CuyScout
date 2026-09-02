import XCTest

final class ScoutBridgeUITests: XCTestCase {
    override func setUpWithError() throws {
        // Un comando del agente que falla (un control que no acepta foco, un selector que ya
        // no existe) no debe terminar el test: eso mataría el runner y con él la sesión.
        // El gateway ya reporta cada fallo por su cuenta.
        continueAfterFailure = true
    }

    /// Ejecuta el puente CuyScout: lanza la app bajo prueba (por bundle ID) y atiende
    /// comandos del gateway hasta el DELETE de la sesión o el vencimiento de maxSeconds.
    func testRunCuyScoutBridge() throws {
        try ScoutBridgeRunner().run()
    }
}