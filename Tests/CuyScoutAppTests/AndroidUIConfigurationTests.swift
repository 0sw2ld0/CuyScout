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

    func testRecordingKeepsExplicitEmulatorSerialWhenAVDHasMultipleInstances() throws {
        let project = ScoutProject(name: "Android", directory: "/project", platform: .android,
            android: .init(applicationId: "com.example.app", driverId: "android-emulator", deviceId: "emulator-5556"))
        let devices = ["emulator-5554", "emulator-5556"].map {
            Device(id: $0, name: "Pixel", runtime: "Android 15", state: "Booted", kind: .simulator, platform: .android)
        }
        let caps = try project.recordingCapabilities(selection: project.initialDeviceSelection, devices: devices)
        XCTAssertEqual(caps["appium:udid"] as? String, "emulator-5556")
        XCTAssertNil(caps["appium:avd"], "An explicit serial must not become an ambiguous AVD name")
    }

    @MainActor func testReplayRejectsOtherPlatformAndPackageBeforeContactingGateway() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "cuyscout-ui-review-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = ScoutAppModel(defaults: defaults, detectSigningTeams: false)
        // No server: an incompatible recording must be rejected before HTTP import.
        model.gatewayURL = "http://127.0.0.1:1"
        model.connected = true
        let project = ScoutProject(name: "Android", directory: root.path, platform: .android,
                                   android: .init(applicationId: "com.example.current", driverId: "android-device"))
        let artifactURL = root.appendingPathComponent("old.cuyscout.json")
        let values = root.appendingPathComponent("values.json")
        try Data("{}".utf8).write(to: values)
        let scenario = ProjectScenario(name: "old", artifactURL: artifactURL, featureURL: nil, validationURL: nil, valuesURL: values)
        for platform in [Device.Platform.ios, .android] {
            let session = Session(id: "old", device: .init(id: "original", name: "Original", runtime: "Fixture", state: "Booted", kind: .physical, platform: platform),
                                  bundleIdentifier: "com.example.previous", createdAt: Date(), driverID: platform == .android ? "android-device" : "ios-device")
            let recording = RecordedSession(sessionID: session.id, startedAt: Date(), stoppedAt: Date(), steps: [
                RecordedStep(index: 0, action: .assertVisible(.init(strategy: .accessibilityIdentifier, value: "login")), startedAt: Date(), durationMilliseconds: 1, success: true)
            ], session: session)
            let artifact = SessionArtifactBundle(session: session, events: [], metrics: .init(totalCommands: 0, successfulCommands: 0, failedCommands: 0, failureRate: 0, averageDurationMilliseconds: 0, p95DurationMilliseconds: 0, commandCounts: [:]), checkpoints: [], testPlan: nil, recording: recording, redactSensitiveData: false)
            var matching = project
            matching.platform = platform
            matching.android?.applicationId = "com.example.previous"
            XCTAssertNoThrow(try matching.validateReplayArtifact(artifact), "Compatible recordings must remain replayable")
            try JSONEncoder().encode(artifact).write(to: artifactURL)
            do {
                _ = try await model.preflightReplay(project: project, scenario: scenario, deviceID: nil, preparation: .restart)
                XCTFail("The incompatible recording must not reach the gateway")
            } catch {
                let expected = platform == .ios ? "plataforma" : "package"
                XCTAssertTrue(error.localizedDescription.contains(expected), "Expected a \(expected) mismatch, got: \(error)")
            }
            await model.replay(project: project, scenario: scenario)
            XCTAssertTrue(model.notice?.contains(platform == .ios ? "plataforma" : "package") == true,
                          "Direct replay must apply the same check as preflight")
        }
    }

    func testReplayPreflightKeepsOtherDestinationKindsSelectable() throws {
        let project = ScoutProject(name: "Android", directory: "/project", platform: .android,
            android: .init(applicationId: "com.example.app", driverId: "android-emulator"))
        let emulator = Device(id: "emulator-5554", name: "Pixel", runtime: "Android", state: "Booted", kind: .simulator, platform: .android)
        let phone = Device(id: "USB", name: "Phone", runtime: "Android", state: "Booted", kind: .physical, platform: .android)
        let cold = Device(id: "Cold", name: "Cold", runtime: "Android", state: "Shutdown", kind: .simulator, platform: .android)
        let iphone = Device(id: "iPhone", name: "iPhone", runtime: "iOS", state: "Booted", kind: .physical)
        let devices = [emulator, phone, cold, iphone]
        // The gateway preflight returns only devices of the kind being checked.
        for checked in [[emulator], [phone], []] {
            let choices = project.replayDestinations(devices: devices, checkedDevices: checked)
            XCTAssertEqual(Set(choices.map(\.id)), Set([emulator.id, phone.id, cold.id]))
            XCTAssertEqual(choices.count, 3, "A checked device must appear only once")
        }
        let updated = Device(id: emulator.id, name: "Updated Pixel", runtime: "Android 16", state: "Booted", kind: .simulator, platform: .android)
        let choices = project.replayDestinations(devices: devices, checkedDevices: [updated])
        XCTAssertEqual(choices.first { $0.id == emulator.id }?.runtime, "Android 16")
        XCTAssertEqual(project.replayDestinations(devices: [emulator], checkedDevices: [phone]).map(\.id), [phone.id, emulator.id])
    }

    func testAVDNameCannotResolveToPhysicalAndroidWithSameName() throws {
        let project = ScoutProject(name: "Android", directory: "/project", platform: .android,
            android: .init(applicationId: "com.example.app", driverId: "android-emulator", avd: "Pixel"))
        let devices = [
            Device(id: "USB", name: "Pixel", runtime: "Android 15", state: "Booted", kind: .physical, platform: .android),
            Device(id: "emulator-5554", name: "Pixel", runtime: "Android 15", state: "Booted", kind: .simulator, platform: .android)
        ]
        let caps = try project.recordingCapabilities(selection: project.initialDeviceSelection, devices: devices)
        XCTAssertEqual(caps["appium:driverId"] as? String, "android-emulator")
        XCTAssertEqual(caps["appium:avd"] as? String, "Pixel")
        XCTAssertNil(caps["appium:udid"])
    }

}
