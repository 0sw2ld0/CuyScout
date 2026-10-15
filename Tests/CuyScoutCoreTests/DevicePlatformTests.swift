import XCTest
@testable import CuyScoutCore

final class DevicePlatformTests: XCTestCase {
    func testLegacyArtifactWithoutPlatformStillLoadsAndRoundTrips() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "legacy-ios.cuyscout", withExtension: "json", subdirectory: "Fixtures"))
        let data = try Data(contentsOf: url)
        let artifact = try JSONDecoder().decode(SessionArtifactBundle.self, from: data)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("\"platform\""))
        XCTAssertEqual(artifact.session.device.platform, .ios)
        XCTAssertEqual(artifact.session.device.kind, .simulator)
        XCTAssertEqual(artifact.session.driverID, "ios-simulator")
        XCTAssertEqual(artifact.recording?.steps.first?.action, .tapElement(.init(strategy: .accessibilityIdentifier, value: "login")))
        XCTAssertEqual(try JSONDecoder().decode(SessionArtifactBundle.self, from: JSONEncoder().encode(artifact)), artifact)
    }

    func testOlderDeviceWithoutKindOrPlatformDefaultsToIOSSimulator() throws {
        let data = Data(#"{"id":"legacy","name":"iPhone","runtime":"iOS","state":"Shutdown","isAvailable":true}"#.utf8)
        let device = try JSONDecoder().decode(Device.self, from: data)
        XCTAssertEqual(device.kind, .simulator)
        XCTAssertEqual(device.platform, .ios)
        XCTAssertEqual(Device(id: "d", name: "iPhone", runtime: "iOS", state: "Booted").platform, .ios)
    }

    func testExplicitPlatformsRoundTripForBothKinds() throws {
        for platform in [Device.Platform.ios, .android] {
            for kind in [Device.Kind.simulator, .physical] {
                let device = Device(id: "d", name: "Demo", runtime: "1", state: "Booted", kind: kind, platform: platform)
                XCTAssertEqual(try JSONDecoder().decode(Device.self, from: JSONEncoder().encode(device)), device)
            }
        }
    }

    func testUnknownPlatformIsRejectedRatherThanAssumedIOS() {
        let data = Data(#"{"id":"d","name":"Demo","runtime":"1","state":"Booted","isAvailable":true,"platform":"unknown"}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(Device.self, from: data))
    }

    func testLegacyDriverDescriptorKeepsItsPlatformListBehavior() throws {
        let data = Data(#"{"id":"custom","name":"Custom","version":"1","platforms":["iOS"],"supportedCapabilities":[],"supportedSettings":[]}"#.utf8)
        let descriptor = try JSONDecoder().decode(DriverDescriptor.self, from: data)
        XCTAssertNil(descriptor.platform)
        XCTAssertNil(descriptor.deviceKind)
        XCTAssertTrue(descriptor.supports(device(.ios, .physical)))
        XCTAssertFalse(descriptor.supports(device(.android, .simulator)))
        XCTAssertFalse(descriptor.supportsReplay(on: device(.ios, .physical)))
        XCTAssertEqual(try JSONDecoder().decode(DriverDescriptor.self, from: JSONEncoder().encode(descriptor)), descriptor)
    }

    func testTypedDescriptorRestrictsPlatformAndKindWithoutDependingOnID() {
        let descriptor = DriverDescriptor(id: "custom-simulator", name: "Custom", platforms: ["iOS"], platform: .ios, deviceKind: .simulator)
        XCTAssertTrue(descriptor.supportsReplay(on: device(.ios, .simulator)))
        XCTAssertFalse(descriptor.supports(device(.ios, .physical)))
        XCTAssertFalse(descriptor.supports(device(.android, .simulator)))
        let any = DriverDescriptor(id: "any", name: "Any", platforms: ["ANY"])
        XCTAssertTrue(any.supports(device(.ios, .physical)))
        XCTAssertTrue(any.supports(device(.android, .simulator)))
    }

    func testBuiltInDescriptorsDeclareIOSAndTheirDeviceKind() {
        let engine = ScoutEngine()
        let iosDrivers = engine.drivers().filter { $0.platform == .ios }
        XCTAssertEqual(iosDrivers.count, 2)
        XCTAssertEqual(iosDrivers.first { $0.id == "ios-simulator" }?.deviceKind, .simulator)
        XCTAssertEqual(iosDrivers.first { $0.id == "ios-device" }?.deviceKind, .physical)
    }

    func testReplayMappingUsesRegisteredDescriptorsAndPreservesMatchingDriver() {
        let engine = ScoutEngine()
        engine.registerDriver(PlatformTestDriver())
        XCTAssertEqual(engine.driverID("custom-simulator", for: .physical), "ios-device")
        XCTAssertEqual(engine.driverID("custom-simulator", for: .simulator), "custom-simulator")
        engine.unregisterDriver(id: "ios-device")
        XCTAssertEqual(engine.driverID("custom-simulator", for: .physical), "custom-simulator")
        XCTAssertEqual(engine.driverID("unregistered", for: .physical), "unregistered")
    }

    func testCapabilitiesUseDevicePlatformAndKeepIOSCapabilities() {
        for platform in [Device.Platform.ios, .android] {
            let session = Session(id: "s", device: device(platform, .simulator), bundleIdentifier: "com.example.demo", createdAt: Date(), automationPort: 8200)
            let capabilities = ScoutEngine.sessionCapabilities(for: session)
            XCTAssertEqual(capabilities["platformName"] as? String, platform.platformName)
            XCTAssertEqual(capabilities["appium:udid"] as? String, "d")
            XCTAssertEqual(capabilities["appium:bundleId"] as? String, "com.example.demo")
            XCTAssertEqual(capabilities["cuyscout:automationPort"] as? Int, 8200)
            if platform == .ios {
                XCTAssertEqual(capabilities["automationName"] as? String, "XCUITest")
                XCTAssertEqual(capabilities["appium:automationName"] as? String, "XCUITest")
            }
        }
    }

    func testSessionSelectionHonorsCustomDriverKindAndReleasesRejectedCandidates() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("platform-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let engine = ScoutEngine(artifactStore: ArtifactStore(directory: root))
        let simulator = try XCTUnwrap(engine.listDevices().first { $0.kind == .simulator && $0.isAvailable })
        engine.registerDriver(PlatformTestDriver(kind: .physical))
        XCTAssertThrowsError(try engine.createSession(deviceID: simulator.id, bundleIdentifier: nil, driverID: "custom-simulator"))
        XCTAssertTrue(engine.schedulerLeases().isEmpty)
        engine.registerDriver(PlatformTestDriver())
        let session = try engine.createSession(deviceID: simulator.id, bundleIdentifier: nil, driverID: "custom-simulator")
        XCTAssertEqual(session.device.platform, .ios)
        XCTAssertEqual(session.device.kind, .simulator)
        XCTAssertEqual(try engine.sessionCapabilities(sessionID: session.id)["platformName"] as? String, "iOS")
        try engine.deleteSession(session.id)
        XCTAssertTrue(engine.schedulerLeases().isEmpty)
    }

    private func device(_ platform: Device.Platform, _ kind: Device.Kind) -> Device {
        Device(id: "d", name: "Demo", runtime: "1", state: "Booted", kind: kind, platform: platform)
    }
}

private final class PlatformTestDriver: CuyScoutDriver, @unchecked Sendable {
    let descriptor: DriverDescriptor
    init() { descriptor = DriverDescriptor(id: "custom-simulator", name: "Custom", platforms: ["iOS"], platform: .ios, deviceKind: .simulator) }
    init(kind: Device.Kind) { descriptor = DriverDescriptor(id: "custom-simulator", name: "Custom", platforms: ["iOS"], platform: .ios, deviceKind: kind) }
    func health() -> DriverHealth { DriverHealth(healthy: true, message: "test") }
    func execute(_ action: ScoutAction, on device: Device) throws -> Data? { nil }
}
