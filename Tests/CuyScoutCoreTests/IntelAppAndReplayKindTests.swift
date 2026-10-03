import XCTest
@testable import CuyScoutCore

final class IntelAppAndReplayKindTests: XCTestCase {
    private let old = "com.apple.CoreSimulator.SimRuntime.iOS-18-3"
    private let universal = "com.apple.CoreSimulator.SimRuntime.iOS-26-4"

    private func sim(_ name: String, _ runtime: String, booted: Bool = false) -> Device {
        Device(id: "\(name)-\(runtime)", name: name, runtime: runtime, state: booted ? "Booted" : "Shutdown")
    }

    func testIntelAppsPreferABootedThenNewestUniversalSimulator() {
        let versions = [old: "18.3", universal: "26.4"]
        let booted = sim("iPhone 16", old, booted: true)
        XCTAssertEqual(RosettaSimulator.preferredIntelDevice([sim("iPhone 17 Pro", universal), booted], versions: versions), booted)
        XCTAssertEqual(RosettaSimulator.preferredIntelDevice([sim("iPhone 16 Pro", old), sim("iPhone 17", universal), sim("iPhone 17 Pro", universal)], versions: versions)?.name, "iPhone 17 Pro")
        XCTAssertNil(RosettaSimulator.preferredIntelDevice([], versions: versions))
    }

    func testReplayOnAnotherDevicePrefersAStandardIPhone() {
        let recorded = Device(id: "00000000-0000000000000001", name: "iPhone de alguien", runtime: "iOS 26.4", state: "connected", kind: .physical)
        let small = sim("iPhone SE (3rd generation)", universal, booted: true)
        let renamed = sim("Simulador de pruebas", universal, booted: true)
        let standard = sim("iPhone 17 Pro", universal)
        XCTAssertEqual(ScoutEngine.preferredReplayDevice(from: [small, renamed, standard], recorded: recorded), standard)
        // Si la prueba se grabó justo en un SE, se respeta ese modelo.
        let recordedSE = sim("iPhone SE (3rd generation)", old)
        XCTAssertEqual(ScoutEngine.preferredReplayDevice(from: [small, standard], recorded: recordedSE), small)
    }

    func testRejectionExplainsWhichRuntimeWorks() {
        let message = ScoutEngine.intelAppRejection(sim("iPhone 17 Pro", "com.apple.CoreSimulator.SimRuntime.iOS-26-5"))
        XCTAssertTrue(message.contains("iOS-26-5"))
        XCTAssertTrue(message.contains("x86_64"))
    }

    func testReplayOnAnotherKindUsesThatKindsDriver() {
        XCTAssertEqual(ScoutEngine.driverID("ios-device", for: .simulator), "ios-simulator")
        XCTAssertEqual(ScoutEngine.driverID("ios-simulator", for: .physical), "ios-device")
        XCTAssertEqual(ScoutEngine.driverID("custom", for: .physical), "custom")
    }

    func testReplayScriptFollowsTheProjectLikeOpenSession() throws {
        let options = ProjectScaffolder.Options(appName: "Demo", appPath: "/tmp/Demo.app", cuyscoutRepoPath: "")
        let script = try XCTUnwrap(ProjectScaffolder.files(for: options)["scripts/replay-cuyscout.sh"])
        XCTAssertTrue(script.contains(#""deviceKind": os.environ["REPLAY_KIND"]"#))
        XCTAssertTrue(script.contains("ios-device) TARGET_KIND=\"physical\""))
        XCTAssertTrue(script.contains("export CUYSCOUT_NEEDS_PHYSICAL=1"))
        XCTAssertTrue(ProjectScaffolder.agentsMarkdownBlock(for: options).contains("aunque la prueba se haya grabado en un iPhone"))
    }
}
