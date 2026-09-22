import Foundation

/// TCP reads are fragments, not HTTP messages. Frame by byte Content-Length before decoding UTF-8.
public struct HTTPRequestBuffer {
    public private(set) var data = Data()
    public private(set) var messageLength: Int?
    public init() {}
    public mutating func append(_ bytes: Data) throws -> Bool {
        data.append(bytes)
        guard data.count <= 8_388_608 else { throw ScoutError.invalidRequest("HTTP request too large") }
        if messageLength == nil, let separator = data.range(of: Data("\r\n\r\n".utf8)) {
            guard separator.lowerBound <= 65_536,
                  let head = String(data: data[..<separator.lowerBound], encoding: .utf8) else {
                throw ScoutError.invalidRequest("Invalid HTTP headers")
            }
            var length: Int?
            for line in head.components(separatedBy: "\r\n").dropFirst() {
                let pair = line.split(separator: ":", maxSplits: 1).map(String.init)
                guard pair.count == 2 else { throw ScoutError.invalidRequest("Invalid HTTP header") }
                let name = pair[0].lowercased()
                if name == "transfer-encoding" { throw ScoutError.invalidRequest("Use Content-Length; chunked requests are not supported") }
                if name == "content-length" {
                    let value = pair[1].trimmingCharacters(in: .whitespaces)
                    guard length == nil, !value.isEmpty, value.allSatisfy({ $0.isASCII && $0.isNumber }),
                          let count = Int(value), count <= 8_388_608 - separator.upperBound else {
                        throw ScoutError.invalidRequest("Invalid or duplicate Content-Length")
                    }
                    length = count
                }
            }
            messageLength = separator.upperBound + (length ?? 0)
        }
        if messageLength == nil && data.count > 65_536 { throw ScoutError.invalidRequest("HTTP headers too large") }
        return messageLength.map { data.count >= $0 } ?? false
    }
}
