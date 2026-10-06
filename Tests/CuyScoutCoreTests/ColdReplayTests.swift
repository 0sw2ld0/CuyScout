import XCTest
@testable import CuyScoutCore

final class ColdReplayTests: XCTestCase {
    func testAutomaticDestinationPrefersMatchingBootedSimulator() {
        let recorded = Device(id: "old", name: "iPhone 17 Pro", runtime: "iOS-26", state: "Shutdown")
        let other = Device(id: "other", name: "iPhone 16", runtime: "iOS-26", state: "Booted")
        let match = Device(id: "new", name: "iPhone 17 Pro", runtime: "iOS-26", state: "Booted")
        XCTAssertEqual(ScoutEngine.preferredReplayDevice(from: [other, match], recorded: recorded)?.id, "new")
        XCTAssertEqual(ScoutEngine.preferredReplayDevice(from: [other, recorded], recorded: recorded)?.id, "old")
    }

    private func fixture() throws -> (ScoutEngine, ArtifactStore, String, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cold-replay-\(UUID().uuidString)")
        let store = ArtifactStore(directory: root)
        let engine = ScoutEngine(artifactStore: store)
        let session = try engine.createSession(deviceID: nil, bundleIdentifier: "com.example.test")
        try engine.startRecording(sessionID: session.id)
        // Record a bridge action even though the original runner is absent.
        XCTAssertThrowsError(try engine.perform(.assertVisible(.init(strategy: .accessibilityIdentifier, value: "ready")), sessionID: session.id))
        try engine.deleteSession(session.id)
        // Sin runner el paso quedó como fallido; el replay salta los intentos fallidos, así que
        // se marca como exitoso, como en una grabación real que sí funcionó.
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: store.load(sessionID: session.id)) as? [String: Any])
        var recording = try XCTUnwrap(json["recording"] as? [String: Any])
        recording["steps"] = (recording["steps"] as? [[String: Any]] ?? []).map { step in var copy = step; copy["success"] = true; copy["error"] = nil; return copy }
        json["recording"] = recording
        try store.save(JSONDecoder().decode(SessionArtifactBundle.self, from: JSONSerialization.data(withJSONObject: json)))
        return (engine, store, session.id, root)
    }

    func testColdReplayRestoresBridgeExecutesAndCanRunAgain() throws {
        let (engine, store, id, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = try store.load(sessionID: id)
        for resilient in [false, true] {
            let worker = expectation(description: "bridge consumes assertion")
            let result = try engine.replayPersistedArtifact(sessionID: id, resilient: resilient, resetApp: false) { session in
                try engine.registerBridge(sessionID: session.id)
                _ = try engine.pollBridge(sessionID: session.id)
                DispatchQueue.global().async {
                    defer { worker.fulfill() }
                    let deadline = Date().addingTimeInterval(5)
                    var consumedAssertion = false
                    while Date() < deadline {
                        do {
                            if let command = try engine.pollBridge(sessionID: session.id) {
                                if !consumedAssertion {
                                    XCTAssertEqual(command.action, .assertVisible(.init(strategy: .accessibilityIdentifier, value: "ready")))
                                    consumedAssertion = true
                                }
                                try engine.completeBridge(sessionID: session.id, result: BridgeResult(commandID: command.id, success: true, payloadBase64: Data("{\"elements\":[]}".utf8).base64EncodedString()))
                            }
                        } catch {
                            XCTAssertTrue(consumedAssertion)
                            return
                        }
                        Thread.sleep(forTimeInterval: 0.01)
                    }
                    XCTFail("Replay did not release its session")
                }
            }
            wait(for: [worker], timeout: 6)
            XCTAssertTrue(result.success)
            XCTAssertEqual(result.executedSteps, 1)
            XCTAssertEqual(engine.replayProgress(artifactID: id), ReplayProgress(stage: "ejecutando", current: 1, total: 1, step: "esperar accessibilityIdentifier=«ready»"))
            XCTAssertThrowsError(try engine.session(id))
            XCTAssertTrue(engine.schedulerLeases().isEmpty)
            XCTAssertEqual(try store.load(sessionID: id), original)
        }
    }

    func testReplayDeclinesPasswordPromptAndRetriesAssertionWithoutChangingArtifact() throws {
        let (engine, store, id, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = try store.load(sessionID: id)
        let worker = expectation(description: "bridge handles known interruption")
        let result = try engine.replayPersistedArtifact(sessionID: id, resetApp: false) { session in
            try engine.registerBridge(sessionID: session.id)
            _ = try engine.pollBridge(sessionID: session.id)
            DispatchQueue.global().async {
                defer { worker.fulfill() }
                let expected: [String] = ["assertVisible", "accessibilityTreeWithOptions", "tapElement", "assertVisible"]
                let alert = Data("{\"activeAlert\":{\"text\":\"Save password?\",\"buttons\":[\"Save\",\"Not Now\"]}}".utf8)
                var index = 0
                let deadline = Date().addingTimeInterval(5)
                while Date() < deadline && index < expected.count {
                    if let command = try? engine.pollBridge(sessionID: session.id) {
                        let encoded = (try? JSONEncoder().encode(command.action)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                        XCTAssertEqual(encoded?["type"] as? String, expected[index])
                        if index == 2 { XCTAssertEqual(encoded?["selector"] as? [String: String], ["strategy": "label", "value": "Not Now"]) }
                        let response = BridgeResult(commandID: command.id, success: index != 0, payloadBase64: index == 1 ? alert.base64EncodedString() : nil, error: index == 0 ? "blocked by prompt" : nil)
                        try? engine.completeBridge(sessionID: session.id, result: response)
                        index += 1
                    } else { Thread.sleep(forTimeInterval: 0.01) }
                }
                XCTAssertEqual(index, expected.count)
            }
        }
        wait(for: [worker], timeout: 6)
        XCTAssertTrue(result.success)
        XCTAssertEqual(result.dismissedInterruptions, 1)
        XCTAssertEqual(try store.load(sessionID: id), original)
    }

    func testReplayCanUseDifferentSimulatorWithoutRewritingArtifact() throws {
        let (engine, store, id, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = try store.load(sessionID: id)
        let saved = try JSONDecoder().decode(SessionArtifactBundle.self, from: original)
        guard let target = try engine.listDevices().first(where: { $0.id != saved.session.device.id && $0.isAvailable }) else {
            throw XCTSkip("This host has only one simulator")
        }
        let worker = expectation(description: "target simulator bridge")
        let result = try engine.replayPersistedArtifact(sessionID: id, resetApp: false, targetDeviceID: target.id) { session in
            XCTAssertEqual(session.device.id, target.id)
            try engine.registerBridge(sessionID: session.id)
            _ = try engine.pollBridge(sessionID: session.id)
            DispatchQueue.global().async {
                defer { worker.fulfill() }
                let deadline = Date().addingTimeInterval(5)
                while Date() < deadline {
                    if let command = try? engine.pollBridge(sessionID: session.id) {
                        try? engine.completeBridge(sessionID: session.id, result: BridgeResult(commandID: command.id, success: true))
                        return
                    }
                    Thread.sleep(forTimeInterval: 0.01)
                }
                XCTFail("No replay command received")
            }
        }
        wait(for: [worker], timeout: 6)
        XCTAssertTrue(result.success)
        XCTAssertEqual(try store.load(sessionID: id), original)
        XCTAssertTrue(engine.schedulerLeases().isEmpty)
    }

    func testReplayPreflightReportsMissingInstallerAndVariables() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cold-preflight-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let engine = ScoutEngine(artifactStore: ArtifactStore(directory: root))
        let session = try engine.createSession(deviceID: nil, bundleIdentifier: "com.example.test")
        try engine.startRecording(sessionID: session.id)
        XCTAssertThrowsError(try engine.perform(.typeElement(.init(strategy: .accessibilityIdentifier, value: "password"), text: "<redacted>"), sessionID: session.id))
        try engine.deleteSession(session.id)
        let report = try engine.preflightReplay(sessionID: session.id, preparation: .reinstall)
        XCTAssertTrue(report.errors.contains { $0.contains("termina en un paso fallido") }, "una grabación que acaba en error no se reproduce")
        XCTAssertFalse(report.ready)
        XCTAssertTrue(report.errors.contains { $0.contains("appPath") })
        // El único paso falló al grabar: no se repite, así que no exige su valor.
        XCTAssertFalse(report.errors.contains { $0.contains("0.text") })
        XCTAssertEqual(report.recordedDeviceID, session.device.id)
    }

    func testPreparationFailureReleasesDeviceAndPreservesArtifact() throws {
        let (engine, store, id, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = try store.load(sessionID: id)
        XCTAssertThrowsError(try engine.replayPersistedArtifact(sessionID: id, prepare: { _ in
            throw ScoutError.invalidRequest("runner unavailable")
        }))
        XCTAssertTrue(engine.schedulerLeases().isEmpty)
        XCTAssertThrowsError(try engine.session(id))
        XCTAssertEqual(try store.load(sessionID: id), original)
        // Metadata-only restore retains its existing behavior.
        _ = try engine.restorePersistedArtifact(sessionID: id)
        XCTAssertFalse(try engine.bridgeStatus(sessionID: id).registered)
        XCTAssertThrowsError(try engine.replayPersistedArtifact(sessionID: id, prepare: { _ in XCTFail("Must reject a live session") }))
        XCTAssertNoThrow(try engine.session(id))
        try engine.deleteSession(id)
    }

    func testReplayFailureReportsStepAndReleasesSession() throws {
        let (engine, store, id, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = try store.load(sessionID: id)
        let result = try engine.replayPersistedArtifact(sessionID: id, resetApp: false, prepare: { _ in })
        XCTAssertFalse(result.success)
        XCTAssertEqual(result.failedStep, 1)
        XCTAssertEqual(result.executedSteps, 0)
        XCTAssertTrue(engine.schedulerLeases().isEmpty)
        XCTAssertEqual(try store.load(sessionID: id), original)
    }

    func testEmptyArtifactIsRejectedBeforePreparation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cold-empty-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let engine = ScoutEngine(artifactStore: ArtifactStore(directory: root))
        let session = try engine.createSession(deviceID: nil, bundleIdentifier: nil)
        try engine.startRecording(sessionID: session.id)
        try engine.deleteSession(session.id)
        XCTAssertThrowsError(try engine.replayPersistedArtifact(sessionID: session.id, prepare: { _ in XCTFail("Empty recording must not launch a runner") }))
        XCTAssertTrue(engine.schedulerLeases().isEmpty)
    }

    func testCompleteArtifactCanBeImportedIntoAnotherGatewayStore() throws {
        let (source, sourceStore, id, sourceRoot) = try fixture()
        defer { try? FileManager.default.removeItem(at: sourceRoot) }
        let package = try sourceStore.load(sessionID: id)
        let targetRoot = FileManager.default.temporaryDirectory.appendingPathComponent("cold-import-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: targetRoot) }
        let target = ScoutEngine(artifactStore: ArtifactStore(directory: targetRoot))
        let descriptor = try target.importPersistedArtifact(package)
        XCTAssertEqual(descriptor.sessionID, id)
        XCTAssertEqual(descriptor.recordedStepCount, 1)
        XCTAssertEqual(target.persistedArtifacts(), [id])
        XCTAssertThrowsError(try target.importPersistedArtifact(package))
        XCTAssertNoThrow(try target.importPersistedArtifact(package, overwrite: true))
    }
}

final class ReplayWaitsForElementsTests: XCTestCase {
    override func tearDown() { ScoutEngine.replayElementWait = 1; super.tearDown() }

    func testAReplayStepWaitsUntilASlowScreenShowsItsElement() throws {
        ScoutEngine.replayElementWait = 5
        let engine = ScoutEngine(artifactStore: ArtifactStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("wait-\(UUID().uuidString)")))
        let session = try engine.createSession(deviceID: nil, bundleIdentifier: "com.example.test")
        try engine.registerBridge(sessionID: session.id)
        _ = try engine.pollBridge(sessionID: session.id)
        var attempts = 0
        let worker = expectation(description: "runner")
        DispatchQueue.global().async {
            let deadline = Date().addingTimeInterval(6)
            while Date() < deadline {
                if let command = try? engine.pollBridge(sessionID: session.id) {
                    attempts += 1
                    // La pantalla siguiente tarda: las dos primeras búsquedas no encuentran el campo.
                    let found = attempts >= 3
                    try? engine.completeBridge(sessionID: session.id, result: BridgeResult(commandID: command.id, success: found, payloadBase64: nil, error: found ? nil : "El elemento no existe para escribir", errorCode: found ? nil : 8))
                    if found { worker.fulfill(); return }
                }
                Thread.sleep(forTimeInterval: 0.01)
            }
        }
        _ = try engine.performWaitingForElement(.typeElement(.init(strategy: .accessibilityIdentifier, value: "password"), text: "x"), sessionID: session.id, resilient: false)
        wait(for: [worker], timeout: 7)
        XCTAssertEqual(attempts, 3)
    }

    func testTheMessageSaysWhenTheScreenCouldNotBeRead() {
        let message = ScoutEngine.replayFailureMessage(step: 5, action: .tapElement(.init(strategy: .label, value: "Ingresar")), selector: .init(strategy: .label, value: "Ingresar"), screenTexts: [], similar: [], screenRead: false, waited: 15)
        XCTAssertTrue(message.contains("tras esperar 15 s"))
        XCTAssertTrue(message.contains("No se pudo leer la pantalla"))
        XCTAssertFalse(message.contains("no mostraba textos"))
    }
}

final class HiddenElementMessageTests: XCTestCase {
    func testPointsAtThePreviousStepWhenTheFieldStaysHidden() {
        let message = ScoutEngine.hiddenElementMessage(step: 5, selector: .init(strategy: .label, value: "Clave, cuadro de texto"), waited: 15,
                                                       previous: ("step-4", .tap(x: 201, y: 800)))
        XCTAssertTrue(message.contains("existe en la app pero siguió oculto tras esperar 15 s"))
        XCTAssertTrue(message.contains("step-4"))
        XCTAssertTrue(message.contains("toque por coordenadas (201, 800)"))
        XCTAssertTrue(message.contains("/ejecutar-escenario"))
    }
}

final class ReplayDiagnosticsTests: XCTestCase {
    func testDescribesStepsWithoutWhatWasTyped() {
        XCTAssertEqual(ReplayDiagnostics.describe(.tap(x: 201, y: 800)), "toque en (201, 800)")
        let typed = ReplayDiagnostics.describe(.typeElement(.init(strategy: .label, value: "Clave"), text: "secreto123"))
        XCTAssertEqual(typed, "escribir en label=«Clave»")
        XCTAssertFalse(typed.contains("secreto123"))
    }

    func testScreenSummaryListsControlsAndHidesSecureValues() throws {
        let tree = try JSONSerialization.data(withJSONObject: ["elements": [
            ["type": "button", "label": "Ingresar con clave", "identifier": "", "frame": ["x": 16, "y": 776, "width": 370, "height": 48]],
            ["type": "secureTextField", "label": "Clave", "identifier": "pwd", "value": "••••", "frame": ["x": 16, "y": 400, "width": 370, "height": 48]]
        ]])
        let summary = ReplayDiagnostics.screenSummary(tree)
        XCTAssertTrue(summary.contains("button «Ingresar con clave» (16,776 370×48)"))
        XCTAssertTrue(summary.contains("secureTextField id=pwd «Clave»"))
        XCTAssertFalse(summary.contains("valor="), "el valor de un campo seguro no se guarda")
    }

    func testElementsUnderAPointGoFromSmallestToLargest() {
        let elements: [[String: Any]] = [
            ["type": "cell", "label": "Fila", "frame": ["x": 0, "y": 700, "width": 402, "height": 200]],
            ["type": "button", "label": "Ingresar", "frame": ["x": 16, "y": 776, "width": 370, "height": 48]],
            ["type": "staticText", "label": "Texto", "frame": ["x": 16, "y": 776, "width": 370, "height": 48]]
        ]
        let under = ScoutEngine.elementsUnder(point: CGPoint(x: 201, y: 800), in: elements, isInteractive: { ["button", "cell"].contains($0) })
        XCTAssertEqual(under.count, 2)
        XCTAssertTrue(under[0].hasPrefix("button 'Ingresar'"))
    }
}
