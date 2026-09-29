import XCTest
@testable import CuyScoutCore

final class ReplayInterruptionTests: XCTestCase {
    func testDeclinesOnlyRecognizedPasswordSavingPrompt() {
        XCTAssertEqual(ReplayInterruption.declinePasswordSaving(.init(text: "¿Guardar contraseña?", buttons: ["Guardar", "Ahora no"])), "Ahora no")
        XCTAssertEqual(ReplayInterruption.declinePasswordSaving(.init(text: "Save this password?", buttons: ["Save", "Not Now"])), "Not Now")
        XCTAssertNil(ReplayInterruption.declinePasswordSaving(.init(text: "Guardar contraseña", buttons: ["Guardar"])))
        XCTAssertNil(ReplayInterruption.declinePasswordSaving(.init(text: "Permitir acceso a fotos", buttons: ["Permitir", "Ahora no"])))
        XCTAssertFalse(ReplayInterruption.mayRetry(.tapElement(.init(strategy: .label, value: "Transferir"))))
    }
}
