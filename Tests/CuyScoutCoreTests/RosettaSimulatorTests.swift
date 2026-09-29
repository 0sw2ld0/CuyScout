import XCTest
@testable import CuyScoutCore

final class RosettaSimulatorTests: XCTestCase {
    func testClassifiesAppArchitectures() {
        XCTAssertEqual(RosettaSimulator.classify(["x86_64", "arm64"]), .native)
        XCTAssertEqual(RosettaSimulator.classify(["arm64"]), .native)
        XCTAssertEqual(RosettaSimulator.classify(["x86_64", "arm64e"]), .native)
        XCTAssertEqual(RosettaSimulator.classify(["x86_64"]), .rosettaOnly)
        XCTAssertEqual(RosettaSimulator.classify([]), .unknown)
    }

    func testReadsArchitecturesFromTheAppExecutable() throws {
        let app = FileManager.default.temporaryDirectory.appendingPathComponent("Arch-\(UUID()).app")
        defer { try? FileManager.default.removeItem(at: app) }
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try FileManager.default.copyItem(atPath: "/usr/bin/true", toPath: app.appendingPathComponent("Demo").path)
        try (["CFBundleExecutable": "Demo"] as NSDictionary).write(to: app.appendingPathComponent("Info.plist"))
        let archs = RosettaSimulator.architectures(ofApp: app.path)
        XCTAssertTrue(archs.contains("arm64") || archs.contains("arm64e"), "binario del sistema: \(archs)")
        XCTAssertFalse(RosettaSimulator.needsRosetta(appPath: app.path))
    }

    func testFindsX86RuntimesAndPrefersAProIPhone() throws {
        let json = #"""
        {"runtimes": [
          {"identifier": "com.apple.CoreSimulator.SimRuntime.iOS-26-5", "name": "iOS 26.5", "version": "26.5", "isAvailable": true, "platform": "iOS", "supportedArchitectures": ["arm64"], "supportedDeviceTypes": []},
          {"identifier": "com.apple.CoreSimulator.SimRuntime.iOS-26-4", "name": "iOS 26.4", "version": "26.4", "isAvailable": true, "platform": "iOS", "supportedArchitectures": ["arm64", "x86_64"],
           "supportedDeviceTypes": [
             {"identifier": "iPhone-16", "name": "iPhone 16", "productFamily": "iPhone"},
             {"identifier": "iPhone-17-Pro", "name": "iPhone 17 Pro", "productFamily": "iPhone"},
             {"identifier": "iPad-Air", "name": "iPad Air", "productFamily": "iPad"}]}
        ]}
        """#
        let runtimes = RosettaSimulator.runtimes(from: Data(json.utf8))
        let x86 = runtimes.filter { $0.architectures.contains("x86_64") }
        XCTAssertEqual(x86.map(\.name), ["iOS 26.4"])
        XCTAssertEqual(RosettaSimulator.preferredDeviceType(in: try XCTUnwrap(x86.first))?.name, "iPhone 17 Pro")
    }

    func testRunnerTargetsX86OnlyOnTheRosettaSimulator() {
        let rosetta = Device(id: "R", name: RosettaSimulator.deviceName, runtime: "iOS-26-4", state: "Booted")
        let normal = Device(id: "N", name: "iPhone 16 Pro", runtime: "iOS-26-5", state: "Booted")
        XCTAssertEqual(ScoutEngine.runnerDestination(for: rosetta), "platform=iOS Simulator,id=R,arch=x86_64")
        XCTAssertEqual(ScoutEngine.runnerDestination(for: normal), "platform=iOS Simulator,id=N")
    }

    func testThisProcessIsNotTranslated() {
        XCTAssertFalse(RosettaSimulator.isTranslated(pid: getpid()))
    }
}
