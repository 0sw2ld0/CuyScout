import XCTest
@testable import CuyScoutCore

/// Funciones tomadas de Maestro: espera a que la app quede quieta, toque repetido si no
/// cambió nada, historial de estabilidad y export a YAML de Maestro.
final class MaestroInspiredTests: XCTestCase {
    private func step(_ index: Int, _ action: ScoutAction, success: Bool = true) -> RecordedStep {
        RecordedStep(index: index, action: action, startedAt: Date(), durationMilliseconds: 10, success: success)
    }

    func testMaestroExportTranslatesStepsAndHidesTypedValues() {
        let yaml = MaestroFlowExporter.make(steps: [
            step(0, .launch(bundleIdentifier: "com.example.app")),
            step(1, .accessibilityTreeWithOptions(AccessibilityOptions())),
            step(2, .tapElement(.init(strategy: .label, value: "Ingresar (1)"))),
            step(3, .tapElement(.init(strategy: .accessibilityIdentifier, value: "missing")), success: false),
            step(4, .typeElement(.init(strategy: .accessibilityIdentifier, value: "email"), text: "<redacted>")),
            step(5, .tap(x: 120.4, y: 300.6)),
            step(6, .waitFor(.init(strategy: .label, value: "Inicio"), timeout: 5)),
            step(7, .assertText(.init(strategy: .accessibilityIdentifier, value: "saldo"), expected: "<redacted>")),
            step(8, .tapElement(.init(strategy: .predicate, value: "label BEGINSWITH 'x'"))),
        ], appID: "com.example.app")
        XCTAssertTrue(yaml.contains("appId: \"com.example.app\"\n"))
        XCTAssertTrue(yaml.contains("---\n- launchApp\n"))
        XCTAssertTrue(yaml.contains("- tapOn: \"Ingresar \\\\(1\\\\)\"\n"), yaml)
        XCTAssertFalse(yaml.contains("missing"), "los intentos fallidos se saltan")
        XCTAssertTrue(yaml.contains("- tapOn:\n    id: \"email\"\n- inputText: ${PASO_4_TEXT}\n- hideKeyboard\n"), yaml)
        XCTAssertTrue(yaml.contains("- tapOn:\n    point: \"120,301\"\n"))
        XCTAssertTrue(yaml.contains("- extendedWaitUntil:\n    visible:\n        text: \"Inicio\"\n    timeout: 5000\n"), yaml)
        XCTAssertTrue(yaml.contains("    id: \"saldo\"\n    text: ${PASO_7_EXPECTED}\n"))
        XCTAssertTrue(yaml.contains("# Selector predicate sin equivalente en Maestro"))
        XCTAssertTrue(yaml.contains("# Variables requeridas: -e PASO_4_TEXT=... -e PASO_7_EXPECTED=..."))
        XCTAssertFalse(yaml.contains("<redacted>"))
    }

    func testMaestroExportStartsByLaunchingTheApp() {
        let yaml = MaestroFlowExporter.make(steps: [step(0, .tapElement(.init(strategy: .accessibilityIdentifier, value: "ok")))], appID: "com.example.app")
        XCTAssertTrue(yaml.contains("---\n- launchApp\n- tapOn:\n    id: \"ok\"\n"), yaml)
    }

    func testMaestroExportQuotesYAMLStrings() {
        XCTAssertEqual(MaestroFlowExporter.quote("a \"b\"\\\n"), "\"a \\\"b\\\"\\\\\\n\"")
        XCTAssertEqual(MaestroFlowExporter.regexEscaped("S/ 10.00?"), "S/ 10\\.00\\?")
    }

    func testReplayHistoryLabelsStability() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("historial-\(UUID().uuidString).json")
        let original = ReplayHistory.file
        ReplayHistory.file = file
        defer { ReplayHistory.file = original; try? FileManager.default.removeItem(at: file) }
        XCTAssertEqual(ReplayHistory.record(id: "a", success: true, failedStep: nil).label, "nueva")
        XCTAssertEqual(ReplayHistory.record(id: "a", success: true, failedStep: nil).label, "estable")
        let flaky = ReplayHistory.record(id: "a", success: false, failedStep: 3)
        XCTAssertEqual(flaky.label, "inestable")
        XCTAssertEqual(flaky.runs, 3); XCTAssertEqual(flaky.passes, 2)
        XCTAssertEqual(ReplayHistory.record(id: "b", success: false, failedStep: 1).label, "nueva")
        XCTAssertEqual(ReplayHistory.record(id: "b", success: false, failedStep: 1).label, "falla siempre")
        for _ in 0..<12 { ReplayHistory.record(id: "a", success: true, failedStep: nil) }
        XCTAssertEqual(ReplayHistory.record(id: "a", success: true, failedStep: nil).label, "estable", "solo cuentan las últimas \(ReplayHistory.keep)")
    }

    /// Replay de un toque contra un runner falso. `treeChangesAfterTap` decide si el toque
    /// cambió la pantalla. Devuelve cuántas veces llegó el toque al runner.
    private func replayTap(treeChangesAfterTap: Bool) throws -> (taps: Int, result: ReplayResult) {
        // El runner responde `screenStatic` (dos capturas iguales): no hace falta el respaldo por jerarquía.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("maestro-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let history = root.appendingPathComponent("historial.json")
        let (timeout, checks, wait, file) = (ScoutEngine.settleTimeout, ScoutEngine.settleHierarchyChecks, ScoutEngine.replayElementWait, ReplayHistory.file)
        ScoutEngine.settleTimeout = 2; ScoutEngine.settleHierarchyChecks = 3; ReplayHistory.file = history
        defer { ScoutEngine.settleTimeout = timeout; ScoutEngine.settleHierarchyChecks = checks; ScoutEngine.replayElementWait = wait; ReplayHistory.file = file }

        let engine = ScoutEngine(artifactStore: ArtifactStore(directory: root))
        let session = try engine.createSession(deviceID: nil, bundleIdentifier: "com.example.test")
        try engine.registerBridge(sessionID: session.id)
        _ = try engine.pollBridge(sessionID: session.id)
        final class Runner: @unchecked Sendable { let lock = NSLock(); var taps = 0; var staticChecks = 0; var replaying = false; var stop = false }
        let state = Runner()
        let lock = state.lock
        let runner = Thread {
            while true {
                lock.lock(); let done = state.stop; lock.unlock()
                if done { return }
                guard let command = try? engine.pollBridge(sessionID: session.id) else { Thread.sleep(forTimeInterval: 0.005); continue }
                var payload = Data()
                lock.lock()
                switch command.action {
                case .screenStatic: state.staticChecks += 1; payload = Data("{\"static\":true}".utf8)
                case .tapElement: if state.replaying { state.taps += 1 }
                case .accessibilityTreeWithOptions:
                    let screen = treeChangesAfterTap && state.taps > 0 ? "Inicio" : "Bienvenida"
                    payload = Data("{\"elements\":[{\"type\":\"staticText\",\"label\":\"\(screen)\"}]}".utf8)
                default: break
                }
                lock.unlock()
                try? engine.completeBridge(sessionID: session.id, result: BridgeResult(commandID: command.id, success: true, payloadBase64: payload.base64EncodedString()))
            }
        }
        runner.start()
        defer { lock.lock(); state.stop = true; lock.unlock() }
        try engine.startRecording(sessionID: session.id)
        _ = try engine.perform(.tapElement(.init(strategy: .label, value: "Ingresar")), sessionID: session.id)
        _ = try engine.stopRecording(sessionID: session.id)
        lock.lock(); state.replaying = true; lock.unlock()
        let result = try engine.replayRecording(sessionID: session.id)
        lock.lock(); defer { lock.unlock() }
        XCTAssertGreaterThan(state.staticChecks, 0, "screenStatic debe llegar al runner")
        return (state.taps, result)
    }

    func testReplayRepeatsTapWhenScreenDidNotChange() throws {
        let (taps, result) = try replayTap(treeChangesAfterTap: false)
        XCTAssertTrue(result.success, result.error ?? "")
        XCTAssertEqual(taps, 2, "como retryTapIfNoChange de Maestro")
        XCTAssertEqual(result.stability, "nueva")
    }

    func testReplayTapsOnceWhenScreenChanged() throws {
        let (taps, result) = try replayTap(treeChangesAfterTap: true)
        XCTAssertTrue(result.success, result.error ?? "")
        XCTAssertEqual(taps, 1)
    }
}
