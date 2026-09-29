import XCTest
@testable import CuyScoutCore

final class PhysicalDeviceTests: XCTestCase {
    func testCoreDeviceJSONSelectsPairedIOSAndPreservesDeviceUDID() throws {
        let data = Data(#"{"result":{"devices":[{"hardwareProperties":{"platform":"iOS","udid":"00008140-TEST"},"deviceProperties":{"name":"iPhone","osVersionNumber":"26.6.2"},"connectionProperties":{"pairingState":"paired","tunnelState":"disconnected"}},{"hardwareProperties":{"platform":"iOS","udid":"OTHER"},"deviceProperties":{"name":"Other"},"connectionProperties":{"pairingState":"paired","tunnelState":"unavailable"}},{"hardwareProperties":{"platform":"macOS","udid":"MAC"}}]}}"#.utf8)
        let devices = SimulatorController.physicalDevices(from: data)
        XCTAssertEqual(devices.count, 2)
        let byID = Dictionary(uniqueKeysWithValues: devices.map { ($0.id, $0) })
        XCTAssertEqual(byID["00008140-TEST"]?.kind, .physical)
        XCTAssertEqual(byID["00008140-TEST"]?.isAvailable, true)
        XCTAssertEqual(byID["OTHER"]?.isAvailable, false)
    }

    func testOldArtifactsDecodeDeviceAsSimulator() throws {
        let old = Data(#"{"id":"SIM","name":"iPhone","runtime":"iOS","state":"Booted","isAvailable":true}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(Device.self, from: old).kind, .simulator)
        let physical = Device(id: "PHONE", name: "iPhone", runtime: "26.6", state: "connected", kind: .physical)
        XCTAssertEqual(try JSONDecoder().decode(Device.self, from: JSONEncoder().encode(physical)), physical)
    }

    func testPhysicalDriverIsRegistered() {
        let registry = DriverRegistry()
        registry.register(PhysicalDeviceDriverAdapter())
        XCTAssertEqual(registry.driver(id: "ios-device")?.descriptor.platforms, ["iOS"])
    }

    func testLocalGatewayProfileRequiresPrivatePermissions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("cuyscout-profile-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("gateway-connection.json")
        let profile = LocalGatewayProfile(url: "http://192.168.1.2:4723", token: "test-token")
        try profile.save(to: file)
        XCTAssertEqual(LocalGatewayProfile.load(from: file), profile)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        XCTAssertNil(LocalGatewayProfile.load(from: file))
    }
}
