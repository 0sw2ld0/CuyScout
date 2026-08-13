import Foundation

public enum CapabilityNegotiator {
    public static func negotiate(_ input: [String: Any]) throws -> [String: Any] {
        guard !input.isEmpty else { throw ScoutError.invalidRequest("W3C capabilities are required") }
        guard let outer = input["capabilities"] as? [String: Any] else { return try normalize((input["desiredCapabilities"] as? [String: Any]) ?? input) }
        let always = outer["alwaysMatch"] as? [String: Any] ?? [:]
        let first: [[String: Any]]
        if let raw = outer["firstMatch"] { guard let values = raw as? [[String: Any]] else { throw ScoutError.invalidRequest("capabilities.firstMatch must be an array") }; first = values.isEmpty ? [[:]] : values } else { first = [[:]] }
        for candidate in first {
            if candidate.keys.contains(where: { key in always[key] != nil && !jsonEqual(always[key], candidate[key]) }) { continue }
            var merged = always
            candidate.forEach { merged[$0.key] = $0.value }
            return try normalize(merged)
        }
        throw ScoutError.invalidRequest("No W3C firstMatch capability set is compatible with alwaysMatch")
    }

    private static func normalize(_ input: [String: Any]) throws -> [String: Any] {
        var values = input
        let aliases = ["automationName", "udid", "deviceName", "platformVersion", "bundleId", "noReset", "fullReset", "app", "browserName", "xcodeOrgId", "xcodeSigningId", "wdaLocalPort", "usePrebuiltWDA", "updatedWDABundleId", "showXcodeLog", "webDriverAgentPort"]
        for alias in aliases where values["appium:\(alias)"] == nil {
            if let value = values[alias] { values["appium:\(alias)"] = value }
        }
        if values["platformName"] == nil { values["platformName"] = "iOS" }
        guard let platform = values["platformName"] as? String else { throw ScoutError.invalidRequest("platformName must be a string") }
        guard ["ios", "any"].contains(platform.lowercased()) else { throw ScoutError.invalidRequest("Unsupported platformName: \(platform)") }
        if let automation = values["appium:automationName"] as? String, automation.lowercased() != "xcuitest" { throw ScoutError.invalidRequest("Unsupported appium:automationName: \(automation)") }
        if values["appium:automationName"] != nil && values["appium:automationName"] as? String == nil { throw ScoutError.invalidRequest("appium:automationName must be a string") }
        if let noReset = values["appium:noReset"] as? Bool, noReset, let fullReset = values["appium:fullReset"] as? Bool, fullReset { throw ScoutError.invalidRequest("appium:noReset and appium:fullReset are mutually exclusive") }
        return values
    }

    private static func jsonEqual(_ lhs: Any?, _ rhs: Any?) -> Bool {
        guard let lhs, let rhs, JSONSerialization.isValidJSONObject(["value": lhs]), JSONSerialization.isValidJSONObject(["value": rhs]) else { return String(describing: lhs) == String(describing: rhs) }
        return (try? JSONSerialization.data(withJSONObject: ["value": lhs])) == (try? JSONSerialization.data(withJSONObject: ["value": rhs]))
    }
}
