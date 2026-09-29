import XCTest
@testable import CuyScoutCore

final class LayaServiceTests: XCTestCase {
    func testReadsAndNormalizesTheConfiguredURL() {
        XCTAssertEqual(LayaService.configuredURL(environment: ["CUYSCOUT_LAYA_URL": "http://127.0.0.1:8791/"])?.absoluteString, "http://127.0.0.1:8791")
        XCTAssertNil(LayaService.configuredURL(environment: [:]))
        XCTAssertNil(LayaService.configuredURL(environment: ["CUYSCOUT_LAYA_URL": "  "]))
    }

    func testValidatesOnlyHTTPURLsWithHost() {
        XCTAssertTrue(LayaService.isValid("http://127.0.0.1:8791"))
        XCTAssertTrue(LayaService.isValid("https://laya.internal"))
        XCTAssertFalse(LayaService.isValid("127.0.0.1:8791"))
        XCTAssertFalse(LayaService.isValid("ftp://host"))
    }

    func testUnconfiguredLayaIsOptionalAndDoesNotBlockReadiness() {
        let check = LayaService.check(url: nil)
        XCTAssertFalse(check.available)
        XCTAssertTrue(check.detail.contains("opcional"))
    }

    func testUnreachableLayaReportsHowToStartIt() {
        let check = LayaService.check(url: URL(string: "http://127.0.0.1:9"), timeout: 0.5)
        XCTAssertFalse(check.available)
        XCTAssertTrue(check.detail.contains("laya-service.sh start"))
    }
}
