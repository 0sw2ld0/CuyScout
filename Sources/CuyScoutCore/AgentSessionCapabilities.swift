import Foundation

/// The MCP tool and HTTP gateway share one capability vocabulary and validation path.
public enum AgentSessionCapabilities {
    public static func make(_ arguments: [String: Any]) throws -> [String: Any] {
        let driver = arguments["driverId"] as? String
        var capabilities: [String: Any] = ["platformName": arguments["platformName"] ?? (driver?.hasPrefix("android-") == true ? "Android" : "iOS")]
        let mapping = ["appPath": "appium:app", "deviceId": "appium:udid", "bundleIdentifier": "appium:bundleId", "driverId": "appium:driverId", "waitSeconds": "appium:sessionWaitTimeout", "noReset": "appium:noReset", "fullReset": "appium:fullReset", "projectDir": "cuyscout:projectDir", "appActivity": "appium:appActivity", "avd": "appium:avd", "deviceName": "appium:deviceName", "platformVersion": "appium:platformVersion"]
        for (argument, capability) in mapping { if let value = arguments[argument] { capabilities[capability] = value } }
        let android = (capabilities["platformName"] as? String)?.lowercased() == "android"
        capabilities["appium:automationName"] = android ? "UiAutomator2" : "XCUITest"
        if android, let package = capabilities.removeValue(forKey: "appium:bundleId") { capabilities["appium:appPackage"] = package }
        return try CapabilityNegotiator.negotiate(capabilities)
    }
}
