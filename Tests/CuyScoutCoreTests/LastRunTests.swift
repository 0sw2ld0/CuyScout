import XCTest
@testable import CuyScoutCore

final class LastRunTests: XCTestCase {
    func testScreenWithoutControlsOrTextsIsStillLoading() {
        XCTAssertFalse(ScoutEngine.treeShowsContent([]))
        XCTAssertFalse(ScoutEngine.treeShowsContent([["type": "application", "label": "Demo"], ["type": "image", "label": ""], ["type": "other", "label": ""]]))
        XCTAssertFalse(ScoutEngine.treeShowsContent([["type": "staticText", "label": "  "]]))
        XCTAssertTrue(ScoutEngine.treeShowsContent([["type": "staticText", "label": "Bienvenido"]]))
        XCTAssertTrue(ScoutEngine.treeShowsContent([["type": "button", "label": ""]]))
    }

    func testDecodesTheReportWrittenByCloseSession() throws {
        let json = #"{"scenario":"pago","status":"blocked_environment","reason":"servicio_no_disponible","step":"Given el usuario ha iniciado sesión","screenTexts":["Algo salió mal"],"finishedAt":"2026-09-30T04:00:00Z"}"#
        let report = try JSONDecoder().decode(LastRunReport.self, from: Data(json.utf8))
        XCTAssertEqual(report.status, .blockedEnvironment)
        XCTAssertEqual(report.title, "Bloqueado por entorno")
        XCTAssertEqual(report.reasonText, "servicio no disponible")
        XCTAssertNotNil(report.finishedDate)
    }

    /// Ejecuta el `close-session.sh` generado contra un gateway falso.
    func testDiscardClosesWithoutExportingAndRecordsTheOutcome() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("close-discard-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for (path, content) in ProjectScaffolder.files(for: .init(appName: "Demo", appPath: "", cuyscoutRepoPath: "")) where path.hasPrefix("scripts/") {
            let file = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: file, atomically: true, encoding: .utf8)
        }
        let log = root.appendingPathComponent("requests.log")
        let stub = """
        import http.server, json, sys
        class H(http.server.BaseHTTPRequestHandler):
            def log_message(self, *a): pass
            def reply(self, body):
                open(sys.argv[1], "a").write(self.command + " " + self.path + "\\n")
                data = json.dumps(body).encode(); self.send_response(200)
                self.send_header("Content-Type", "application/json"); self.send_header("Content-Length", str(len(data))); self.end_headers(); self.wfile.write(data)
            def do_GET(self): self.reply({"value": {"texts": ["Algo salió mal", "Cuenta 191234567890 de qa@example.com"]}})
            def do_DELETE(self): self.reply({"value": None})
        server = http.server.HTTPServer(("127.0.0.1", 0), H)
        print(server.server_port, flush=True)
        server.serve_forever()
        """
        let server = Process()
        server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        server.arguments = ["-c", stub, log.path]
        let portPipe = Pipe()
        server.standardOutput = portPipe
        try server.run()
        defer { server.terminate() }
        let port = String(decoding: portPipe.fileHandleForReading.availableData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(port.isEmpty)

        let script = Process()
        script.executableURL = URL(fileURLWithPath: "/bin/bash")
        script.arguments = [root.appendingPathComponent("scripts/close-session.sh").path, "S1", "pago", "--discard", "--reason", "servicio_no_disponible", "--step", "Given el usuario ha iniciado sesión"]
        script.environment = ["PATH": "/usr/bin:/bin", "HOME": root.path, "CUYSCOUT_URL": "http://127.0.0.1:\(port)", "CUYSCOUT_TOKEN": "t"]
        script.standardOutput = FileHandle.nullDevice
        script.standardError = FileHandle.nullDevice
        try script.run()
        script.waitUntilExit()
        XCTAssertEqual(script.terminationStatus, 0)

        let output = root.appendingPathComponent("output")
        let report = try XCTUnwrap(LastRunReport.load(scenario: "pago", outputDirectory: output))
        XCTAssertEqual(report.status, .blockedEnvironment)
        XCTAssertEqual(report.step, "Given el usuario ha iniciado sesión")
        XCTAssertEqual(report.sessionId, "S1")
        XCTAssertEqual(report.screenTexts?.first, "Algo salió mal")
        XCTAssertEqual(report.screenTexts?.last, "Cuenta <número> de <correo>")
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.appendingPathComponent("pago.cuyscout.json").path))
        let requests = try String(contentsOf: log, encoding: .utf8)
        XCTAssertTrue(requests.contains("DELETE /session/S1"))
        XCTAssertFalse(requests.contains("/artifacts"))
        XCTAssertFalse(requests.contains("recording"))
    }
}

final class DeviceLockedTests: XCTestCase {
    func testDetectsALockedIPhoneInTheRunnerLog() throws {
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("runner-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: log) }
        XCTAssertFalse(ScoutEngine.runnerLogShowsLockedDevice(logPath: log.path))
        try "Run Destination Preflight: The destination is not ready.\nNSLocalizedDescription=Unlock iPhone to Continue}\n".write(to: log, atomically: true, encoding: .utf8)
        XCTAssertTrue(ScoutEngine.runnerLogShowsLockedDevice(logPath: log.path))
    }
}
