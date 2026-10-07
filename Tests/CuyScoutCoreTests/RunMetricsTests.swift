import XCTest
@testable import CuyScoutCore

final class RunMetricsTests: XCTestCase {
    func testCountsAgentRequestsTimeAndEstimatedTokens() {
        let start = Date(timeIntervalSince1970: 1_000)
        var metrics = RunMetricsAccumulator(startedAt: start)
        metrics.readyAt = start.addingTimeInterval(40)
        metrics.record(route: "/session/s/observe", method: "GET", status: 200, milliseconds: 1_500, responseBytes: 8_000)
        metrics.record(route: "/session/s/actions", method: "POST", status: 200, milliseconds: 2_500, responseBytes: 400)
        metrics.record(route: "/session/s/actions", method: "POST", status: 404, milliseconds: 1_000, responseBytes: 600)
        metrics.record(route: "/session/s/screenshot", method: "GET", status: 200, milliseconds: 1_000, responseBytes: 900_000)
        let result = metrics.metrics(now: start.addingTimeInterval(160))
        XCTAssertEqual(result.totalSeconds, 160)
        XCTAssertEqual(result.preparationSeconds, 40)
        XCTAssertEqual(result.deviceSeconds, 6)
        XCTAssertEqual(result.agentSeconds, 114, "el resto es el agente pensando")
        XCTAssertEqual(result.requests, 4)
        XCTAssertEqual(result.observations, 1)
        XCTAssertEqual(result.actions, 2)
        XCTAssertEqual(result.failures, 1)
        XCTAssertEqual(result.screenshots, 1)
        XCTAssertEqual(result.bytesToAgent, 9_000, "una captura no cuenta como texto")
        XCTAssertEqual(result.estimatedTokens, 9_000 / 4 + RunMetrics.tokensPerScreenshot)
    }

    func testFormatsDurationsAndTokens() {
        XCTAssertEqual(RunMetrics.duration(48), "48 s")
        XCTAssertEqual(RunMetrics.duration(724), "12 min 4 s")
        XCTAssertEqual(RunMetrics.duration(120), "2 min")
        XCTAssertEqual(RunMetrics.tokens(800), "~800 tokens")
        XCTAssertEqual(RunMetrics.tokens(45_400), "~45 k tokens")
    }

    func testEngineMeasuresASessionAndLastRunKeepsIt() throws {
        let engine = ScoutEngine(artifactStore: ArtifactStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("metrics-\(UUID().uuidString)")))
        let session = try engine.createSession(deviceID: nil, bundleIdentifier: "com.example.test")
        engine.recordAgentRequest(sessionID: session.id, route: "/session/\(session.id)/observe", method: "GET", status: 200, milliseconds: 100, responseBytes: 4_000)
        engine.recordAgentRequest(sessionID: "otra", route: "/session/otra/observe", method: "GET", status: 200, milliseconds: 100, responseBytes: 4_000)
        let metrics = try engine.runMetrics(sessionID: session.id)
        XCTAssertEqual(metrics.requests, 1)
        XCTAssertEqual(metrics.estimatedTokens, 1_000)

        let json = #"{"scenario":"login","status":"recorded","metrics":{"totalSeconds":95,"preparationSeconds":30,"deviceSeconds":20,"agentSeconds":45,"requests":12,"observations":6,"actions":5,"failures":1,"screenshots":0,"bytesToAgent":20000,"estimatedTokens":5000}}"#
        let report = try JSONDecoder().decode(LastRunReport.self, from: Data(json.utf8))
        XCTAssertEqual(report.metrics?.summary, "1 min 35 s · 12 comandos · ~5 k tokens")
        let legacy = try JSONDecoder().decode(LastRunReport.self, from: Data(#"{"scenario":"login","status":"failed"}"#.utf8))
        XCTAssertNil(legacy.metrics)
    }

    func testCloseSessionSavesTheMetrics() throws {
        let options = ProjectScaffolder.Options(appName: "Demo", appPath: "/tmp/Demo.app", cuyscoutRepoPath: "")
        let script = try XCTUnwrap(ProjectScaffolder.files(for: options)["scripts/close-session.sh"])
        XCTAssertTrue(script.contains(#"/session/${SESSION}/metrics/run"#))
        XCTAssertTrue(script.contains(#"report["metrics"] = metrics"#))
    }
}

final class LastRunToleratesBadMetricsTests: XCTestCase {
    func testMalformedMetricsDoNotLoseTheRunResult() throws {
        let report = try JSONDecoder().decode(LastRunReport.self, from: Data(#"{"scenario":"x","status":"failed","metrics":{"value":{}}}"#.utf8))
        XCTAssertEqual(report.status, .failed)
        XCTAssertNil(report.metrics)
    }
}
