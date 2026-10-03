import XCTest
@testable import CuyScoutCore

final class RunnerProvisioningTests: XCTestCase {
    private let first = "00000000-0000000000000001"
    private let second = "00000000-0000000000000002"

    /// Un `.mobileprovision` de mentira: bytes de firma alrededor del plist en claro.
    private func profile(devices: [String], expires: Date = Date().addingTimeInterval(86_400 * 30), allDevices: Bool = false) throws -> Data {
        var plist: [String: Any] = ["Name": "Perfil de prueba", "ExpirationDate": expires, "ProvisionedDevices": devices]
        if allDevices { plist["ProvisionsAllDevices"] = true }
        let xml = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        return Data([0x30, 0x82, 0x1f, 0x00]) + xml + Data([0xa0, 0x82, 0x0b, 0x00])
    }

    func testProfileAllowsOnlyListedAndUnexpiredDevices() throws {
        XCTAssertEqual(ScoutEngine.provisioningProfile(try profile(devices: [first]), allows: first), true)
        XCTAssertEqual(ScoutEngine.provisioningProfile(try profile(devices: [first]), allows: second), false)
        XCTAssertEqual(ScoutEngine.provisioningProfile(try profile(devices: [first.lowercased()]), allows: first), true)
        XCTAssertEqual(ScoutEngine.provisioningProfile(try profile(devices: [first], expires: Date().addingTimeInterval(60)), allows: first), false, "a punto de caducar")
        XCTAssertEqual(ScoutEngine.provisioningProfile(try profile(devices: [], allDevices: true), allows: second), true)
        XCTAssertNil(ScoutEngine.provisioningProfile(Data("sin plist".utf8), allows: first))
    }

    func testRunnerIsResignedWhenItsProfileDoesNotIncludeTheIPhone() throws {
        let products = FileManager.default.temporaryDirectory.appendingPathComponent("cuyscout-profile-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: products) }
        let app = products.appendingPathComponent("Debug-iphoneos/ScoutRunner-Runner.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        let xctestrun = products.appendingPathComponent("ScoutRunner_iphoneos-arm64.xctestrun").path
        XCTAssertNil(ScoutEngine.runnerProfileAllows(deviceID: first, xctestrun: xctestrun), "sin perfil no se fuerza nada")
        try profile(devices: [first]).write(to: app.appendingPathComponent("embedded.mobileprovision"))
        XCTAssertEqual(ScoutEngine.runnerProfileAllows(deviceID: first, xctestrun: xctestrun), true)
        XCTAssertEqual(ScoutEngine.runnerProfileAllows(deviceID: second, xctestrun: xctestrun), false)
    }

    func testRunnerLogExplainsAnUnprovisionedIPhone() throws {
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("cuyscout-runner-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: log) }
        try "Failed to install embedded profile for com.example.runner : 0xe8008012 (This provisioning profile cannot be installed on this device.)".write(to: log, atomically: true, encoding: .utf8)
        XCTAssertTrue(ScoutEngine.runnerLogShowsUnprovisionedDevice(logPath: log.path))
        XCTAssertTrue(ScoutEngine.runnerTimeoutMessage(logPath: log.path).hasPrefix("runner_not_provisioned"))
        try "Test Suite started".write(to: log, atomically: true, encoding: .utf8)
        XCTAssertFalse(ScoutEngine.runnerLogShowsUnprovisionedDevice(logPath: log.path))
    }

    func testAgentsAndOpenSessionHandleAnUnprovisionedRunner() throws {
        let options = ProjectScaffolder.Options(appName: "Demo", appPath: "/tmp/Demo.app", cuyscoutRepoPath: "")
        XCTAssertTrue(ProjectScaffolder.agentsMarkdownBlock(for: options).contains("`runner_not_provisioned`"))
        let script = try XCTUnwrap(ProjectScaffolder.files(for: options)["scripts/open-session.sh"])
        XCTAssertTrue(script.contains(#""runner_not_provisioned" in blockers"#))
        XCTAssertTrue(script.contains("exit 4"))
    }

    func testOutdatedGatewayIsDetectedByItsBuild() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("cuyscout-build-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("v1".utf8).write(to: file)
        let build = try XCTUnwrap(GatewayBuild.identifier(of: file))
        XCTAssertFalse(GatewayBuild.isOutdated(running: build, bundled: build))
        XCTAssertTrue(GatewayBuild.isOutdated(running: nil, bundled: build), "un gateway anterior no informa su compilación")
        XCTAssertTrue(GatewayBuild.isOutdated(running: "1-1", bundled: build))
        XCTAssertFalse(GatewayBuild.isOutdated(running: nil, bundled: nil), "sin gateway incluido en la app no se decide nada")
    }
}

final class RunnerGatewayURLTests: XCTestCase {
    func testSimulatorRunnerUsesLoopbackAndIPhoneUsesTheNetworkAddress() {
        let simulator = Device(id: "SIM", name: "iPhone 16", runtime: "iOS 18", state: "Booted", kind: .simulator)
        let iPhone = Device(id: "00000000-0000000000000001", name: "iPhone", runtime: "iOS 18", state: "connected", kind: .physical)
        XCTAssertEqual(ScoutEngine.runnerGatewayURL(base: "http://10.0.0.5:4724", device: simulator), "http://127.0.0.1:4724")
        XCTAssertEqual(ScoutEngine.runnerGatewayURL(base: "http://10.0.0.5:4724", device: iPhone), "http://10.0.0.5:4724")
        XCTAssertEqual(ScoutEngine.runnerGatewayURL(base: "http://127.0.0.1:4723", device: simulator), "http://127.0.0.1:4723")
    }
}

final class KeyboardRuleTests: XCTestCase {
    func testAgentsSaysTheKeyboardClosesAfterTyping() throws {
        let options = ProjectScaffolder.Options(appName: "Demo", appPath: "/tmp/Demo.app", cuyscoutRepoPath: "")
        let agents = ProjectScaffolder.agentsMarkdownBlock(for: options)
        XCTAssertTrue(agents.contains("después de ingresar un dato, el teclado se cierra"))
        XCTAssertTrue(agents.contains("`keyboard_still_open`"))
    }

    func testRunnerClosesTheKeyboardWithoutSubmitting() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Runner/ScoutRunner/ScoutRunner/ScoutBridgeRunner.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("if dismissKeyboard { dismissKeyboardIfShown() }"))
        XCTAssertTrue(source.contains("dismissKeyboard: false"), "borrar un campo deja el teclado abierto para escribir")
        // Nunca teclas que envían el formulario.
        XCTAssertFalse(source.contains("\"go\", ") || source.contains("\"enviar\""))
    }
}
