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
        let aliases = ["appPackage", "appActivity", "avd", "driverId", "automationName", "udid", "deviceName", "platformVersion", "bundleId", "noReset", "fullReset", "app", "browserName", "xcodeOrgId", "xcodeSigningId", "wdaLocalPort", "usePrebuiltWDA", "updatedWDABundleId", "showXcodeLog", "webDriverAgentPort"]
        for alias in aliases where values["appium:\(alias)"] == nil {
            if let value = values[alias] { values["appium:\(alias)"] = value }
        }
        if let standard = values["platformName"] as? String, let alias = values["appium:platformName"] as? String, standard.lowercased() != alias.lowercased() {
            throw ScoutError.invalidRequest("platformName conflicts with appium:platformName")
        }
        if values["platformName"] == nil { values["platformName"] = values["appium:platformName"] ?? "iOS" }
        guard let platform = values["platformName"] as? String else { throw ScoutError.invalidRequest("platformName must be a string") }
        guard ["ios", "any", "android"].contains(platform.lowercased()) else { throw ScoutError.invalidRequest("Unsupported platformName: \(platform)") }
        let android = platform.lowercased() == "android"
        if let automation = values["appium:automationName"] as? String, automation.lowercased() != (android ? "uiautomator2" : "xcuitest") { throw ScoutError.invalidRequest("Unsupported appium:automationName: \(automation)") }
        if values["appium:automationName"] != nil && values["appium:automationName"] as? String == nil { throw ScoutError.invalidRequest("appium:automationName must be a string") }
        if let noReset = values["appium:noReset"] as? Bool, noReset, let fullReset = values["appium:fullReset"] as? Bool, fullReset { throw ScoutError.invalidRequest("appium:noReset and appium:fullReset are mutually exclusive") }
        if android {
            var warnings: [String] = []
            for name in ["xcodeOrgId", "xcodeSigningId", "wdaLocalPort", "usePrebuiltWDA", "updatedWDABundleId", "showXcodeLog", "webDriverAgentPort"] {
                if values.removeValue(forKey: "appium:\(name)") != nil { warnings.append("Ignored appium:\(name) on Android") }
                values.removeValue(forKey: name)
            }
            if !warnings.isEmpty { values["cuyscout:capabilityWarnings"] = warnings }
            for name in ["appPackage", "appActivity", "avd", "udid"] {
                if let value = values["appium:\(name)"], (value as? String)?.isEmpty != false { throw ScoutError.invalidRequest("appium:\(name) must be a nonempty string") }
            }
        }
        return values
    }

    private static func jsonEqual(_ lhs: Any?, _ rhs: Any?) -> Bool {
        guard let lhs, let rhs, JSONSerialization.isValidJSONObject(["value": lhs]), JSONSerialization.isValidJSONObject(["value": rhs]) else { return String(describing: lhs) == String(describing: rhs) }
        return (try? JSONSerialization.data(withJSONObject: ["value": lhs])) == (try? JSONSerialization.data(withJSONObject: ["value": rhs]))
    }
}
