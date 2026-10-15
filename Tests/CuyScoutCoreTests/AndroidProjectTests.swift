import XCTest
@testable import CuyScoutCore

final class AndroidProjectTests: XCTestCase {
    private func root() -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Android Project " + UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }; return root
    }
    func testUpdateRetainsAndroidConfigAndProjectOwnedContent() throws {
        let path = root()
        let android = AndroidProjectConfiguration(apk: "/apps/Demo Wallet.apk", applicationId: "com.example.wallet", activity: ".MainActivity", driverId: "android-device", deviceId: "USB_FAKE")
        let options = ProjectScaffolder.Options(appName: "Wallet", appPath: android.apk, cuyscoutRepoPath: "", useMCP: true, platform: .android, android: android)
        try ProjectUpdater.write(options: options, vscode: false, to: path)
        try "Feature: Pago\n".write(to: path.appendingPathComponent("features/pago.feature"), atomically: true, encoding: .utf8)
        var config = try XCTUnwrap(ProjectUpdater.readConfig(path)); config["simulator"] = "/apps/Wallet.app"; config["custom"] = "keep"
        var settings = config["android"] as! [String: Any]; settings["custom"] = "keep"; config["android"] = settings
        try JSONSerialization.data(withJSONObject: config).write(to: path.appendingPathComponent(ProjectUpdater.configFile))
        try ProjectUpdater.update(path)
        let (restored, _) = ProjectUpdater.inferSettings(for: path)
        XCTAssertEqual(restored.platform, .android); XCTAssertEqual(restored.android, android); XCTAssertTrue(restored.useMCP)
        config = try XCTUnwrap(ProjectUpdater.readConfig(path))
        XCTAssertEqual(config["simulator"] as? String, "/apps/Wallet.app"); XCTAssertEqual(config["custom"] as? String, "keep")
        XCTAssertEqual((config["android"] as? [String: Any])?["custom"] as? String, "keep")
        XCTAssertEqual(try String(contentsOf: path.appendingPathComponent("features/pago.feature"), encoding: .utf8), "Feature: Pago\n")
        XCTAssertFalse(ProjectUpdater.needsUpdate(path))
    }
    func testAndroidDoesNotSeedSimulatorWithAnAPK() throws {
        let path = root(), android = AndroidProjectConfiguration(apk: "/apps/Wallet.apk", applicationId: "com.example.wallet")
        try ProjectUpdater.write(options: .init(appName: "Wallet", appPath: android.apk, cuyscoutRepoPath: "", platform: .android, android: android), vscode: false, to: path, simulatorApp: android.apk)
        let config = try XCTUnwrap(ProjectUpdater.readConfig(path))
        XCTAssertEqual(config["simulator"] as? String, ""); XCTAssertEqual(config["platform"] as? String, "android")
    }
    func testInvalidAndroidSettingsFailBeforeWritingProject() {
        for android in [AndroidProjectConfiguration(applicationId: "bad;package"), .init(apk: "App.app", applicationId: "com.example.app"), .init(applicationId: "com.example.app", driverId: "ios-device"), .init(applicationId: "com.example.app", driverId: "android-device", avd: "Pixel")] {
            let path = root()
            XCTAssertThrowsError(try ProjectUpdater.write(options: .init(appName: "App", appPath: android.apk, cuyscoutRepoPath: "", platform: .android, android: android), vscode: false, to: path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: path.path))
        }
    }
    func testInstalledAppDoesNotRequireAPK() throws {
        let path = root(), android = AndroidProjectConfiguration(applicationId: "com.example.wallet", driverId: "android-device")
        try ProjectUpdater.write(options: .init(appName: "Wallet", appPath: "", cuyscoutRepoPath: "", platform: .android, android: android), vscode: false, to: path)
        XCTAssertEqual(ProjectUpdater.inferSettings(for: path).0.android, android)
    }
    func testAndroidGuideKeepsObserveLoopSeparateFromIOS() {
        let ios = ProjectScaffolder.Options(appName: "Wallet", appPath: "App.app", cuyscoutRepoPath: "/repo")
        var android = ios; android.platform = .android
        let guide = ProjectScaffolder.agentsMarkdownBlock(for: android)
        XCTAssertTrue(guide.contains("cuyscout-android/SKILL.md")); XCTAssertTrue(guide.contains("observe → decidir → execute → observe"))
        XCTAssertFalse(guide.contains("Lee AGENT-GUIDE.md")); XCTAssertFalse(guide.contains("MCP"))
        android.useMCP = true
        XCTAssertTrue(ProjectScaffolder.agentsMarkdownBlock(for: android).contains("MCP primero"))
        XCTAssertTrue(ProjectScaffolder.agentsMarkdownBlock(for: ios).contains("AGENT-GUIDE.md"))
    }
    func testAgentCapabilitiesShareAndroidAndIOSDefaults() throws {
        let caps = try AgentSessionCapabilities.make(["driverId": "android-device", "bundleIdentifier": "com.example.wallet", "appPath": "/apps/Wallet.apk", "appActivity": ".MainActivity", "deviceId": "USB_FAKE", "noReset": true])
        XCTAssertEqual(caps["platformName"] as? String, "Android"); XCTAssertEqual(caps["appium:automationName"] as? String, "UiAutomator2")
        XCTAssertEqual(caps["appium:appPackage"] as? String, "com.example.wallet"); XCTAssertNil(caps["appium:bundleId"])
        XCTAssertEqual(caps["appium:appActivity"] as? String, ".MainActivity"); XCTAssertEqual(caps["appium:udid"] as? String, "USB_FAKE")
        let ios = try AgentSessionCapabilities.make(["bundleIdentifier": "com.example.wallet"])
        XCTAssertEqual(ios["platformName"] as? String, "iOS"); XCTAssertEqual(ios["appium:bundleId"] as? String, "com.example.wallet")
        XCTAssertThrowsError(try AgentSessionCapabilities.make(["platformName": "Android", "noReset": true, "fullReset": true]))
    }
}
