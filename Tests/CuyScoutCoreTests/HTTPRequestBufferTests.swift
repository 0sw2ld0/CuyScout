import XCTest
@testable import CuyScoutCore

final class HTTPRequestBufferTests: XCTestCase {
    func testSplitHeadersAndUTF8BodyAreNotDispatchedEarly() throws {
        let body = Data(#"{"expected":"N° Operación: éxito"}"#.utf8)
        let head = Data("POST /actions HTTP/1.1\r\nContent-Length: \(body.count)\r\n\r\n".utf8)
        let wire = head + body
        var buffer = HTTPRequestBuffer()
        for (index, byte) in wire.enumerated() {
            XCTAssertEqual(try buffer.append(Data([byte])), index == wire.count - 1)
        }
        XCTAssertEqual(buffer.data, wire)
    }
    func testRejectsAmbiguousOrUnsupportedFraming() {
        for headers in ["Content-Length: -1", "Content-Length: 2\r\nContent-Length: 3", "Transfer-Encoding: chunked", "Content-Length: 99999999"] {
            var buffer = HTTPRequestBuffer()
            XCTAssertThrowsError(try buffer.append(Data("POST / HTTP/1.1\r\n\(headers)\r\n\r\n".utf8)))
        }
    }
}
