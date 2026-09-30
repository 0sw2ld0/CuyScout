import XCTest
@testable import CuyScoutCore

final class ScoutLogTests: XCTestCase {
    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("scoutlog-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testLinesAreReadableAndNeverCarrySecrets() {
        let line = ScoutLog.format(.warning, "http", "Petición rechazada", ["status": 401, "token": "abc123", "text": "mi clave", "path": "/session/1/actions", "nota": "correo qa@example.com"],
                                   date: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(line.hasPrefix("1970-01-01T00:00:00.000Z WARN [http] Petición rechazada"))
        XCTAssertTrue(line.contains("status=401"))
        XCTAssertTrue(line.contains("path=/session/1/actions"))
        XCTAssertTrue(line.contains("token=<oculto>"))
        XCTAssertTrue(line.contains("text=<oculto>"))
        XCTAssertFalse(line.contains("abc123"))
        XCTAssertFalse(line.contains("mi clave"))
        XCTAssertFalse(line.contains("qa@example.com"))
        XCTAssertFalse(ScoutLog.format(.info, "x", "y", ["context": "NATIVE_APP"]).contains("<oculto>"))
        let device = ScoutLog.format(.info, "runner", "Runner lanzado", ["destination": "platform=iOS,id=00001111-000A0B0C0D0E0F10", "cuenta": "19112345678901"])
        XCTAssertTrue(device.contains("id=00001111-000A0B0C0D0E0F10"))
        XCTAssertTrue(device.contains("cuenta=<oculto>"))
    }

    func testWritesTailsRotatesAndFiltersByLevel() throws {
        let directory = temporaryDirectory()
        let log = ScoutLog(name: "prueba", directory: directory, maxBytes: 400, minimumLevel: .info)
        log.debug("x", "no debería aparecer")
        for index in 0..<10 { log.info("session", "Sesión \(index)", ["n": index]) }
        let tail = log.tail(lines: 3)
        XCTAssertEqual(tail.count, 3)
        XCTAssertTrue(tail.last?.contains("Sesión 9") == true)
        XCTAssertFalse(log.tail(lines: 100).contains { $0.contains("no debería aparecer") })
        XCTAssertTrue(FileManager.default.fileExists(atPath: log.fileURL.appendingPathExtension("1").path))
        let mode = (try FileManager.default.attributesOfItem(atPath: log.fileURL.path))[.posixPermissions] as? NSNumber
        XCTAssertEqual(mode?.intValue, 0o600)
    }

    func testThrottleLetsOneEventThroughPerInterval() {
        let throttle = LogThrottle(interval: 30)
        let start = Date()
        XCTAssertTrue(throttle.shouldLog(now: start))
        XCTAssertFalse(throttle.shouldLog(now: start.addingTimeInterval(5)))
        XCTAssertTrue(throttle.shouldLog(now: start.addingTimeInterval(31)))
    }
}

final class PhysicalGatewayStatusTests: XCTestCase {
    private let wifi = [LocalNetwork.Interface(name: "en0", address: "10.0.0.5"), LocalNetwork.Interface(name: "utun3", address: "10.8.0.2")]

    func testLocalModeExplainsHowToEnableTheIPhone() {
        let status = PhysicalGatewayStatus.evaluate(environment: [:], interfaces: wifi, probe: { _ in true })
        XCTAssertFalse(status.enabled)
        XCTAssertFalse(status.ready)
        XCTAssertTrue(status.issues.first?.contains("modo local") == true)
        XCTAssertFalse(status.doctorCheck().available)
    }

    func testReadyWhenTheAnnouncedIPIsThisMacAndAnswers() {
        let environment = ["CUYSCOUT_BIND_ADDRESS": "10.0.0.5", "CUYSCOUT_DEVICE_GATEWAY_URL": "http://10.0.0.5:4723", "CUYSCOUT_TOKEN": "t"]
        let status = PhysicalGatewayStatus.evaluate(environment: environment, interfaces: wifi, probe: { _ in true })
        XCTAssertTrue(status.ready)
        XCTAssertEqual(status.currentAddress, "10.0.0.5")
        XCTAssertTrue(status.doctorCheck().available)
    }

    func testDetectsANetworkChangeAnUnreachableGatewayAndAMissingToken() {
        let moved = PhysicalGatewayStatus.evaluate(environment: ["CUYSCOUT_DEVICE_GATEWAY_URL": "http://192.168.1.9:4723", "CUYSCOUT_TOKEN": "t"], interfaces: wifi, probe: { _ in true })
        XCTAssertTrue(moved.issues.first?.contains("ya no es de esta Mac") == true)
        let silent = PhysicalGatewayStatus.evaluate(environment: ["CUYSCOUT_DEVICE_GATEWAY_URL": "http://10.0.0.5:4723", "CUYSCOUT_TOKEN": "t"], interfaces: wifi, runnerContact: nil, probe: { _ in false })
        XCTAssertTrue(silent.issues.first?.contains("no responde") == true)
        let noToken = PhysicalGatewayStatus.evaluate(environment: ["CUYSCOUT_DEVICE_GATEWAY_URL": "http://10.0.0.5:4723"], interfaces: wifi, probe: { _ in true })
        XCTAssertTrue(noToken.issues.contains { $0.contains("CUYSCOUT_TOKEN") })
    }

    func testAConnectedRunnerProvesTheIPhoneReachesTheGateway() {
        // Mac corporativa: la Mac no puede consultarse por su IP de red, pero el iPhone sí llega.
        let environment = ["CUYSCOUT_DEVICE_GATEWAY_URL": "http://10.0.0.5:4723", "CUYSCOUT_TOKEN": "t"]
        var probed = false
        let status = PhysicalGatewayStatus.evaluate(environment: environment, interfaces: wifi, runnerContact: Date(), probe: { _ in probed = true; return false })
        XCTAssertFalse(probed)
        XCTAssertTrue(status.ready)
        XCTAssertTrue(status.runnerConnected)
        XCTAssertTrue(status.doctorCheck().detail.contains("ya se conectó"))
        // Un runner no arregla un gateway en modo local ni una IP que ya no es de la Mac.
        XCTAssertFalse(PhysicalGatewayStatus.evaluate(environment: [:], interfaces: wifi, runnerContact: Date(), probe: { _ in true }).ready)
        XCTAssertFalse(PhysicalGatewayStatus.evaluate(environment: ["CUYSCOUT_DEVICE_GATEWAY_URL": "http://192.168.1.9:4723", "CUYSCOUT_TOKEN": "t"], interfaces: wifi, runnerContact: Date(), probe: { _ in true }).ready)
    }

    func testPrefersWiFiAndRecognisesTheIPhoneHotspot() {
        XCTAssertEqual(LocalNetwork.primaryIPv4(from: [LocalNetwork.Interface(name: "utun3", address: "10.8.0.2")] + wifi), "10.0.0.5")
        XCTAssertTrue(LocalNetwork.isIPhoneHotspot("172.20.10.3"))
        XCTAssertFalse(LocalNetwork.isIPhoneHotspot("192.168.1.3"))
    }
}
