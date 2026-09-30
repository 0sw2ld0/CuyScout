import XCTest
@testable import CuyScoutCore

final class PortInspectorTests: XCTestCase {
    func testParsesLsofAndRecognisesAStrayGateway() throws {
        let gateway = try XCTUnwrap(PortInspector.parse("p4242\ncnode\n".replacingOccurrences(of: "node", with: "cuyscout")))
        XCTAssertEqual(gateway.pid, 4242)
        XCTAssertTrue(gateway.isCuyScoutGateway)
        XCTAssertFalse(try XCTUnwrap(PortInspector.parse("p10\ncnode\n")).isCuyScoutGateway, "Appium corre como node")
        XCTAssertFalse(try XCTUnwrap(PortInspector.parse("p11\nccuyscout-app\n")).isCuyScoutGateway, "la app no es el gateway")
        XCTAssertNil(PortInspector.parse(""))
    }

    func testPicksTheNextFreePort() {
        XCTAssertEqual(PortInspector.firstFreePort(in: 4724...4730, isFree: { $0 >= 4726 }), 4726)
        XCTAssertNil(PortInspector.firstFreePort(in: 4724...4725, isFree: { _ in false }))
    }
}
