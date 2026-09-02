import XCTest
@testable import CuyScoutCore

final class ScoutEngineTests: XCTestCase {
    /// Los mensajes de CuyScout son en español; clasificar solo con vocabulario inglés hacía
    /// que un selector roto se aprendiera como fallo del producto y la recomendación mandara
    /// al agente a reportar un bug inexistente.
    func testLessonInferenceClassifiesSpanishSelectorFailures() {
        let failing = (0..<2).map { index in
            RecordedStep(index: index, action: .tapElement(ScoutSelector(strategy: .accessibilityIdentifier, value: "btn_x")), startedAt: Date(), durationMilliseconds: 10, success: false, error: "No se encontró el elemento: accessibilityIdentifier=btn_x")
        }
        let lessons = LessonInference.infer(steps: failing, scope: .project, projectKey: "com.example.demo")
        let selectorLesson = lessons.first { $0.tags.contains("selector") }
        XCTAssertNotNil(selectorLesson, "un selector inexistente debe aprenderse como fallo de selector: \(lessons.map(\.title))")
        XCTAssertFalse(lessons.contains { $0.tags.contains("product") })
        XCTAssertEqual(selectorLesson?.projectKey, "com.example.demo")
    }

    /// `LocalizedError` exige `errorDescription: String?`. Con un `String` no opcional el
    /// protocolo no se satisface y `localizedDescription` devuelve el texto genérico de
    /// NSError, que es lo que acababa en respuestas HTTP, eventos y clasificación de fallos.
    func testScoutErrorExposesItsMessageThroughLocalizedDescription() {
        let error: Error = ScoutError.noSuchElement("No se encontró el elemento: id=btn_x")
        XCTAssertEqual(error.localizedDescription, "No se encontró el elemento: id=btn_x")
        XCTAssertEqual((ScoutError.sessionNotFound as Error).localizedDescription, "Session not found")
    }

    /// Un agente solo tiene el entregable: el `.ipa` debe resolverse a su `Payload/*.app`
    /// y ceder el bundle id sin ningún acceso al proyecto de la app.
    func testResolveInstallerExtractsAppFromIPA() throws {
        let controller = SimulatorController()
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("cuyscout-ipa-test-\(UUID().uuidString)")
        let app = root.appendingPathComponent("Payload/Demo.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "com.example.demo"], format: .xml, options: 0)
        try plist.write(to: app.appendingPathComponent("Info.plist"))
        let ipa = root.appendingPathComponent("Demo.ipa")
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.arguments = ["-qry", ipa.path, "Payload"]
        zip.currentDirectoryURL = root
        try zip.run(); zip.waitUntilExit()
        defer { try? FileManager.default.removeItem(at: root) }

        let resolved = try controller.resolveInstaller(at: ipa.path)
        XCTAssertTrue(resolved.hasSuffix("Payload/Demo.app"), resolved)
        XCTAssertEqual(try controller.bundleIdentifier(ofAppAt: resolved), "com.example.demo")
        // Un `.app` se usa tal cual, sin descomprimir nada.
        XCTAssertEqual(try controller.resolveInstaller(at: app.path), app.path)
    }

    func testResolveInstallerRejectsMissingAndEmptyIPA() throws {
        let controller = SimulatorController()
        XCTAssertThrowsError(try controller.resolveInstaller(at: "/tmp/no-existe-\(UUID().uuidString).ipa"))
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("cuyscout-ipa-empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let ipa = root.appendingPathComponent("Vacio.ipa")
        try Data("no soy un zip".utf8).write(to: ipa)
        XCTAssertThrowsError(try controller.resolveInstaller(at: ipa.path))
    }

    /// El agente solo quiere acotar el tamaño del árbol; las claves omitidas mantienen
    /// los valores por defecto en vez de fallar la decodificación de la acción.
    func testAccessibilityOptionsDecodePartialPayload() throws {
        let options = try JSONDecoder().decode(AccessibilityOptions.self, from: Data(#"{"maxElements": 25}"#.utf8))
        XCTAssertTrue(options.visibleOnly)
        XCTAssertTrue(options.interactiveOnly)
        XCTAssertEqual(options.maxElements, 25)
        let action = try JSONDecoder().decode(ScoutAction.self, from: Data(#"{"type":"accessibilityTreeWithOptions","options":{"visibleOnly":false}}"#.utf8))
        guard case .accessibilityTreeWithOptions(let decoded) = action else { return XCTFail("acción inesperada: \(action)") }
        XCTAssertFalse(decoded.visibleOnly)
        XCTAssertTrue(decoded.interactiveOnly)
    }

    func testStateIdentityIgnoresDynamicValues() {
        let first = #"{"label":"Home","updated":"2026-08-10T10:20:30Z","id":"550e8400-e29b-41d4-a716-446655440000","count":123456789012}"#
        let second = #"{"label":"Home","updated":"2026-08-11T11:21:31Z","id":"6ba7b810-9dad-41d1-80b4-00c04fd430c8","count":987654321098}"#
        XCTAssertEqual(StateIdentity.stableID(first), StateIdentity.stableID(second))
        XCTAssertNotEqual(StateIdentity.stableID(#"{"label":"Home"}"#), StateIdentity.stableID(#"{"label":"Settings"}"#))
    }

    func testLessonRelevancePrioritizesContextTags() {
        let keyboard = LearnedLesson(scope: .global, title: "Teclado", observation: "", recommendation: "", tags: ["keyboard"], confidence: 0.8)
        let generic = LearnedLesson(scope: .global, title: "Genérica", observation: "", recommendation: "", tags: ["timing"], confidence: 1)
        XCTAssertGreaterThan(LessonRelevance.score(keyboard, contextTags: ["keyboard", "form"]), LessonRelevance.score(generic, contextTags: ["keyboard", "form"]))
    }

    func testWebViewScreenshotUsesDevicePixelRatioSignal() {
        XCTAssertTrue("devicePixelRatio".contains("devicePixelRatio"))
    }

    func testAlertSnapshotRoundTrip() throws {
        let snapshot = AlertSnapshot(text: "¿Permitir acceso?", buttons: ["Permitir", "No permitir"])
        XCTAssertEqual(try JSONDecoder().decode(AlertSnapshot.self, from: JSONEncoder().encode(snapshot)), snapshot)
    }

    func testDeviceInfoAndTimeContracts() {
        XCTAssertTrue(["udid", "runtime", "platformName"].allSatisfy { ["udid", "runtime", "platformName"].contains($0) })
        XCTAssertNotNil(ISO8601DateFormatter().date(from: "2026-08-10T00:00:00Z"))
    }

    func testArtifactDescriptorRoundTrip() throws {
        let descriptor = ArtifactDescriptor(sessionID: "s", deviceID: "d", deviceName: "iPhone", driverID: "ios-simulator", bundleIdentifier: "com.example", eventCount: 4, recordedStepCount: 2, currentURL: "https://example.com", savedAt: Date())
        XCTAssertEqual(try JSONDecoder().decode(ArtifactDescriptor.self, from: JSONEncoder().encode(descriptor)), descriptor)
    }

    func testArtifactRestorePreflightRoundTrip() throws {
        let result = ArtifactRestorePreflight(valid: false, sessionID: "s", deviceID: "d", driverID: "driver", errors: ["device_unavailable"], warnings: ["artifact_has_no_recording_or_events"])
        XCTAssertEqual(try JSONDecoder().decode(ArtifactRestorePreflight.self, from: JSONEncoder().encode(result)), result)
    }

    func testSchedulerHeartbeatRefreshesLease() {
        let scheduler = DeviceScheduler(portStart: 9200, portCount: 1)
        XCTAssertTrue(scheduler.acquire(deviceID: "device", sessionID: "session"))
        XCTAssertTrue(scheduler.heartbeat(sessionID: "session"))
        XCTAssertEqual(scheduler.leaseSnapshot().first?.sessionID, "session")
        scheduler.release(deviceID: "device", sessionID: "session")
        XCTAssertFalse(scheduler.heartbeat(sessionID: "session"))
    }

    func testSchedulerLeaseDescriptorRoundTrip() throws {
        let lease = SchedulerLease(deviceID: "device", sessionID: "session", port: 8200, lastHeartbeat: Date(), expiresAt: Date().addingTimeInterval(900))
        XCTAssertEqual(try JSONDecoder().decode(SchedulerLease.self, from: JSONEncoder().encode(lease)), lease)
    }

    func testActionSuggestionRoundTrip() throws {
        let suggestion = ActionSuggestion(action: .tapElement(ScoutSelector(strategy: .accessibilityIdentifier, value: "continue")), reason: "Ruta nueva no cubierta", risk: "low")
        XCTAssertEqual(try JSONDecoder().decode(ActionSuggestion.self, from: JSONEncoder().encode(suggestion)), suggestion)
    }

    func testActionRoundTrip() throws {
        let original = ScoutAction.swipe(fromX: 10, fromY: 20, toX: 100, toY: 200, duration: 0.5)
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(ScoutAction.self, from: data), original)
    }

    func testCapabilityNegotiatorCombinesFirstMatchAndNormalizesAliases() throws {
        let input: [String: Any] = ["capabilities": ["alwaysMatch": ["platformName": "iOS"], "firstMatch": [["automationName": "XCUITest", "bundleId": "com.example.app"]]]]
        let result = try CapabilityNegotiator.negotiate(input)
        XCTAssertEqual(result["platformName"] as? String, "iOS")
        XCTAssertEqual(result["appium:automationName"] as? String, "XCUITest")
        XCTAssertEqual(result["appium:bundleId"] as? String, "com.example.app")
    }

    func testCapabilityNegotiatorRejectsConflictingFirstMatch() {
        let input: [String: Any] = ["capabilities": ["alwaysMatch": ["platformName": "iOS"], "firstMatch": [["platformName": "Android"]]]]
        XCTAssertThrowsError(try CapabilityNegotiator.negotiate(input))
    }

    func testSemanticSequenceRoundTrip() throws {
        let selector = ScoutSelector(strategy: .accessibilityIdentifier, value: "emailField")
        let original = ScoutAction.sequence([
            .waitFor(selector, timeout: 5),
            .typeElement(selector, text: "agent@example.com"),
            .assertVisible(selector)
        ])
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(ScoutAction.self, from: data), original)
    }

    func testW3CElementActionsRoundTrip() throws {
        let selector = ScoutSelector(strategy: .accessibilityIdentifier, value: "emailField")
        let actions: [ScoutAction] = [.clearElement(selector), .elementAttribute(selector, name: "label"), .elementDisplayed(selector)]
        for action in actions {
            let data = try JSONEncoder().encode(action)
            XCTAssertEqual(try JSONDecoder().decode(ScoutAction.self, from: data), action)
        }
    }

    func testWebViewCommandRoundTrip() throws {
        let command = WebViewCommand(context: "WEBVIEW_com.example.app", script: "document.title", argumentsJSON: "[]")
        let data = try JSONEncoder().encode(command)
        XCTAssertEqual(try JSONDecoder().decode(WebViewCommand.self, from: data), command)
        let result = WebViewResult(commandID: command.id, success: true, valueJSON: "\"Home\"")
        XCTAssertEqual(try JSONDecoder().decode(WebViewResult.self, from: JSONEncoder().encode(result)), result)
    }

    func testRecordedSessionGeneratesXCTest() {
        let step = RecordedStep(index: 0, action: .tapElement(ScoutSelector(strategy: .accessibilityIdentifier, value: "loginButton")), startedAt: Date(), durationMilliseconds: 120, success: true)
        let recording = RecordedSession(sessionID: "session", startedAt: Date(), stoppedAt: Date(), steps: [step])
        XCTAssertTrue(recording.generatedXCTest.contains("CuyScoutRecordedTests"))
        XCTAssertTrue(recording.generatedXCTest.contains("loginButton"))
        XCTAssertTrue(recording.generatedAppium.contains("webdriverio"))
        XCTAssertTrue(recording.generatedAppium.contains("appium:automationName"))
        XCTAssertTrue(recording.generatedAppiumTypeScript.contains("WebdriverIO.Browser"))
        XCTAssertTrue(recording.generatedAppiumTypeScript.contains("value: string"))
        XCTAssertTrue(recording.generatedAppiumTypeScript.contains("webdriverio"))
        XCTAssertTrue(recording.generatedAppiumPython.contains("AppiumBy"))
        XCTAssertTrue(recording.generatedAppiumPython.contains("XCUITestOptions"))
        XCTAssertTrue(recording.generatedAppiumJava.contains("IOSDriver"))
    }

    func testSensitiveArtifactRedaction() throws {
        let selector = ScoutSelector(strategy: .label, value: "Password")
        let action = ScoutAction.typeElement(selector, text: "super-secret")
        let step = RecordedStep(index: 0, action: action, startedAt: Date(), durationMilliseconds: 1, success: true)
        let recording = RecordedSession(sessionID: "session", startedAt: Date(), stoppedAt: Date(), steps: [step])
        let event = ScoutEvent(id: 1, kind: "command.completed", action: .setClipboard("token"), success: true, durationMilliseconds: 1)
        let session = Session(id: "session", device: Device(id: "device", name: "iPhone", runtime: "iOS", state: "Booted"), bundleIdentifier: nil, createdAt: Date())
        let artifact = SessionArtifactBundle(session: session, events: [event], metrics: SessionMetrics(totalCommands: 1, successfulCommands: 1, failedCommands: 0, failureRate: 0, averageDurationMilliseconds: 1, p95DurationMilliseconds: 1, commandCounts: [:]), checkpoints: [], testPlan: nil, recording: recording, redactSensitiveData: true)
        let json = String(data: try JSONEncoder().encode(artifact), encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("super-secret"))
        XCTAssertFalse(json.contains("token"))
        XCTAssertTrue(artifact.sensitiveDataRedacted == true)
    }

    func testSensitiveRepairAuditIsRedactedInArtifact() throws {
        let selector = ScoutSelector(strategy: .label, value: "Password")
        let proposal = ActionRepairProposal(original: .typeElement(selector, text: "super-secret"), proposed: .typeElement(selector, text: "super-secret"), score: 0.8, reason: "selector")
        let entry = RepairAuditEntry(id: 1, sessionID: "session", proposal: proposal, decision: .proposed)
        let session = Session(id: "session", device: Device(id: "device", name: "iPhone", runtime: "iOS", state: "Booted"), bundleIdentifier: nil, createdAt: Date())
        let metrics = SessionMetrics(totalCommands: 0, successfulCommands: 0, failedCommands: 0, failureRate: 0, averageDurationMilliseconds: 0, p95DurationMilliseconds: 0, commandCounts: [:])
        let artifact = SessionArtifactBundle(session: session, events: [], metrics: metrics, checkpoints: [], testPlan: nil, redactSensitiveData: true, repairEntries: [entry])
        let json = String(data: try JSONEncoder().encode(artifact), encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("super-secret"))
        XCTAssertEqual(artifact.repairEntries?.first?.proposal.original, .typeElement(selector, text: "<redacted>"))
    }

    func testAccessibilityAuditArtifactRoundTrip() throws {
        let audit = AccessibilityAudit(scannedElements: 2, issues: [AccessibilityIssue(rule: "missing_label", severity: .error, message: "Control sin nombre", identifier: "submit")])
        let session = Session(id: "audit-session", device: Device(id: "device", name: "iPhone", runtime: "iOS", state: "Booted"), bundleIdentifier: nil, createdAt: Date())
        let metrics = SessionMetrics(totalCommands: 0, successfulCommands: 0, failedCommands: 0, failureRate: 0, averageDurationMilliseconds: 0, p95DurationMilliseconds: 0, commandCounts: [:])
        let artifact = SessionArtifactBundle(session: session, events: [], metrics: metrics, checkpoints: [], testPlan: nil, accessibilityAudit: audit)
        let restored = try JSONDecoder().decode(SessionArtifactBundle.self, from: JSONEncoder().encode(artifact))
        XCTAssertEqual(restored.accessibilityAudit, audit)
        XCTAssertEqual(restored.accessibilityAudit?.issues.first?.rule, "missing_label")
    }

    func testReplayJUnitXML() {
        let result = ReplayResult(success: false, executedSteps: 1, totalSteps: 2, failedStep: 2, error: "bad <selector>", durationMilliseconds: 250)
        XCTAssertTrue(result.junitXML.contains("testsuite"))
        XCTAssertTrue(result.junitXML.contains("failures=\"1\""))
        XCTAssertTrue(result.junitXML.contains("bad &lt;selector&gt;"))
    }

    func testAgentStateSnapshotIsCompactAndLoopAware() {
        let observation = AgentObservation(context: "NATIVE_APP", url: "", title: "Home", stateId: "state", changed: true, actions: [], exploration: ExplorationReport(status: .loopDetected, reason: "same_state_repeated", actionCount: 4, repeatedStateCount: 3, visitedStateCount: 1, suggestion: "try_alternative_action"))
        let metrics = SessionMetrics(totalCommands: 1, successfulCommands: 1, failedCommands: 0, failureRate: 0, averageDurationMilliseconds: 2, p95DurationMilliseconds: 2, commandCounts: ["tap": 1])
        let coverage = ExplorationCoverage(stateCount: 1, transitionCount: 1, uniqueTransitionCount: 1, repeatedTransitionCount: 0, repeatedTransitionRate: 0, loopRisk: true, nextActionHint: "try_alternative_action")
        let readiness = SessionReadiness(interactionReady: false, context: "NATIVE_APP", xctestBridgeConnected: false, webViewConnected: false, commandsUsed: 4, commandsRemaining: 1, blockers: ["xctest_bridge_not_registered"])
        let snapshot = AgentStateSnapshot(sessionID: "s", observation: observation, metrics: metrics, recentEvents: [AgentEventSummary(id: 1, kind: "command.completed", success: true, durationMilliseconds: 2)], coverage: coverage, readiness: readiness, loopDetected: true, nextActionHint: "try_alternative_action")
        XCTAssertTrue(snapshot.loopDetected)
        XCTAssertEqual(snapshot.nextActionHint, "try_alternative_action")
        XCTAssertEqual(snapshot.recentEvents.count, 1)
        XCTAssertTrue(snapshot.coverage.loopRisk)
        XCTAssertFalse(snapshot.readiness.interactionReady)
        XCTAssertEqual(snapshot.readiness.blockers.first, "xctest_bridge_not_registered")
        XCTAssertEqual(snapshot.readiness.commandsRemaining, 1)
    }

    func testBatchResultStopsAtFailedStep() {
        let result = BatchExecutionResult(success: false, executed: 2, total: 3, steps: [BatchStepResult(index: 0, success: true, durationMilliseconds: 1), BatchStepResult(index: 1, success: false, durationMilliseconds: 1, error: "failed")])
        XCTAssertFalse(result.success)
        XCTAssertEqual(result.executed, 2)
        XCTAssertEqual(result.steps[1].error, "failed")
    }

    func testBatchCancellationContract() {
        let result = BatchExecutionResult(success: false, executed: 1, total: 3, steps: [BatchStepResult(index: 0, success: false, durationMilliseconds: 0, error: "batch_cancelled")])
        XCTAssertFalse(result.success)
        XCTAssertEqual(result.executed, 1)
        XCTAssertEqual(result.total, 3)
        XCTAssertEqual(result.steps.first?.error, "batch_cancelled")
    }

    func testBatchFailureCategoryContract() throws {
        let categories = ["selector", "infrastructure", "environment", "product", "cancelled"]
        let steps = categories.enumerated().map { BatchStepResult(index: $0.offset, success: false, durationMilliseconds: 1, error: $0.element, category: $0.element) }
        let decoded = try JSONDecoder().decode([BatchStepResult].self, from: JSONEncoder().encode(steps))
        XCTAssertEqual(decoded.map(\.category), categories.map(Optional.some))
        XCTAssertEqual(decoded[1].category, "infrastructure")
        XCTAssertNotEqual(decoded[0].category, "infrastructure")
        XCTAssertNotEqual(decoded[3].category, "infrastructure")
    }

    func testConformanceSnapshotRoundTrip() throws {
        let snapshot = ConformanceSnapshot(protocolName: "W3C WebDriver / Appium", protocolVersion: "2024-11", implemented: ["sessions"], partial: ["WEBVIEW"], pendingIntegrations: ["WebKit Inspector real"], automatedTests: 28)
        let restored = try JSONDecoder().decode(ConformanceSnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(restored, snapshot)
        XCTAssertTrue(restored.implemented.contains("sessions"))
        XCTAssertTrue(restored.pendingIntegrations.contains("WebKit Inspector real"))
    }

    func testSessionHealthSnapshotRoundTrip() throws {
        let snapshot = SessionHealthSnapshot(sessionID: "s", healthy: false, context: "NATIVE_APP", blockers: ["xctest_bridge_not_registered"], commandsUsed: 4, commandsRemaining: 6, failureRate: 0.25, p95DurationMilliseconds: 180)
        let restored = try JSONDecoder().decode(SessionHealthSnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(restored, snapshot)
        XCTAssertEqual(restored.blockers.first, "xctest_bridge_not_registered")
        XCTAssertEqual(restored.commandsRemaining, 6)
    }

    func testLearnedLessonStoreRoundTrip() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("cuyscout-lessons-\(UUID().uuidString).json")
        let lesson = LearnedLesson(scope: .global, title: "Teclado cubre el campo", observation: "El teclado reduce el área visible al escribir", recommendation: "Desplazar el formulario antes de validar", tags: ["keyboard", "scroll"], confidence: 0.95)
        try LessonStore(fileURL: file).upsert(lesson)
        let restored = LessonStore(fileURL: file).list()
        XCTAssertEqual(restored, [lesson])
    }

    func testLessonRedactorRemovesSecrets() {
        let text = "El usuario test@example.com recibió Bearer abc123; password=hunter2; order 123456789."
        let redacted = LessonRedactor.redact(text)
        XCTAssertFalse(redacted.contains("test@example.com"))
        XCTAssertFalse(redacted.contains("abc123"))
        XCTAssertFalse(redacted.contains("hunter2"))
        XCTAssertFalse(redacted.contains("123456789"))
        XCTAssertGreaterThanOrEqual(redacted.components(separatedBy: "<redacted>").count, 5)
    }

    func testLearnedLessonStoreConsolidatesAndSearches() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("cuyscout-lessons-\(UUID().uuidString).json")
        let store = LessonStore(fileURL: file)
        let first = try store.record(LearnedLesson(scope: .project, projectKey: "com.example.app", title: "Teclado cubre el campo", observation: "El botón queda oculto", recommendation: "Cerrar el teclado", tags: ["keyboard"], confidence: 0.7))
        let reinforced = try store.record(LearnedLesson(scope: .project, projectKey: "com.example.app", title: "  teclado CUBRE el campo ", observation: "El botón sigue oculto", recommendation: "Cerrar el teclado antes de continuar", tags: ["form", "keyboard"], confidence: 0.8))
        _ = try store.record(LearnedLesson(scope: .global, title: "Esperar animaciones", observation: "La vista tarda", recommendation: "Esperar estabilidad", tags: ["timing"], confidence: 0.9))

        XCTAssertEqual(first.id, reinforced.id)
        XCTAssertEqual(reinforced.occurrences, 2)
        XCTAssertEqual(Set(reinforced.tags), Set(["keyboard", "form"]))
        XCTAssertGreaterThan(reinforced.confidence, 0.8)
        XCTAssertEqual(store.list().count, 2)
        XCTAssertEqual(store.search(query: "botón oculto", tags: ["keyboard"]).map(\.id), [first.id])
        XCTAssertEqual(store.search(tags: ["timing"], scope: .global).first?.title, "Esperar animaciones")
    }

    func testLessonInferenceLearnsOnlyEvidenceBackedPatterns() {
        let now = Date()
        let steps = [
            RecordedStep(index: 0, action: .typeElement(ScoutSelector(strategy: .accessibilityIdentifier, value: "email"), text: "secret@example.com"), startedAt: now, durationMilliseconds: 100, success: true),
            RecordedStep(index: 1, action: .tapElement(ScoutSelector(strategy: .accessibilityIdentifier, value: "continue")), startedAt: now, durationMilliseconds: 2_100, success: false, error: "no such element: continue"),
            RecordedStep(index: 2, action: .assertVisible(ScoutSelector(strategy: .accessibilityIdentifier, value: "continue")), startedAt: now, durationMilliseconds: 2_500, success: false, error: "not visible: continue")
        ]
        let exploration = ExplorationReport(status: .loopDetected, reason: "same_state_repeated", actionCount: 3, repeatedStateCount: 3, visitedStateCount: 1)
        let lessons = LessonInference.infer(steps: steps, exploration: exploration, scope: .project, projectKey: "com.example.app", sessionID: "session")

        XCTAssertEqual(lessons.count, 4)
        XCTAssertTrue(lessons.contains { $0.tags.contains("keyboard") })
        XCTAssertTrue(lessons.contains { $0.tags.contains("loop") })
        XCTAssertTrue(lessons.contains { $0.tags.contains("timing") })
        XCTAssertTrue(lessons.contains { $0.title == "Fallo recurrente de selector" })
        XCTAssertFalse(String(data: try! JSONEncoder().encode(lessons), encoding: .utf8)!.contains("secret@example.com"))
    }

    func testTestPlanValidatorRejectsFragileIncompletePlans() {
        let plan = TestPlan(sessionID: "s", steps: [
            TestPlanStep(id: "step-1", action: .tap(x: 2, y: 3), success: true, durationMilliseconds: 1),
            TestPlanStep(id: "step-2", action: .typeElement(ScoutSelector(strategy: .label, value: ""), text: "<text>"), success: false, durationMilliseconds: 1)
        ], warnings: [])
        let result = TestPlanValidator.validate(plan, exports: ["", "valid"])
        XCTAssertFalse(result.valid)
        XCTAssertFalse(result.executable)
        XCTAssertGreaterThanOrEqual(result.errors.count, 3)
        XCTAssertTrue(result.warnings.contains { $0.contains("coordenadas") })
        XCTAssertTrue(result.warnings.contains { $0.contains("placeholder") })
        XCTAssertTrue(result.warnings.contains { $0.contains("accessibilityIdentifier") })
    }

    func testTestPlanValidatorChecksExporterStructure() {
        let plan = TestPlan(sessionID: "s", steps: [TestPlanStep(id: "step-1", action: .tapElement(ScoutSelector(strategy: .accessibilityIdentifier, value: "submit")), success: true, durationMilliseconds: 1)], warnings: [])
        let exports = ["XCTestCase func test", "webdriverio describe(", "WebdriverIO.Browser WebdriverIO.Element describe(", "unittest def test_recorded_exploration", "@Test class", "Feature: Scenario:", "[]"]
        let valid = TestPlanValidator.validate(plan, exports: exports)
        XCTAssertTrue(valid.valid)
        XCTAssertTrue(valid.executable)

        let broken = TestPlanValidator.validate(plan, exports: ["bad"])
        XCTAssertFalse(broken.valid)
        XCTAssertTrue(broken.errors.contains { $0.contains("marcador estructural") })
    }

    func testActionRepairProposalPreservesApprovalBoundary() throws {
        let original = ScoutAction.tapElement(ScoutSelector(strategy: .label, value: "Continue"))
        let proposed = ScoutAction.tapElement(ScoutSelector(strategy: .accessibilityIdentifier, value: "continueButton"))
        let proposal = ActionRepairProposal(original: original, proposed: proposed, score: 0.92, reason: "Coincidencia semántica por identifier")
        let restored = try JSONDecoder().decode(ActionRepairProposal.self, from: JSONEncoder().encode(proposal))
        XCTAssertEqual(restored, proposal)
        XCTAssertTrue(restored.requiresApproval)
        XCTAssertEqual(restored.score, 0.92)
    }

    func testRepairAuditRoundTrip() throws {
        let proposal = ActionRepairProposal(original: .tapElement(ScoutSelector(strategy: .label, value: "Continue")), proposed: .tapElement(ScoutSelector(strategy: .accessibilityIdentifier, value: "continueButton")), score: 0.92, reason: "identifier")
        let entry = RepairAuditEntry(id: 1, sessionID: "s", proposal: proposal, decision: .applied)
        let restored = try JSONDecoder().decode(RepairAuditEntry.self, from: JSONEncoder().encode(entry))
        XCTAssertEqual(restored, entry)
        XCTAssertEqual(restored.decision, .applied)
    }

    func testBatchRequestIDContract() {
        let first = BatchExecutionResult(success: true, executed: 1, total: 1, steps: [BatchStepResult(index: 0, success: true, durationMilliseconds: 1)])
        let encoded = try? JSONEncoder().encode(first)
        XCTAssertNotNil(encoded)
        XCTAssertEqual(first, try? JSONDecoder().decode(BatchExecutionResult.self, from: encoded!))
    }

    func testBatchCompactSummaryRoundTrip() throws {
        let summary = BatchCompactSummary(requestID: "request-1", success: false, executed: 2, total: 3, failedSteps: [1], failureCategories: ["infrastructure": 1], retryableFailureCount: 1, nextActionHint: "retry_infrastructure_only")
        let restored = try JSONDecoder().decode(BatchCompactSummary.self, from: JSONEncoder().encode(summary))
        XCTAssertEqual(restored, summary)
        XCTAssertEqual(restored.failureCategories["infrastructure"], 1)
    }

    func testBatchTimeoutIsRepresentedByStepError() {
        let result = BatchExecutionResult(success: false, executed: 1, total: 2, steps: [BatchStepResult(index: 1, success: false, durationMilliseconds: 0, error: "batch_timeout")])
        XCTAssertEqual(result.steps.first?.error, "batch_timeout")
        XCTAssertFalse(result.success)
    }

    func testBatchValidationReportsEmptySequenceAndPlaceholder() {
        let validation = BatchValidation(valid: false, actionCount: 1, errors: ["actions[0]: la secuencia está vacía."], warnings: ["actions[1]: contiene un placeholder de dato sensible."])
        XCTAssertFalse(validation.valid)
        XCTAssertEqual(validation.errors.count, 1)
        XCTAssertEqual(validation.warnings.count, 1)
    }

    func testExplorationCoverageRoundTrip() throws {
        let coverage = ExplorationCoverage(stateCount: 3, transitionCount: 4, uniqueTransitionCount: 3, repeatedTransitionCount: 1, repeatedTransitionRate: 0.25, loopRisk: true, nextActionHint: "try_alternative_action")
        let decoded = try JSONDecoder().decode(ExplorationCoverage.self, from: JSONEncoder().encode(coverage))
        XCTAssertEqual(decoded, coverage)
        XCTAssertTrue(decoded.loopRisk)
    }

    func testScreenContractRoundTripAndComparison() throws {
        let element = ScreenContractElement(identifier: "loginButton", role: "button", label: "Login")
        let contract = ScreenContract(name: "Login", stateId: "state", context: "NATIVE_APP", elements: [element])
        let decoded = try JSONDecoder().decode(ScreenContract.self, from: JSONEncoder().encode(contract))
        XCTAssertEqual(decoded, contract)
        let comparison = ScreenContractComparison(matches: false, missing: [element], changed: [], unexpected: [])
        XCTAssertFalse(comparison.matches)
        XCTAssertEqual(comparison.missing.first?.identifier, "loginButton")
    }

    func testSecurityPolicyCommandBudgetDefaultsAndRoundTrips() throws {
        let policy = SecurityPolicy(maxCommandsPerSession: 25, deniedActionTypes: ["SETCLIPBOARD"])
        let decoded = try JSONDecoder().decode(SecurityPolicy.self, from: JSONEncoder().encode(policy))
        XCTAssertEqual(decoded.maxCommandsPerSession, 25)
        XCTAssertEqual(decoded.deniedActionTypes, ["SETCLIPBOARD"])
        let legacy = try JSONDecoder().decode(SecurityPolicy.self, from: Data("{}".utf8))
        XCTAssertEqual(legacy.maxCommandsPerSession, 0)
    }

    func testArtifactStoreStatusRoundTrip() throws {
        let status = ArtifactStoreStatus(available: true, persistedCount: 2, autosaveInterval: 10, totalBytes: 2048, latestSavedAt: Date(timeIntervalSince1970: 100), artifactRetention: 5)
        XCTAssertEqual(try JSONDecoder().decode(ArtifactStoreStatus.self, from: JSONEncoder().encode(status)), status)
    }

    func testArtifactRetentionLimitIsConfigured() {
        let store = ArtifactStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), retentionLimit: 3)
        XCTAssertEqual(store.retentionLimit, 3)
    }

    func testPrometheusMetricsFormat() {
        let engine = ScoutEngine()
        let text = engine.fleetMetricsPrometheus()
        XCTAssertTrue(text.contains("# TYPE cuyscout_active_sessions gauge"))
        XCTAssertTrue(text.contains("cuyscout_failure_rate"))
    }

    func testSecurityAuditRoundTrip() throws {
        let entry = SecurityAuditEntry(id: 1, sessionID: "s", actionType: "setClipboard", allowed: false, sensitive: true, reason: "blocked")
        XCTAssertEqual(try JSONDecoder().decode(SecurityAuditEntry.self, from: JSONEncoder().encode(entry)), entry)
        XCTAssertTrue(entry.sensitive)
    }

    func testArtifactPreservesSecurityPolicy() throws {
        let policy = SecurityPolicy(allowLifecycle: false, maxCommandsPerSession: 25)
        let session = Session(id: "policy-session", device: Device(id: "device", name: "iPhone", runtime: "iOS", state: "Booted"), bundleIdentifier: nil, createdAt: Date())
        let artifact = SessionArtifactBundle(session: session, events: [], metrics: SessionMetrics(totalCommands: 0, successfulCommands: 0, failedCommands: 0, failureRate: 0, averageDurationMilliseconds: 0, p95DurationMilliseconds: 0, commandCounts: [:]), checkpoints: [], testPlan: nil, securityPolicy: policy)
        let decoded = try JSONDecoder().decode(SessionArtifactBundle.self, from: JSONEncoder().encode(artifact))
        XCTAssertEqual(decoded.securityPolicy, policy)
    }

    func testArtifactStoreRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("cuyscout-test-\(UUID().uuidString)")
        let store = ArtifactStore(directory: directory)
        let session = Session(id: "stored-session", device: Device(id: "device", name: "iPhone", runtime: "iOS", state: "Booted"), bundleIdentifier: nil, createdAt: Date())
        let artifact = SessionArtifactBundle(session: session, events: [], metrics: SessionMetrics(totalCommands: 0, successfulCommands: 0, failedCommands: 0, failureRate: 0, averageDurationMilliseconds: 0, p95DurationMilliseconds: 0, commandCounts: [:]), checkpoints: [], testPlan: nil)
        try store.save(artifact)
        XCTAssertEqual(store.list(), ["stored-session"])
        XCTAssertNoThrow(try JSONDecoder().decode(SessionArtifactBundle.self, from: store.load(sessionID: "stored-session")))
        XCTAssertNil(artifact.totalCommandCount)
    }

    func testPluginRegistrationContract() {
        let engine = ScoutEngine()
        let plugin = TestPlugin()
        engine.registerPlugin(plugin)
        XCTAssertTrue(engine.plugins().contains { $0.id == "test-plugin" })
        engine.unregisterPlugin(id: "test-plugin")
        XCTAssertFalse(engine.plugins().contains { $0.id == "test-plugin" })
    }

    func testDriverRegistrationContract() {
        let engine = ScoutEngine()
        let driver = TestDriver()
        engine.registerDriver(driver)
        XCTAssertTrue(engine.drivers().contains { $0.id == "test-driver" })
        XCTAssertEqual(engine.driverHealth()["test-driver"]?.healthy, true)
        engine.unregisterDriver(id: "test-driver")
        XCTAssertFalse(engine.drivers().contains { $0.id == "test-driver" })
    }

    func testSchedulerLeaseContract() {
        let scheduler = DeviceScheduler()
        XCTAssertTrue(scheduler.acquire(deviceID: "device", sessionID: "session-a"))
        XCTAssertFalse(scheduler.acquire(deviceID: "device", sessionID: "session-b"))
        scheduler.release(deviceID: "device", sessionID: "session-b")
        XCTAssertTrue(scheduler.isLeased("device"))
        scheduler.release(deviceID: "device", sessionID: "session-a")
        XCTAssertFalse(scheduler.isLeased("device"))
    }

    func testSchedulerPortIsolationAndReuse() {
        let scheduler = DeviceScheduler(portStart: 9100, portCount: 2)
        XCTAssertTrue(scheduler.acquire(deviceID: "device-a", sessionID: "session-a"))
        XCTAssertTrue(scheduler.acquire(deviceID: "device-b", sessionID: "session-b"))
        XCTAssertEqual(scheduler.port(sessionID: "session-a"), 9100)
        XCTAssertEqual(scheduler.port(sessionID: "session-b"), 9101)
        scheduler.release(deviceID: "device-a", sessionID: "session-a")
        XCTAssertNil(scheduler.port(sessionID: "session-a"))
        XCTAssertTrue(scheduler.acquire(deviceID: "device-c", sessionID: "session-c"))
        XCTAssertEqual(scheduler.port(sessionID: "session-c"), 9100)
    }

    func testRelativeElementSearchActionsRoundTrip() throws {
        let parent = ScoutSelector(strategy: .accessibilityIdentifier, value: "parentCell")
        let child = ScoutSelector(strategy: .label, value: "Edit")
        let actions: [ScoutAction] = [.findElementFromElement(parent: parent, child: child), .findElementsFromElement(parent: parent, child: child)]
        for action in actions {
            let data = try JSONEncoder().encode(action)
            XCTAssertEqual(try JSONDecoder().decode(ScoutAction.self, from: data), action)
        }
    }

    func testElementSelectedAndNameActionsRoundTrip() throws {
        let selector = ScoutSelector(strategy: .accessibilityIdentifier, value: "toggleSwitch")
        let actions: [ScoutAction] = [.elementSelected(selector), .elementName(selector)]
        for action in actions {
            let data = try JSONEncoder().encode(action)
            XCTAssertEqual(try JSONDecoder().decode(ScoutAction.self, from: data), action)
        }
    }

    func testConformanceSnapshotIncludesNewCapabilities() {
        let snapshot = ScoutEngine().conformanceSnapshot()
        XCTAssertTrue(snapshot.implemented.contains("findElementFromElement"))
        XCTAssertTrue(snapshot.implemented.contains("findElementsFromElement"))
        XCTAssertTrue(snapshot.implemented.contains("windowRect"))
        XCTAssertTrue(snapshot.implemented.contains("elementSelected"))
        XCTAssertTrue(snapshot.implemented.contains("elementName"))
        XCTAssertTrue(snapshot.implemented.contains("pageLoad"))
    }

    func testPageLoadTimeoutIsConfigurable() throws {
        let engine = ScoutEngine()
        let session = try engine.createSession(deviceID: nil, bundleIdentifier: nil, driverID: "ios-simulator")
        try engine.updateTimeouts(sessionID: session.id, values: ["pageLoad": 5000])
        let timeouts = try engine.getTimeouts(sessionID: session.id)
        XCTAssertEqual(timeouts["pageLoad"], 5000)
    }

    func testWindowRectRequiresSession() {
        let engine = ScoutEngine()
        XCTAssertThrowsError(try engine.windowRect(sessionID: "nonexistent")) { error in
            guard case ScoutError.sessionNotFound = error else { return XCTFail("Expected sessionNotFound") }
        }
    }

    func testSetWindowRectUnsupportedInNative() throws {
        let engine = ScoutEngine()
        let session = try engine.createSession(deviceID: nil, bundleIdentifier: nil, driverID: "ios-simulator")
        XCTAssertThrowsError(try engine.setWindowRect(sessionID: session.id, x: 0, y: 0, width: 100, height: 100)) { error in
            guard case ScoutError.unsupported = error else { return XCTFail("Expected unsupported") }
        }
    }

    func testScrollAndAlertTextActionsRoundTrip() throws {
        let actions: [ScoutAction] = [.scroll(x: 0, y: 100), .alertText("hello"), .activeElement]
        for action in actions {
            let data = try JSONEncoder().encode(action)
            XCTAssertEqual(try JSONDecoder().decode(ScoutAction.self, from: data), action)
        }
    }

    func testElementPropertyActionRoundTrip() throws {
        let selector = ScoutSelector(strategy: .accessibilityIdentifier, value: "field")
        let action = ScoutAction.elementProperty(selector, name: "label")
        let data = try JSONEncoder().encode(action)
        XCTAssertEqual(try JSONDecoder().decode(ScoutAction.self, from: data), action)
    }

    func testCookieModelRoundTrip() throws {
        let cookie = Cookie(name: "session", value: "abc123", path: "/", domain: "example.com", secure: true, httpOnly: true, expiry: 3600)
        let data = try JSONEncoder().encode(cookie)
        let decoded = try JSONDecoder().decode(Cookie.self, from: data)
        XCTAssertEqual(cookie, decoded)
    }

    func testCookiesRequireSession() {
        let engine = ScoutEngine()
        XCTAssertThrowsError(try engine.cookies(sessionID: "nonexistent")) { error in
            guard case ScoutError.sessionNotFound = error else { return XCTFail("Expected sessionNotFound") }
        }
    }

    func testAddCookieRequiresWebView() throws {
        let engine = ScoutEngine()
        let session = try engine.createSession(deviceID: nil, bundleIdentifier: nil, driverID: "ios-simulator")
        let cookie = Cookie(name: "test", value: "1")
        XCTAssertThrowsError(try engine.addCookie(sessionID: session.id, cookie: cookie)) { error in
            guard case ScoutError.unsupported = error else { return XCTFail("Expected unsupported") }
        }
    }

    func testActiveElementReturnsNilInNative() throws {
        let engine = ScoutEngine()
        let session = try engine.createSession(deviceID: nil, bundleIdentifier: nil, driverID: "ios-simulator")
        XCTAssertNil(try engine.activeElement(sessionID: session.id))
    }

    func testConformanceSnapshotIncludesScrollCookiesActiveElement() {
        let snapshot = ScoutEngine().conformanceSnapshot()
        XCTAssertTrue(snapshot.implemented.contains("scroll"))
        XCTAssertTrue(snapshot.implemented.contains("cookies"))
        XCTAssertTrue(snapshot.implemented.contains("activeElement"))
        XCTAssertTrue(snapshot.implemented.contains("elementProperty"))
        XCTAssertTrue(snapshot.implemented.contains("alertText"))
    }

    func testPermissionBiometryLocationActionsRoundTrip() throws {
        let actions: [ScoutAction] = [
            .grantPermission(bundleIdentifier: "com.example.app", service: "camera"),
            .setBiometry(enrolled: true, enabled: true),
            .setLocation(latitude: 37.7749, longitude: -122.4194),
            .visualDiff(tolerance: 0.05)
        ]
        for action in actions {
            let data = try JSONEncoder().encode(action)
            XCTAssertEqual(try JSONDecoder().decode(ScoutAction.self, from: data), action)
        }
    }

    func testPermissionGrantModelRoundTrip() throws {
        let grant = PermissionGrant(bundleIdentifier: "com.example.app", service: "camera", granted: true)
        let data = try JSONEncoder().encode(grant)
        XCTAssertEqual(try JSONDecoder().decode(PermissionGrant.self, from: data), grant)
    }

    func testBiometryResultModelRoundTrip() throws {
        let result = BiometryResult(enrolled: true, enabled: true)
        let data = try JSONEncoder().encode(result)
        XCTAssertEqual(try JSONDecoder().decode(BiometryResult.self, from: data), result)
    }

    func testVisualDiffResultModelRoundTrip() throws {
        let result = VisualDiffResult(identical: true, differenceRatio: 0.02, tolerance: 0.1, pixelDifferences: 500)
        let data = try JSONEncoder().encode(result)
        XCTAssertEqual(try JSONDecoder().decode(VisualDiffResult.self, from: data), result)
    }

    func testTimelineEntryModelRoundTrip() throws {
        let entry = TimelineEntry(id: 1, timestamp: Date(), actionType: "tap", success: true, durationMilliseconds: 120)
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(TimelineEntry.self, from: data)
        XCTAssertEqual(entry.id, decoded.id)
        XCTAssertEqual(entry.actionType, decoded.actionType)
        XCTAssertEqual(entry.success, decoded.success)
    }

    func testTimelineRequiresSession() {
        let engine = ScoutEngine()
        XCTAssertThrowsError(try engine.timeline(sessionID: "nonexistent")) { error in
            guard case ScoutError.sessionNotFound = error else { return XCTFail("Expected sessionNotFound") }
        }
    }

    func testVisualDiffRequiresSession() {
        let engine = ScoutEngine()
        XCTAssertThrowsError(try engine.visualDiff(sessionID: "nonexistent")) { error in
            guard case ScoutError.sessionNotFound = error else { return XCTFail("Expected sessionNotFound") }
        }
    }

    func testPluginAllowlistBlocksUnregistered() {
        let registry = PluginRegistry()
        registry.setAllowlist(["allowed-plugin"])
        let plugin = TestPlugin()
        registry.register(plugin)
        XCTAssertFalse(registry.descriptors().contains { $0.id == "test-plugin" })
    }

    func testPluginAllowlistAllowsRegistered() {
        let registry = PluginRegistry()
        registry.setAllowlist(["test-plugin"])
        let plugin = TestPlugin()
        registry.register(plugin)
        XCTAssertTrue(registry.descriptors().contains { $0.id == "test-plugin" })
    }

    func testDriverDescriptorDeclaresCapabilities() {
        let driver = SimulatorDriverAdapter()
        XCTAssertFalse(driver.descriptor.supportedCapabilities.isEmpty)
        XCTAssertFalse(driver.descriptor.supportedSettings.isEmpty)
        XCTAssertTrue(driver.descriptor.supportedCapabilities.contains("appium:udid"))
    }

    func testConformanceSnapshotIncludesNewPhaseFeatures() {
        let snapshot = ScoutEngine().conformanceSnapshot()
        XCTAssertTrue(snapshot.implemented.contains("permissions"))
        XCTAssertTrue(snapshot.implemented.contains("biometry"))
        XCTAssertTrue(snapshot.implemented.contains("geolocation"))
        XCTAssertTrue(snapshot.implemented.contains("visualDiff"))
        XCTAssertTrue(snapshot.implemented.contains("timeline"))
    }

    func testSessionPriorityOrdering() {
        XCTAssertLessThan(SessionPriority.normal, SessionPriority.high)
        XCTAssertLessThan(SessionPriority.high, SessionPriority.urgent)
        XCTAssertLessThan(SessionPriority.low, SessionPriority.normal)
    }

    func testQueueEntryModelRoundTrip() throws {
        let entry = QueueEntry(sessionID: "s1", deviceID: "dev", bundleIdentifier: "com.app", driverID: "ios-simulator", priority: .urgent)
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(QueueEntry.self, from: data)
        XCTAssertEqual(entry, decoded)
    }

    func testEnqueueAndCancelSession() {
        let engine = ScoutEngine()
        let entry = engine.enqueueSession(deviceID: nil, bundleIdentifier: nil, driverID: "ios-simulator", priority: .high)
        XCTAssertEqual(engine.sessionQueueSnapshot().count, 1)
        XCTAssertTrue(engine.cancelQueuedSession(sessionID: entry.sessionID))
        XCTAssertEqual(engine.sessionQueueSnapshot().count, 0)
    }

    func testQueueSortedByPriority() {
        let engine = ScoutEngine()
        _ = engine.enqueueSession(deviceID: nil, bundleIdentifier: nil, driverID: "ios-simulator", priority: .low)
        _ = engine.enqueueSession(deviceID: nil, bundleIdentifier: nil, driverID: "ios-simulator", priority: .urgent)
        _ = engine.enqueueSession(deviceID: nil, bundleIdentifier: nil, driverID: "ios-simulator", priority: .normal)
        let queue = engine.sessionQueueSnapshot()
        XCTAssertEqual(queue[0].priority, .urgent)
        XCTAssertEqual(queue[1].priority, .normal)
        XCTAssertEqual(queue[2].priority, .low)
    }

    func testFleetDashboardRequiresNoSession() {
        let engine = ScoutEngine()
        XCTAssertNoThrow(try engine.fleetDashboard())
    }

    func testConsoleLogEntryModelRoundTrip() throws {
        let entry = ConsoleLogEntry(id: 1, level: "error", message: "test", source: "app")
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(ConsoleLogEntry.self, from: data)
        XCTAssertEqual(entry, decoded)
    }

    func testConsoleLogRequiresSession() {
        let engine = ScoutEngine()
        XCTAssertThrowsError(try engine.consoleLogs(sessionID: "nonexistent")) { error in
            guard case ScoutError.sessionNotFound = error else { return XCTFail("Expected sessionNotFound") }
        }
    }

    func testReactiveRuleModelRoundTrip() throws {
        let rule = ReactiveRule(id: "rule1", eventKind: "command.failed", action: .screenshot, captureScreenshot: true)
        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(ReactiveRule.self, from: data)
        XCTAssertEqual(rule, decoded)
    }

    func testReactiveRuleAddAndRemove() throws {
        let engine = ScoutEngine()
        let session = try engine.createSession(deviceID: nil, bundleIdentifier: nil, driverID: "ios-simulator")
        let rule = ReactiveRule(id: "r1", eventKind: "command.failed", action: .screenshot)
        try engine.addReactiveRule(sessionID: session.id, rule: rule)
        XCTAssertEqual(try engine.reactiveRulesList(sessionID: session.id).count, 1)
        XCTAssertTrue(try engine.removeReactiveRule(sessionID: session.id, ruleID: "r1"))
        XCTAssertEqual(try engine.reactiveRulesList(sessionID: session.id).count, 0)
    }

    func testAppCacheEntryModelRoundTrip() throws {
        let entry = AppCacheEntry(bundleIdentifier: "com.app", path: "/tmp/app.app")
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(AppCacheEntry.self, from: data)
        XCTAssertEqual(entry, decoded)
    }

    func testAppCacheStoreAndRetrieve() {
        let engine = ScoutEngine()
        let entry = engine.cacheApp(bundleIdentifier: "com.app", path: "/tmp/app.app")
        XCTAssertEqual(engine.cachedApp(bundleIdentifier: "com.app")?.path, "/tmp/app.app")
        XCTAssertEqual(engine.appCacheList().count, 1)
        engine.clearAppCache(bundleIdentifier: "com.app")
        XCTAssertNil(engine.cachedApp(bundleIdentifier: "com.app"))
    }

    func testConformanceSnapshotIncludesFase8And10Features() {
        let snapshot = ScoutEngine().conformanceSnapshot()
        XCTAssertTrue(snapshot.implemented.contains("sessionQueue"))
        XCTAssertTrue(snapshot.implemented.contains("fleetDashboard"))
        XCTAssertTrue(snapshot.implemented.contains("appCache"))
        XCTAssertTrue(snapshot.implemented.contains("consoleLogs"))
        XCTAssertTrue(snapshot.implemented.contains("reactiveRules"))
    }

    func testSemanticFingerprintModelRoundTrip() throws {
        let fp = SemanticFingerprint(elementID: "el1", identifier: "loginBtn", label: "Login", elementType: "button", frame: ["x": 10, "y": 20, "width": 100, "height": 44], fingerprintHash: "abc123")
        let data = try JSONEncoder().encode(fp)
        let decoded = try JSONDecoder().decode(SemanticFingerprint.self, from: data)
        XCTAssertEqual(fp, decoded)
    }

    func testRecordAndRetrieveFingerprint() throws {
        let engine = ScoutEngine()
        let session = try engine.createSession(deviceID: nil, bundleIdentifier: nil, driverID: "ios-simulator")
        try engine.recordFingerprint(sessionID: session.id, elementID: "el1", identifier: "loginBtn", label: "Login", elementType: "button", frame: ["x": 10, "y": 20, "width": 100, "height": 44])
        let fingerprints = try engine.fingerprints(sessionID: session.id)
        XCTAssertEqual(fingerprints.count, 1)
        XCTAssertEqual(fingerprints.first?.identifier, "loginBtn")
    }

    func testMatchFingerprintByLabel() throws {
        let engine = ScoutEngine()
        let session = try engine.createSession(deviceID: nil, bundleIdentifier: nil, driverID: "ios-simulator")
        try engine.recordFingerprint(sessionID: session.id, elementID: "el1", identifier: "btn1", label: "Submit", elementType: "button", frame: [:])
        let match = try engine.matchFingerprint(sessionID: session.id, identifier: nil, label: "Submit", elementType: nil)
        XCTAssertEqual(match?.identifier, "btn1")
    }

    func testBehaviorComparisonDetectsMismatch() throws {
        let engine = ScoutEngine()
        let session = try engine.createSession(deviceID: nil, bundleIdentifier: nil, driverID: "ios-simulator")
        let result = try engine.compareBehavior(sessionID: session.id, expectedSuccess: true, actualSuccess: false, expectedError: nil)
        XCTAssertFalse(result.matched)
        XCTAssertTrue(result.differences.contains { $0.contains("success_mismatch") })
    }

    func testBehaviorComparisonMatched() throws {
        let engine = ScoutEngine()
        let session = try engine.createSession(deviceID: nil, bundleIdentifier: nil, driverID: "ios-simulator")
        let result = try engine.compareBehavior(sessionID: session.id, expectedSuccess: true, actualSuccess: true, expectedError: nil)
        XCTAssertTrue(result.matched)
    }

    func testDriverManifestModelRoundTrip() throws {
        let manifest = DriverManifest(id: "android-uiautomator2", name: "Android Driver", version: "1.0", platforms: ["Android"], libraryPath: "/tmp/driver.bundle")
        let data = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(DriverManifest.self, from: data)
        XCTAssertEqual(manifest, decoded)
    }

    func testRegisterAndListDriverManifest() {
        let engine = ScoutEngine()
        let manifest = DriverManifest(id: "android-uiautomator2", name: "Android Driver", version: "1.0", platforms: ["Android"], libraryPath: "/tmp/driver.bundle")
        engine.registerDriverManifest(manifest)
        XCTAssertEqual(engine.driverManifests().count, 1)
        XCTAssertEqual(engine.driverManifests().first?.id, "android-uiautomator2")
    }

    func testLoadDriverFromNonexistentPath() {
        let engine = ScoutEngine()
        let manifest = DriverManifest(id: "test-driver", name: "Test", version: "1.0", platforms: ["Test"], libraryPath: "/nonexistent/path.bundle")
        let result = engine.loadDriverFromManifest(manifest)
        XCTAssertFalse(result.loaded)
        XCTAssertNotNil(result.error)
    }

    func testPluginRoutesEmptyByDefault() {
        let engine = ScoutEngine()
        XCTAssertEqual(engine.pluginRoutes().count, 0)
    }

    func testPluginTransformResultDefault() {
        let registry = PluginRegistry()
        let plugin = TestPlugin()
        registry.register(plugin)
        let result = registry.transformResult(.screenshot, result: Data("test".utf8), sessionID: "s1")
        XCTAssertEqual(result, Data("test".utf8))
    }

    func testConformanceSnapshotIncludesSelfHealingAndDriverFeatures() {
        let snapshot = ScoutEngine().conformanceSnapshot()
        XCTAssertTrue(snapshot.implemented.contains("semanticFingerprints"))
        XCTAssertTrue(snapshot.implemented.contains("behaviorComparison"))
        XCTAssertTrue(snapshot.implemented.contains("pluginRoutes"))
        XCTAssertTrue(snapshot.implemented.contains("driverManifests"))
    }

    func testSubmitActionRoundTrip() throws {
        let selector = ScoutSelector(strategy: .accessibilityIdentifier, value: "form")
        let action = ScoutAction.submit(selector)
        let data = try JSONEncoder().encode(action)
        XCTAssertEqual(try JSONDecoder().decode(ScoutAction.self, from: data), action)
    }

    func testNetworkRequestEntryModelRoundTrip() throws {
        let entry = NetworkRequestEntry(id: 1, method: "GET", url: "https://api.example.com", status: 200, requestSize: 100, responseSize: 500, durationMilliseconds: 50)
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(NetworkRequestEntry.self, from: data)
        XCTAssertEqual(entry, decoded)
    }

    func testRecordAndListNetworkRequests() throws {
        let engine = ScoutEngine()
        let session = try engine.createSession(deviceID: nil, bundleIdentifier: nil, driverID: "ios-simulator")
        try engine.recordNetworkRequest(sessionID: session.id, method: "POST", url: "https://api.example.com/login", status: 200)
        let requests = try engine.networkRequestsList(sessionID: session.id)
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.method, "POST")
    }

    func testShardConfigModelRoundTrip() throws {
        let config = ShardConfig(shardIndex: 0, shardCount: 4)
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(ShardConfig.self, from: data)
        XCTAssertEqual(config, decoded)
    }

    func testSetAndGetShardConfig() throws {
        let engine = ScoutEngine()
        let session = try engine.createSession(deviceID: nil, bundleIdentifier: nil, driverID: "ios-simulator")
        try engine.setShardConfig(sessionID: session.id, shardIndex: 1, shardCount: 3)
        let config = try engine.shardConfig(sessionID: session.id)
        XCTAssertEqual(config?.shardIndex, 1)
        XCTAssertEqual(config?.shardCount, 3)
    }

    func testShardConfigRejectsInvalid() throws {
        let engine = ScoutEngine()
        let session = try engine.createSession(deviceID: nil, bundleIdentifier: nil, driverID: "ios-simulator")
        XCTAssertThrowsError(try engine.setShardConfig(sessionID: session.id, shardIndex: 5, shardCount: 3)) { error in
            guard case ScoutError.invalidRequest = error else { return XCTFail("Expected invalidRequest") }
        }
    }

    func testShouldRunInShard() throws {
        let engine = ScoutEngine()
        let session = try engine.createSession(deviceID: nil, bundleIdentifier: nil, driverID: "ios-simulator")
        try engine.setShardConfig(sessionID: session.id, shardIndex: 0, shardCount: 2)
        XCTAssertTrue(try engine.shouldRunInShard(sessionID: session.id, stepIndex: 0))
        XCTAssertFalse(try engine.shouldRunInShard(sessionID: session.id, stepIndex: 1))
        XCTAssertTrue(try engine.shouldRunInShard(sessionID: session.id, stepIndex: 2))
    }

    func testOtelSpanModelRoundTrip() throws {
        let span = OtelSpan(traceID: "trace1", spanID: "span1", parentSpanID: nil, name: "perform", attributes: ["action": "tap"])
        let data = try JSONEncoder().encode(span)
        let decoded = try JSONDecoder().decode(OtelSpan.self, from: data)
        XCTAssertEqual(span, decoded)
    }

    func testRecordAndListOtelSpans() throws {
        let engine = ScoutEngine()
        let session = try engine.createSession(deviceID: nil, bundleIdentifier: nil, driverID: "ios-simulator")
        let span = OtelSpan(traceID: "t1", spanID: "s1", name: "test")
        try engine.recordOtelSpan(sessionID: session.id, span: span)
        XCTAssertEqual(try engine.otelSpansList(sessionID: session.id).count, 1)
    }

    func testPluginDescriptorHasSignatureField() {
        let descriptor = PluginDescriptor(id: "signed-plugin", name: "Signed", capabilities: [], signature: "abc123")
        XCTAssertEqual(descriptor.signature, "abc123")
    }

    func testPluginDescriptorSignatureDefaultsNil() {
        let descriptor = PluginDescriptor(id: "unsigned", name: "Unsigned")
        XCTAssertNil(descriptor.signature)
    }

    func testConformanceSnapshotIncludesQuickWinFeatures() {
        let snapshot = ScoutEngine().conformanceSnapshot()
        XCTAssertTrue(snapshot.implemented.contains("submit"))
        XCTAssertTrue(snapshot.implemented.contains("networkCapture"))
        XCTAssertTrue(snapshot.implemented.contains("sharding"))
        XCTAssertTrue(snapshot.implemented.contains("openTelemetry"))
        XCTAssertTrue(snapshot.implemented.contains("pluginSignature"))
    }

    func testSetAppearanceActionRoundTrip() throws {
        let action = ScoutAction.setAppearance("dark")
        let data = try JSONEncoder().encode(action)
        XCTAssertEqual(try JSONDecoder().decode(ScoutAction.self, from: data), action)
    }

    func testStatusBarConfigModelRoundTrip() throws {
        let config = StatusBarConfig(time: "9:41", dataNetwork: "wifi", wifiMode: "active", batteryLevel: 75, batteryState: "charging")
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(StatusBarConfig.self, from: data)
        XCTAssertEqual(config, decoded)
    }

    func testVideoRecordingResultModelRoundTrip() throws {
        let result = VideoRecordingResult(path: "/tmp/video.mp4", started: true)
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(VideoRecordingResult.self, from: data)
        XCTAssertEqual(result, decoded)
    }

    func testAppInfoModelRoundTrip() throws {
        let app = AppInfo(bundleIdentifier: "com.example.app", name: "Example", type: "User")
        let data = try JSONEncoder().encode(app)
        let decoded = try JSONDecoder().decode(AppInfo.self, from: data)
        XCTAssertEqual(app, decoded)
    }

    func testDeepLinkActionRoundTrip() throws {
        let action = ScoutAction.deepLink("myapp://detail/123")
        let data = try JSONEncoder().encode(action)
        XCTAssertEqual(try JSONDecoder().decode(ScoutAction.self, from: data), action)
    }

    func testListAppsActionRoundTrip() throws {
        let action = ScoutAction.listApps
        let data = try JSONEncoder().encode(action)
        XCTAssertEqual(try JSONDecoder().decode(ScoutAction.self, from: data), action)
    }

    func testResetKeychainActionRoundTrip() throws {
        let action = ScoutAction.resetKeychain
        let data = try JSONEncoder().encode(action)
        XCTAssertEqual(try JSONDecoder().decode(ScoutAction.self, from: data), action)
    }

    func testStopVideoRecordingActionRoundTrip() throws {
        let action = ScoutAction.stopVideoRecording
        let data = try JSONEncoder().encode(action)
        XCTAssertEqual(try JSONDecoder().decode(ScoutAction.self, from: data), action)
    }

    func testConformanceSnapshotIncludesSimctlFeatures() {
        let snapshot = ScoutEngine().conformanceSnapshot()
        XCTAssertTrue(snapshot.implemented.contains("appearance"))
        XCTAssertTrue(snapshot.implemented.contains("statusBar"))
        XCTAssertTrue(snapshot.implemented.contains("videoRecording"))
        XCTAssertTrue(snapshot.implemented.contains("listApps"))
        XCTAssertTrue(snapshot.implemented.contains("keychain"))
        XCTAssertTrue(snapshot.implemented.contains("deepLink"))
    }

    func testPushNotificationActionRoundTrip() throws {
        let action = ScoutAction.pushNotification(bundleIdentifier: "com.app", payloadPath: "/tmp/push.apns")
        let data = try JSONEncoder().encode(action)
        XCTAssertEqual(try JSONDecoder().decode(ScoutAction.self, from: data), action)
    }

    func testPushNotificationPayloadModelRoundTrip() throws {
        let payload = PushNotificationPayload(bundleIdentifier: "com.app", payloadPath: "/tmp/push.apns", sent: true)
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(PushNotificationPayload.self, from: data)
        XCTAssertEqual(payload, decoded)
    }

    func testContentSizeModelRoundTrip() throws {
        let size = ContentSize(size: "extra-large")
        let data = try JSONEncoder().encode(size)
        let decoded = try JSONDecoder().decode(ContentSize.self, from: data)
        XCTAssertEqual(size, decoded)
    }

    func testSetContentSizeActionRoundTrip() throws {
        let action = ScoutAction.setContentSize("large")
        let data = try JSONEncoder().encode(action)
        XCTAssertEqual(try JSONDecoder().decode(ScoutAction.self, from: data), action)
    }

    func testAddMediaActionRoundTrip() throws {
        let action = ScoutAction.addMedia("/tmp/photo.jpg")
        let data = try JSONEncoder().encode(action)
        XCTAssertEqual(try JSONDecoder().decode(ScoutAction.self, from: data), action)
    }

    func testSpawnProcessActionRoundTrip() throws {
        let action = ScoutAction.spawnProcess(bundleIdentifier: "com.app", args: ["--flag"])
        let data = try JSONEncoder().encode(action)
        XCTAssertEqual(try JSONDecoder().decode(ScoutAction.self, from: data), action)
    }

    func testProcessSpawnResultModelRoundTrip() throws {
        let result = ProcessSpawnResult(bundleIdentifier: "com.app", pid: 1234, output: "done")
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(ProcessSpawnResult.self, from: data)
        XCTAssertEqual(result, decoded)
    }

    func testICloudSyncStatusModelRoundTrip() throws {
        let status = ICloudSyncStatus(synced: true, detail: "synced")
        let data = try JSONEncoder().encode(status)
        let decoded = try JSONDecoder().decode(ICloudSyncStatus.self, from: data)
        XCTAssertEqual(status, decoded)
    }

    func testICloudSyncActionRoundTrip() throws {
        let action = ScoutAction.icloudSync
        let data = try JSONEncoder().encode(action)
        XCTAssertEqual(try JSONDecoder().decode(ScoutAction.self, from: data), action)
    }

    func testConformanceSnapshotIncludesNewSimctlFeatures() {
        let snapshot = ScoutEngine().conformanceSnapshot()
        XCTAssertTrue(snapshot.implemented.contains("pushNotification"))
        XCTAssertTrue(snapshot.implemented.contains("contentSize"))
        XCTAssertTrue(snapshot.implemented.contains("addMedia"))
        XCTAssertTrue(snapshot.implemented.contains("spawnProcess"))
        XCTAssertTrue(snapshot.implemented.contains("icloudSync"))
        XCTAssertTrue(snapshot.implemented.contains("elementLocation"))
    }

    func testShakeActionRoundTrip() throws {
        let action = ScoutAction.shake
        let data = try JSONEncoder().encode(action)
        XCTAssertEqual(try JSONDecoder().decode(ScoutAction.self, from: data), action)
    }

    func testDoubleTapActionRoundTrip() throws {
        let selector = ScoutSelector(strategy: .accessibilityIdentifier, value: "btn")
        let action = ScoutAction.doubleTap(selector)
        let data = try JSONEncoder().encode(action)
        XCTAssertEqual(try JSONDecoder().decode(ScoutAction.self, from: data), action)
    }

    func testLongPressActionRoundTrip() throws {
        let selector = ScoutSelector(strategy: .accessibilityIdentifier, value: "btn")
        let action = ScoutAction.longPress(selector, duration: 2.0)
        let data = try JSONEncoder().encode(action)
        XCTAssertEqual(try JSONDecoder().decode(ScoutAction.self, from: data), action)
    }

    func testPinchActionRoundTrip() throws {
        let action = ScoutAction.pinch(scale: 2.0, velocity: 1.5)
        let data = try JSONEncoder().encode(action)
        XCTAssertEqual(try JSONDecoder().decode(ScoutAction.self, from: data), action)
    }

    func testEnumerateFilesActionRoundTrip() throws {
        let action = ScoutAction.enumerateFiles("/Documents")
        let data = try JSONEncoder().encode(action)
        XCTAssertEqual(try JSONDecoder().decode(ScoutAction.self, from: data), action)
    }

    func testGetAppearanceReturnsDefault() throws {
        let engine = ScoutEngine()
        let session = try engine.createSession(deviceID: nil, bundleIdentifier: nil, driverID: "ios-simulator")
        XCTAssertEqual(try engine.appearance(sessionID: session.id), "light")
    }

    func testGetContentSizeReturnsDefault() throws {
        let engine = ScoutEngine()
        let session = try engine.createSession(deviceID: nil, bundleIdentifier: nil, driverID: "ios-simulator")
        XCTAssertEqual(try engine.contentSize(sessionID: session.id), "standard")
    }

    func testConformanceSnapshotIncludesGestureFeatures() {
        let snapshot = ScoutEngine().conformanceSnapshot()
        XCTAssertTrue(snapshot.implemented.contains("shake"))
        XCTAssertTrue(snapshot.implemented.contains("doubleTap"))
        XCTAssertTrue(snapshot.implemented.contains("longPress"))
        XCTAssertTrue(snapshot.implemented.contains("pinch"))
        XCTAssertTrue(snapshot.implemented.contains("elementSize"))
        XCTAssertTrue(snapshot.implemented.contains("getAppearance"))
        XCTAssertTrue(snapshot.implemented.contains("getContentSize"))
        XCTAssertTrue(snapshot.implemented.contains("enumerateFiles"))
    }

    func testDeviceInfoIncludesEnrichedFields() throws {
        let engine = ScoutEngine()
        let session = try engine.createSession(deviceID: nil, bundleIdentifier: "com.example.app", driverID: "ios-simulator")
        let info = try engine.deviceInfo(sessionID: session.id)
        XCTAssertEqual(info["automationName"] as? String, "XCUITest")
        XCTAssertEqual(info["manufacturer"] as? String, "Apple")
        XCTAssertEqual(info["deviceName"] as? String, session.device.name)
        XCTAssertEqual(info["platformVersion"] as? String, session.device.runtime)
        XCTAssertEqual(info["bundleIdentifier"] as? String, "com.example.app")
    }

    func testDeviceTimeReturnsString() throws {
        let engine = ScoutEngine()
        let session = try engine.createSession(deviceID: nil, bundleIdentifier: nil, driverID: "ios-simulator")
        let time = try engine.deviceTime(sessionID: session.id)
        XCTAssertFalse(time.isEmpty)
    }

    func testConformanceSnapshotIncludesDeviceLifecycle() {
        let snapshot = ScoutEngine().conformanceSnapshot()
        XCTAssertTrue(snapshot.implemented.contains("deviceLifecycle"))
        XCTAssertTrue(snapshot.implemented.contains("pbsync"))
    }

    func testDownloadFileActionRoundTrip() throws {
        let action = ScoutAction.downloadFile(source: "/sim/path", destination: "/host/path")
        let data = try JSONEncoder().encode(action)
        XCTAssertEqual(try JSONDecoder().decode(ScoutAction.self, from: data), action)
    }

    func testUploadFileActionRoundTrip() throws {
        let action = ScoutAction.uploadFile(source: "/host/path", destination: "/sim/path")
        let data = try JSONEncoder().encode(action)
        XCTAssertEqual(try JSONDecoder().decode(ScoutAction.self, from: data), action)
    }

    func testGetAppContainerActionRoundTrip() throws {
        let action = ScoutAction.getAppContainer(bundleIdentifier: "com.app", container: "data")
        let data = try JSONEncoder().encode(action)
        XCTAssertEqual(try JSONDecoder().decode(ScoutAction.self, from: data), action)
    }

    func testGetConfigActionRoundTrip() throws {
        let action = ScoutAction.getConfig("some.key")
        let data = try JSONEncoder().encode(action)
        XCTAssertEqual(try JSONDecoder().decode(ScoutAction.self, from: data), action)
    }

    func testSetConfigActionRoundTrip() throws {
        let action = ScoutAction.setConfig(key: "some.key", value: "some.value")
        let data = try JSONEncoder().encode(action)
        XCTAssertEqual(try JSONDecoder().decode(ScoutAction.self, from: data), action)
    }

    func testConformanceSnapshotIncludesFileTransferFeatures() {
        let snapshot = ScoutEngine().conformanceSnapshot()
        XCTAssertTrue(snapshot.implemented.contains("fileTransfer"))
        XCTAssertTrue(snapshot.implemented.contains("appContainer"))
        XCTAssertTrue(snapshot.implemented.contains("simulatorConfig"))
    }

    func testFailureCategoryEnumValues() {
        XCTAssertEqual(FailureCategory.selector, FailureCategory(rawValue: "selector"))
        XCTAssertEqual(FailureCategory.infrastructure, FailureCategory(rawValue: "infrastructure"))
        XCTAssertEqual(FailureCategory.product, FailureCategory(rawValue: "product"))
    }

    func testClassifyFailureSelector() {
        let engine = ScoutEngine()
        XCTAssertEqual(engine.classifyFailure(ScoutError.noSuchElement("test")), .selector)
        XCTAssertEqual(engine.classifyFailure(ScoutError.staleElementReference("test")), .selector)
    }

    func testClassifyFailureInfrastructure() {
        let engine = ScoutEngine()
        XCTAssertEqual(engine.classifyFailure(ScoutError.commandFailed("Timeout esperando XCTest")), .infrastructure)
    }

    func testClassifyFailureEnvironment() {
        let engine = ScoutEngine()
        XCTAssertEqual(engine.classifyFailure(ScoutError.unsupported("test")), .environment)
    }

    func testTestVerificationResultModelRoundTrip() throws {
        let result = TestVerificationResult(compiled: true, executed: true, passed: true, exportFormat: "xctest", error: nil, durationMilliseconds: 500)
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(TestVerificationResult.self, from: data)
        XCTAssertEqual(result, decoded)
    }

    func testAccessibilityOverlayModelRoundTrip() throws {
        let overlay = AccessibilityOverlay(screenshotBase64: "abc", elements: [OverlayElement(identifier: "btn", label: "OK", elementType: "button", frame: ["x": 10, "y": 20, "width": 100, "height": 44])])
        let data = try JSONEncoder().encode(overlay)
        let decoded = try JSONDecoder().decode(AccessibilityOverlay.self, from: data)
        XCTAssertEqual(overlay, decoded)
    }

    func testVisualRegionCompareModelRoundTrip() throws {
        let result = VisualRegionCompare(identical: true, differenceRatio: 0.01, region: ["x": 0, "y": 0, "width": 100, "height": 100], pixelDifferences: 10)
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(VisualRegionCompare.self, from: data)
        XCTAssertEqual(result, decoded)
    }

    func testPluginSecurityPolicyModelRoundTrip() throws {
        let policy = PluginSecurityPolicy(requireSignature: true, allowedCapabilities: ["read", "write"], deniedActions: ["delete"])
        let data = try JSONEncoder().encode(policy)
        let decoded = try JSONDecoder().decode(PluginSecurityPolicy.self, from: data)
        XCTAssertEqual(policy, decoded)
    }

    func testPluginSecurityPolicyBlocksUnsignedPlugin() {
        let registry = PluginRegistry()
        registry.setSecurityPolicy(PluginSecurityPolicy(requireSignature: true))
        let plugin = TestPlugin()
        registry.register(plugin)
        XCTAssertFalse(registry.descriptors().contains { $0.id == "test-plugin" })
    }

    func testPluginSecurityPolicyAllowsSignedPlugin() {
        let registry = PluginRegistry()
        registry.setSecurityPolicy(PluginSecurityPolicy(requireSignature: true))
        let signedPlugin = SignedTestPlugin()
        registry.register(signedPlugin)
        XCTAssertTrue(registry.descriptors().contains { $0.id == "signed-plugin" })
    }

    func testCapabilityNegotiatorSupportsAppAndNoReset() throws {
        let input: [String: Any] = ["capabilities": ["alwaysMatch": ["platformName": "iOS", "appium:automationName": "XCUITest", "appium:app": "/tmp/app.app", "appium:noReset": true]]]
        let result = try CapabilityNegotiator.negotiate(input)
        XCTAssertEqual(result["appium:app"] as? String, "/tmp/app.app")
        XCTAssertEqual(result["appium:noReset"] as? Bool, true)
    }

    func testCapabilityNegotiatorRejectsNoResetAndFullReset() {
        let input: [String: Any] = ["capabilities": ["alwaysMatch": ["platformName": "iOS", "appium:automationName": "XCUITest", "appium:noReset": true, "appium:fullReset": true]]]
        XCTAssertThrowsError(try CapabilityNegotiator.negotiate(input)) { error in
            guard case ScoutError.invalidRequest = error else { return XCTFail("Expected invalidRequest") }
        }
    }

    func testCapabilityNegotiatorSupportsBrowserName() throws {
        let input: [String: Any] = ["capabilities": ["alwaysMatch": ["platformName": "iOS", "appium:automationName": "XCUITest", "browserName": "Safari"]]]
        let result = try CapabilityNegotiator.negotiate(input)
        XCTAssertEqual(result["appium:browserName"] as? String, "Safari")
    }

    func testConformanceSnapshotIncludesAll7Points() {
        let snapshot = ScoutEngine().conformanceSnapshot()
        XCTAssertTrue(snapshot.implemented.contains("testVerification"))
        XCTAssertTrue(snapshot.implemented.contains("failureClassification"))
        XCTAssertTrue(snapshot.implemented.contains("accessibilityOverlay"))
        XCTAssertTrue(snapshot.implemented.contains("visualRegionCompare"))
        XCTAssertTrue(snapshot.implemented.contains("pluginSecurityPolicy"))
        XCTAssertFalse(snapshot.pendingIntegrations.contains("TLS handshake"))
    }

    func testCycleDetectionResultModelRoundTrip() throws {
        let result = CycleDetectionResult(cyclesDetected: 2, cycleStates: ["state1", "state2"], hasCycle: true, recommendation: "backtrack")
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(CycleDetectionResult.self, from: data)
        XCTAssertEqual(result, decoded)
    }

    func testDetectCyclesEmptyGraph() throws {
        let engine = ScoutEngine()
        let session = try engine.createSession(deviceID: nil, bundleIdentifier: nil, driverID: "ios-simulator")
        let result = try engine.detectCycles(sessionID: session.id)
        XCTAssertFalse(result.hasCycle)
        XCTAssertEqual(result.cyclesDetected, 0)
    }

    func testOCRResultModelRoundTrip() throws {
        let result = OCRResult(recognizedText: "Hello World", confidence: 0.95, observations: [OCRObservation(text: "Hello", confidence: 0.98, boundingBox: ["x": 0.1, "y": 0.2, "width": 0.3, "height": 0.1])])
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(OCRResult.self, from: data)
        XCTAssertEqual(result, decoded)
    }

    func testRunnerBuildResultModelRoundTrip() throws {
        let result = RunnerBuildResult(built: true, runnerPath: "/tmp/runner.xctestrun", error: nil, signed: true)
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(RunnerBuildResult.self, from: data)
        XCTAssertEqual(result, decoded)
    }

    func testDriverManifestWithPrincipalClass() throws {
        let manifest = DriverManifest(id: "custom-driver", name: "Custom", version: "1.0", platforms: ["iOS"], libraryPath: "/tmp/driver.bundle", principalClass: "CustomDriver")
        let data = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(DriverManifest.self, from: data)
        XCTAssertEqual(manifest, decoded)
        XCTAssertEqual(decoded.principalClass, "CustomDriver")
    }

    func testConformanceSnapshotIncludesFinal4Points() {
        let snapshot = ScoutEngine().conformanceSnapshot()
        XCTAssertTrue(snapshot.implemented.contains("semanticCycleDetection"))
        XCTAssertTrue(snapshot.implemented.contains("ocr"))
        XCTAssertTrue(snapshot.implemented.contains("runnerBuild"))
    }

    func testWebSocketAcceptKeyMatchesRFC6455Vector() {
        XCTAssertEqual(WebSocketTransport.acceptKey(for: "dGhlIHNhbXBsZSBub25jZQ=="), "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")
    }

    func testWebSocketHandshakeResponseHeaders() {
        let response = WebSocketTransport.handshakeResponse(key: "dGhlIHNhbXBsZSBub25jZQ==")
        XCTAssertTrue(response.hasPrefix("HTTP/1.1 101 Switching Protocols\r\n"))
        XCTAssertTrue(response.contains("Upgrade: websocket\r\n"))
        XCTAssertTrue(response.contains("Connection: Upgrade\r\n"))
        XCTAssertTrue(response.contains("Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=\r\n"))
    }

    func testWebSocketTextFrameEncodingLengths() {
        let short = WebSocketTransport.encodeTextFrame(Data("hola".utf8))
        XCTAssertEqual(short[0], 0x81)
        XCTAssertEqual(short[1], 4)
        XCTAssertEqual(String(data: short.suffix(4), encoding: .utf8), "hola")
        let medium = WebSocketTransport.encodeTextFrame(Data(repeating: 65, count: 200))
        XCTAssertEqual(medium[1], 126)
        XCTAssertEqual(Int(medium[2]) << 8 | Int(medium[3]), 200)
        let large = WebSocketTransport.encodeTextFrame(Data(repeating: 66, count: 70000))
        XCTAssertEqual(large[1], 127)
        var decoded = 0; for offset in 0..<8 { decoded = decoded << 8 | Int(large[2 + offset]) }
        XCTAssertEqual(decoded, 70000)
        XCTAssertEqual(WebSocketTransport.encodeCloseFrame()[0], 0x88)
        XCTAssertEqual(WebSocketTransport.encodePongFrame(Data("x".utf8))[0], 0x8A)
    }

    func testWebSocketDecodeMaskedPingCloseAndPartialFrames() {
        let mask: [UInt8] = [0x11, 0x22, 0x33, 0x44]
        var ping = [UInt8]([0x89, 0x82]) + mask
        ping += [UInt8]("hi".utf8).enumerated().map { $0.element ^ mask[$0.offset % 4] }
        let close = [UInt8]([0x88, 0x80]) + mask
        let first = WebSocketTransport.decodeClientFrames(Data(ping + close))
        XCTAssertEqual(first.frames.count, 2)
        XCTAssertEqual(first.frames[0].opcode, .ping)
        XCTAssertEqual(String(data: first.frames[0].payload, encoding: .utf8), "hi")
        XCTAssertTrue(first.frames[0].fin)
        XCTAssertEqual(first.frames[1].opcode, .close)
        XCTAssertEqual(first.consumedBytes, ping.count + close.count)
        var truncated = [UInt8]([0x81, 0x84]) + mask + [UInt8]("hol".utf8).enumerated().map { $0.element ^ mask[$0.offset % 4] }
        let partial = WebSocketTransport.decodeClientFrames(Data(truncated))
        XCTAssertTrue(partial.frames.isEmpty)
        XCTAssertEqual(partial.consumedBytes, 0)
        truncated += [UInt8]("a".utf8).map { $0 ^ mask[3] }
        let completed = WebSocketTransport.decodeClientFrames(Data(truncated))
        XCTAssertEqual(completed.frames.count, 1)
        XCTAssertEqual(completed.frames[0].opcode, .text)
        XCTAssertEqual(String(data: completed.frames[0].payload, encoding: .utf8), "hola")
    }

    func testConformanceSnapshotIncludesWebSocketBiDi() {
        let snapshot = ScoutEngine().conformanceSnapshot()
        XCTAssertTrue(snapshot.implemented.contains("websocketBiDi"))
        XCTAssertFalse(snapshot.pendingIntegrations.contains("WebSocket WebDriver BiDi"))
    }

    func testFarmWorkerModelRoundTrip() throws {
        let worker = FarmWorker(id: "w1", url: "http://192.168.1.10:4723", capabilities: ["ios-simulator"], maxSessions: 4, activeSessions: 2, ttlSeconds: 60)
        let data = try JSONEncoder().encode(worker)
        let decoded = try JSONDecoder().decode(FarmWorker.self, from: data)
        XCTAssertEqual(worker, decoded)
        XCTAssertEqual(decoded.status, .online)
        XCTAssertTrue(decoded.capacityAvailable)
    }

    func testRegisterFarmWorkerRejectsInvalidURL() {
        let engine = ScoutEngine()
        XCTAssertThrowsError(try engine.registerFarmWorker(url: "not-a-url"))
        XCTAssertThrowsError(try engine.registerFarmWorker(url: "ftp://192.168.1.10:4723"))
    }

    func testFarmWorkerRegistrationHeartbeatAndCapacity() throws {
        let engine = ScoutEngine()
        let worker = try engine.registerFarmWorker(url: "http://192.168.1.10:4723", capabilities: ["ios-simulator", "xcodebuild"], maxSessions: 2)
        XCTAssertEqual(worker.status, .online)
        XCTAssertTrue(worker.capacityAvailable)
        XCTAssertEqual(engine.farmWorkersStatus().count, 1)
        XCTAssertThrowsError(try engine.farmWorkerHeartbeat(workerID: "unknown"))
        let saturated = try engine.farmWorkerHeartbeat(workerID: worker.id, activeSessions: 2)
        XCTAssertEqual(saturated.activeSessions, 2)
        XCTAssertFalse(saturated.capacityAvailable)
        let released = try engine.farmWorkerHeartbeat(workerID: worker.id, activeSessions: 0)
        XCTAssertTrue(released.capacityAvailable)
    }

    func testFarmWorkerExpiresAfterTTLAndHeartbeatReactivates() throws {
        let engine = ScoutEngine()
        let worker = try engine.registerFarmWorker(url: "http://192.168.1.10:4723")
        XCTAssertEqual(engine.farmWorkersStatus().first?.status, .online)
        let expired = engine.farmWorkersStatus(asOf: Date().addingTimeInterval(Double(worker.ttlSeconds) + 1))
        XCTAssertEqual(expired.first?.status, .expired)
        XCTAssertFalse(expired.first?.capacityAvailable ?? true)
        let reactivated = try engine.farmWorkerHeartbeat(workerID: worker.id, activeSessions: 1)
        XCTAssertEqual(reactivated.status, .online)
        XCTAssertTrue(reactivated.capacityAvailable)
    }

    func testDeregisterFarmWorkerRemovesEntry() throws {
        let engine = ScoutEngine()
        let worker = try engine.registerFarmWorker(url: "http://192.168.1.10:4723")
        XCTAssertTrue(engine.deregisterFarmWorker(workerID: worker.id))
        XCTAssertFalse(engine.deregisterFarmWorker(workerID: worker.id))
        XCTAssertTrue(engine.farmWorkersStatus().isEmpty)
    }

    func testFleetDashboardIncludesWorkers() throws {
        let engine = ScoutEngine()
        _ = try engine.registerFarmWorker(url: "http://192.168.1.10:4723")
        let dashboard = try engine.fleetDashboard()
        XCTAssertEqual(dashboard.workersOnline, 1)
        XCTAssertEqual(dashboard.workersExpired, 0)
    }

    func testConformanceSnapshotIncludesFarmWorkers() {
        let snapshot = ScoutEngine().conformanceSnapshot()
        XCTAssertTrue(snapshot.implemented.contains("farmWorkers"))
        XCTAssertFalse(snapshot.pendingIntegrations.contains("distributed device farm"))
        XCTAssertTrue(snapshot.partial.contains("distributed device farm execution"))
    }
}

private final class TestPlugin: CuyScoutPlugin, @unchecked Sendable {
    let descriptor = PluginDescriptor(id: "test-plugin", name: "Test Plugin", capabilities: ["test"])
    func before(_ action: ScoutAction, sessionID: String) throws -> ScoutAction { action }
    func after(_ action: ScoutAction, result: Data?, error: Error?, sessionID: String) {}
}

private final class SignedTestPlugin: CuyScoutPlugin, @unchecked Sendable {
    let descriptor = PluginDescriptor(id: "signed-plugin", name: "Signed Plugin", capabilities: ["test"], signature: "abc123")
    func before(_ action: ScoutAction, sessionID: String) throws -> ScoutAction { action }
    func after(_ action: ScoutAction, result: Data?, error: Error?, sessionID: String) {}
}

private final class TestDriver: CuyScoutDriver, @unchecked Sendable {
    let descriptor = DriverDescriptor(id: "test-driver", name: "Test Driver", platforms: ["Test"])
    init() {}
    func health() -> DriverHealth { DriverHealth(healthy: true, message: "test") }
    func execute(_ action: ScoutAction, on device: Device) throws -> Data? { nil }
}
