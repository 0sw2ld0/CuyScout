import Foundation

/// Produces a compact identity for a screen while ignoring values that commonly
/// change between two observations of the same screen.
public enum StateIdentity {
    public static func stableID(_ source: String) -> String {
        var normalized = source
        let patterns = [
            #"\b\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})?\b"#,
            #"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}\b"#,
            #"\b\d{10,}\b"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            normalized = regex.stringByReplacingMatches(in: normalized, range: NSRange(normalized.startIndex..., in: normalized), withTemplate: "<dynamic>")
        }
        normalized = normalized.split { $0.isWhitespace }.joined(separator: " ")
        let encoded = Data(normalized.utf8).base64EncodedString()
        return "state:\(String(encoded.prefix(48)))"
    }
}
