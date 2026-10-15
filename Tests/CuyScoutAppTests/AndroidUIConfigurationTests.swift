import XCTest
import CuyScoutCore
@testable import CuyScoutApp

final class AndroidUIConfigurationTests: XCTestCase {
    func testLegacySavedProjectDefaultsToIOS() throws {
        let old: [String: Any] = ["id": UUID().uuidString, "name": "Legacy", "directory": "/tmp/legacy", "appPath": "/apps/App.app"]
        let project = try JSONDecoder().decode(ScoutProject.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertEqual(project.platform, .ios)
        XCTAssertNil(project.android)
        XCTAssertTrue(project.canRecord)
    }

    func testRecordingUsesAndroidPackageAPKAndColdAVD() throws {
        let config = AndroidProjectConfiguration(apk: "/apps/App.apk", applicationId: "com.example.app", activity: ".MainActivity", driverId: "android-emulator", avd: "Pixel")
        let project = ScoutProject(name: "Android", directory: "/project", platform: .android, android: config)
        let device = Device(id: "Pixel", name: "Pixel", runtime: "Android", state: "Shutdown", kind: .simulator, platform: .android)
        let caps = try project.recordingCapabilities(selection: project.initialDeviceSelection, devices: [device])
        XCTAssertEqual(caps["platformName"] as? String, "Android")
        XCTAssertEqual(caps["appium:automationName"] as? String, "UiAutomator2")
        XCTAssertEqual(caps["appium:appPackage"] as? String, "com.example.app")
        XCTAssertEqual(caps["appium:app"] as? String, "/apps/App.apk")
        XCTAssertEqual(caps["appium:avd"] as? String, "Pixel")
        XCTAssertNil(caps["appium:udid"])
        XCTAssertEqual(caps["cuyscout:projectDir"] as? String, "/project")
    }

    func testPhysicalAndroidWithoutAPKAndCrossPlatformRejection() throws {
        let project = ScoutProject(name: "Android", directory: "/project", platform: .android,
                                   android: .init(applicationId: "com.example.app", driverId: "android-device", deviceId: "USB"))
        let caps = try project.recordingCapabilities(selection: project.initialDeviceSelection, devices: [])
        XCTAssertEqual(caps["appium:driverId"] as? String, "android-device")
        XCTAssertEqual(caps["appium:udid"] as? String, "USB")
        XCTAssertNil(caps["appium:app"])
        XCTAssertTrue(project.canRecord)
        let iphone = Device(id: "iPhone", name: "iPhone", runtime: "iOS", state: "Booted", kind: .physical)
        XCTAssertThrowsError(try project.recordingCapabilities(selection: iphone.id, devices: [iphone]))
    }

    @MainActor func testConfigurationPersistsSwitchesAndAgentSettingsWithoutLosingIOSOrFeatures() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "cuyscout-ui-test-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = ScoutAppModel(defaults: defaults, detectSigningTeams: false)
        try ProjectUpdater.write(options: .init(appName: "App", appPath: "/apps/App.app", cuyscoutRepoPath: "", useMCP: true), vscode: false, to: root, simulatorApp: "/apps/App.app")
        try "Feature: Keep me".write(to: root.appendingPathComponent("features/keep.feature"), atomically: true, encoding: .utf8)
        let project = try model.openProject(at: root)
        try model.configureProject(project, platform: .android, android: .init(applicationId: "com.example.app", driverId: "android-emulator", avd: "Pixel"))
        XCTAssertEqual(model.projects.first?.platform, .android)
        XCTAssertEqual(WorkspaceFiles.installers(in: root)?.android?.avd, "Pixel")
        XCTAssertTrue(try String(contentsOf: root.appendingPathComponent("AGENTS.md"), encoding: .utf8).contains("app Android"))
        try model.configureProject(model.projects[0], platform: .android, android: .init(applicationId: "com.example.app", driverId: "android-device"))
        XCTAssertNil(ProjectUpdater.inferSettings(for: root).0.android?.avd)
        try model.configureProject(model.projects[0], platform: .ios, android: nil)
        XCTAssertEqual(model.projects.first?.appPath, "/apps/App.app")
        XCTAssertEqual(model.projects.first?.platform, .ios)
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("features/keep.feature"), encoding: .utf8), "Feature: Keep me")
        XCTAssertTrue(ProjectUpdater.inferSettings(for: root).0.useMCP)
    }
    func testReplayResolvesConfiguredAVDToItsRunningSerial() {
        let project = ScoutProject(name: "Android", directory: "/project", platform: .android,
                                   android: .init(applicationId: "com.example.app", driverId: "android-emulator", avd: "Pixel"))
        let running = Device(id: "emulator-5554", name: "Pixel", runtime: "Android 15", state: "Booted", kind: .simulator, platform: .android)
        XCTAssertEqual(project.replayDeviceID(override: nil, devices: [running]), "emulator-5554")
        XCTAssertEqual(project.replayDeviceID(override: nil, devices: []), "Pixel")
        XCTAssertEqual(project.replayDeviceID(override: "USB", devices: [running]), "USB")
    }

    func testIOSRecordingKeepsInstallerAndInstalledIPhoneCapabilities() throws {
        let project = ScoutProject(name: "iOS", directory: "/project", appPath: "/App.app", physicalBundleID: "com.example.ios")
        let simulator = try project.recordingCapabilities(selection: "", devices: [])
        XCTAssertEqual(simulator["appium:driverId"] as? String, "ios-simulator")
        XCTAssertEqual(simulator["appium:app"] as? String, "/App.app")
        let physical = try project.recordingCapabilities(selection: "physical:auto", devices: [])
        XCTAssertEqual(physical["appium:bundleId"] as? String, "com.example.ios")
        XCTAssertEqual(physical["appium:driverId"] as? String, "ios-device")
        XCTAssertNil(physical["appium:app"])
    }

    @MainActor func testCreateAndroidProjectPersistsAPKAndReloadsCLIEdits() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let apk = root.appendingPathComponent("Demo App.apk")
        try Data().write(to: apk)
        let suite = "cuyscout-ui-test-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = ScoutAppModel(defaults: defaults, detectSigningTeams: false)
        let projectRoot = root.appendingPathComponent("Project")
        let android = AndroidProjectConfiguration(apk: apk.path, applicationId: "com.example.app", driverId: "android-device", deviceId: "USB")
        try model.createProject(name: "Android", directory: projectRoot, installer: nil, useMCP: true, platform: .android, android: android)
        XCTAssertEqual(model.projects.first?.android, android)
        XCTAssertEqual(model.projects.first?.appPath, "", "An APK must never occupy the iOS installer slot")
        let saved = try JSONDecoder().decode([ScoutProject].self, from: XCTUnwrap(defaults.data(forKey: "cuyscout.projects.v1")))
        XCTAssertEqual(saved.first?.android, android)
        let cli: [String: Any] = ["platform": "android", "android": ["apk": "", "applicationId": "com.example.installed", "driverId": "android-device"]]
        try JSONSerialization.data(withJSONObject: cli).write(to: projectRoot.appendingPathComponent(ProjectUpdater.configFile))
        model.syncProjectsFromDisk()
        XCTAssertEqual(model.projects.first?.android?.apk, "")
        XCTAssertEqual(model.projects.first?.android?.applicationId, "com.example.installed")
        XCTAssertEqual(model.projects.first?.platform, .android)
        XCTAssertNil(model.projects.first?.android?.deviceId)
    }

    @MainActor func testInvalidAPKOrPackageDoesNotCreateProject() throws {
        let suite = "cuyscout-ui-test-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = ScoutAppModel(defaults: defaults, detectSigningTeams: false)
        for config in [AndroidProjectConfiguration(apk: "/missing/App.apk", applicationId: "com.example.app"),
                       .init(apk: "/App.ipa", applicationId: "com.example.app"),
                       .init(applicationId: "bad-package")] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            XCTAssertThrowsError(try model.createProject(name: "Invalid", directory: root, installer: nil, platform: .android, android: config))
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        }
        XCTAssertTrue(model.projects.isEmpty)
    }

}
