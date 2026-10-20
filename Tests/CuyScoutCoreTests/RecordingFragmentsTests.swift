import XCTest
@testable import CuyScoutCore

/// Fragmentos creados desde una grabación guardada: sin sesión, con los valores locales y las credenciales.
final class RecordingFragmentsTests: XCTestCase {
    private func label(_ value: String) -> [String: Any] { ["strategy": "label", "value": value] }
    private func step(_ index: Int, _ action: [String: Any], success: Bool = true, error: String? = nil) -> [String: Any] {
        var step: [String: Any] = ["index": index, "action": action, "success": success, "durationMilliseconds": 120, "startedAt": 814201358.5]
        if let error { step["error"] = error }
        return step
    }
    /// Misma forma que `output/<escenario>.cuyscout.json`: recording.steps, session.device.platform y session.bundleIdentifier.
    private func makeProject() throws -> (root: URL, artifact: URL, values: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("rec-frag-\(UUID().uuidString)")
        for dir in ["output", "fixtures/replay-values"] { try FileManager.default.createDirectory(at: root.appendingPathComponent(dir), withIntermediateDirectories: true) }
        try Data("# agentes".utf8).write(to: root.appendingPathComponent("AGENTS.md"))
        let steps: [[String: Any]] = [
            step(0, ["type": "accessibilityTreeWithOptions", "options": ["visibleOnly": true]]),
            step(1, ["type": "tap", "x": 192, "y": 757.9], success: false, error: "No se pudo tocar el elemento"),
            step(2, ["type": "tapElement", "selector": label("Ingresar con Clave de Internet")]),
            step(3, ["type": "typeElement", "selector": ["strategy": "accessibilityIdentifier", "value": "bcp-input-1"], "text": "<redacted>"]),
            step(4, ["type": "tapElement", "selector": label("Continuar")]),
            step(5, ["type": "assertVisible", "selector": label("Transferir")]),
            step(6, ["type": "tapElement", "selector": label("Transferir")]),
            step(7, ["type": "typeElement", "selector": ["strategy": "accessibilityIdentifier", "value": "amount-input.input"], "text": "<redacted>"]),
        ]
        let artifact: [String: Any] = ["recording": ["steps": steps, "sessionID": "x"], "session": ["bundleIdentifier": "com.example.bank", "device": ["platform": "android"]]]
        let artifactURL = root.appendingPathComponent("output/transferencia.cuyscout.json")
        try JSONSerialization.data(withJSONObject: artifact).write(to: artifactURL)
        let valuesURL = root.appendingPathComponent("fixtures/replay-values/transferencia.json")
        try JSONSerialization.data(withJSONObject: ["3.text": "android-secret-1", "7.text": "10.00"]).write(to: valuesURL)
        try JSONSerialization.data(withJSONObject: ["demo_user": ["password_android": "android-secret-1"]]).write(to: root.appendingPathComponent("fixtures/credentials.test.json"))
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return (root, artifactURL, valuesURL)
    }
    private let exit = SessionFragment.Check(selector: .init(strategy: .label, value: "Transferir"))

    func testLoadReadsStepsPlatformBundleAndLocalValues() throws {
        let p = try makeProject()
        let source = try RecordingFragments.load(name: "transferencia", artifact: p.artifact, replayValues: p.values)
        XCTAssertEqual(source.platform, .android); XCTAssertEqual(source.bundleIdentifier, "com.example.bank")
        XCTAssertEqual(source.steps.map(\.index), Array(0...7)); XCTAssertEqual(source.replayValues["3.text"], "android-secret-1")
        XCTAssertTrue(try RecordingFragments.load(name: "x", artifact: p.artifact, replayValues: nil).replayValues.isEmpty)
        XCTAssertThrowsError(try RecordingFragments.load(name: "x", artifact: p.root.appendingPathComponent("AGENTS.md"), replayValues: nil))
    }

    func testEligibilityAndSummariesNeverShowTypedText() throws {
        let p = try makeProject()
        let source = try RecordingFragments.load(name: "transferencia", artifact: p.artifact, replayValues: p.values)
        let kinds = source.steps.map { RecordingFragments.eligibility(of: $0) }
        XCTAssertEqual(kinds, [.reading, .failed, .eligible, .eligible, .eligible, .assertion, .eligible, .eligible])
        let summaries = source.steps.map { RecordingFragments.summary(of: $0.action) }
        XCTAssertEqual(summaries[2], "Tocar «Ingresar con Clave de Internet»"); XCTAssertEqual(summaries[3], "Escribir en «bcp-input-1»")
        XCTAssertEqual(summaries[1], "Tocar por coordenadas (192, 757)")
        XCTAssertFalse(summaries.joined().contains("android-secret"))
    }

    func testCredentialMatchTellsWhichFieldAStepTypes() throws {
        let p = try makeProject()
        let source = try RecordingFragments.load(name: "transferencia", artifact: p.artifact, replayValues: p.values)
        let credentials = try FragmentStore.credentials(in: p.root)
        XCTAssertEqual(RecordingFragments.credentialMatch(for: source.steps[3], in: source, credentials: credentials), "password_android (demo_user)")
        XCTAssertNil(RecordingFragments.credentialMatch(for: source.steps[7], in: source, credentials: credentials), "el monto no es una credencial")
        XCTAssertNil(RecordingFragments.credentialMatch(for: source.steps[2], in: source, credentials: credentials), "un toque no escribe nada")
    }

    func testSavingALoginFragmentKeepsOnlyGoodStepsAndNeverTheSecret() throws {
        let p = try makeProject()
        let source = try RecordingFragments.load(name: "transferencia", artifact: p.artifact, replayValues: p.values)
        let result = try RecordingFragments.save(source: source, selecting: [0, 1, 2, 3, 4, 5], name: "login", exitCheck: exit, in: p.root)
        XCTAssertEqual(result.steps, 3, "solo los pasos que actúan y salieron bien")
        XCTAssertEqual(result.dropped, 3, "la lectura, el paso fallido y la aserción")
        XCTAssertEqual(result.credentialFields, ["password_android"])
        XCTAssertEqual(result.path, "fragments/login.android.json")
        let fragment = try FragmentStore.load(name: "login", platform: .android, in: p.root)
        XCTAssertEqual(fragment.bundleIdentifier, "com.example.bank"); XCTAssertEqual(fragment.defaultAlias, "demo_user")
        XCTAssertEqual(fragment.variables, ["1.text": "password_android"], "índice relativo al fragmento, no a la grabación")
        let raw = try String(contentsOf: p.root.appendingPathComponent(result.path), encoding: .utf8)
        XCTAssertFalse(raw.contains("android-secret-1")); XCTAssertTrue(raw.contains("<redacted>"))
    }

    func testStepsOutsideTheCredentialsAreRefusedUnlessAllowedAndNotSecret() throws {
        let p = try makeProject()
        let source = try RecordingFragments.load(name: "transferencia", artifact: p.artifact, replayValues: p.values)
        XCTAssertThrowsError(try RecordingFragments.save(source: source, selecting: [6, 7], name: "monto", exitCheck: exit, in: p.root)) {
            XCTAssertTrue("\($0)".contains("paso 2") && "\($0)".contains("credentials.test.json"), "\($0)")
            XCTAssertFalse("\($0)".contains("10.00"))
        }
        XCTAssertNoThrow(try RecordingFragments.save(source: source, selecting: [6, 7], name: "monto", exitCheck: exit, in: p.root, allowLiteral: true))
    }

    func testMissingLocalValuesNoEligibleStepsAndBadNamesAreExplained() throws {
        let p = try makeProject()
        let noValues = try RecordingFragments.load(name: "transferencia", artifact: p.artifact, replayValues: nil)
        XCTAssertThrowsError(try RecordingFragments.save(source: noValues, selecting: [2, 3], name: "login", exitCheck: exit, in: p.root)) {
            XCTAssertTrue("\($0)".contains("replay-values") && "\($0)".contains("paso 4"), "\($0)")
        }
        let source = try RecordingFragments.load(name: "transferencia", artifact: p.artifact, replayValues: p.values)
        XCTAssertThrowsError(try RecordingFragments.save(source: source, selecting: [0, 1, 5], name: "login", exitCheck: exit, in: p.root)) { XCTAssertTrue("\($0)".contains("No hay pasos que guardar")) }
        XCTAssertThrowsError(try RecordingFragments.save(source: source, selecting: [2], name: "../mal", exitCheck: exit, in: p.root))
        _ = try RecordingFragments.save(source: source, selecting: [2], name: "uno", exitCheck: exit, in: p.root)
        XCTAssertThrowsError(try RecordingFragments.save(source: source, selecting: [2], name: "uno", exitCheck: exit, in: p.root)) { XCTAssertTrue("\($0)".contains("overwrite")) }
    }

    func testLiveValidationUsesTheCurrentRulesAndTheLocalValues() throws {
        let p = try makeProject()
        let source = try RecordingFragments.load(name: "transferencia", artifact: p.artifact, replayValues: p.values)
        // El paso 0 es una lectura y el 1 un toque por coordenadas que falló: la lectura no invalida; el toque fallido sí avisa.
        let result = RecordingFragments.validation(of: source)
        XCTAssertFalse(result.valid, "un paso que actúa y falló sigue siendo un error")
        XCTAssertTrue(result.errors.contains { $0.contains("step-2") })
        XCTAssertFalse(result.errors.contains { $0.contains("step-1:") }, "la lectura no es un error")
        XCTAssertFalse(result.warnings.contains { $0.contains("placeholder") }, "con los valores locales no queda ningún placeholder")
        let onlyReadingFailed = RecordingFragments.Source(name: "x", platform: .android, bundleIdentifier: nil, steps: [
            RecordedStep(index: 0, action: .accessibilityTree, startedAt: Date(), durationMilliseconds: 1, success: false),
            RecordedStep(index: 1, action: .tapElement(.init(strategy: .accessibilityIdentifier, value: "ok")), startedAt: Date(), durationMilliseconds: 1, success: true)
        ], replayValues: [:])
        let clean = RecordingFragments.validation(of: onlyReadingFailed)
        XCTAssertTrue(clean.valid && clean.executable, "\(clean)")
        XCTAssertFalse(clean.warnings.contains { $0.contains("pasos fallidos") }, "una lectura fallida no pide revisar el plan")
        XCTAssertTrue(clean.warnings.contains { $0.contains("lectura fallida") })
        let noValues = try RecordingFragments.load(name: "transferencia", artifact: p.artifact, replayValues: nil)
        XCTAssertTrue(RecordingFragments.validation(of: noValues).warnings.contains { $0.contains("placeholder") }, "sin valores el aviso sigue siendo correcto")
    }

    func testErrorsAreExplainedInPlainLanguage() {
        let busy = "runner_busy: el runner no respondió a tiempo (la app puede estar procesando o no quedar quieta). El comando se canceló y no se ejecutará tarde"
        XCTAssertEqual(RecordingFragments.humanize(error: busy), "el runner no respondió a tiempo")
        XCTAssertEqual(RecordingFragments.humanize(error: "No se pudo tocar el elemento"), "no se pudo tocar el elemento")
        XCTAssertEqual(RecordingFragments.humanize(error: "not_visible: el elemento está oculto, tapado o deshabilitado"), "el elemento estaba oculto o tapado")
        XCTAssertEqual(RecordingFragments.humanize(error: "No se encontró el elemento"), "el elemento no existía en esa pantalla")
        XCTAssertEqual(RecordingFragments.humanize(error: "Algo raro pasó. Segunda frase"), "algo raro pasó")
        XCTAssertTrue(RecordingFragments.humanize(error: String(repeating: "x", count: 300))!.hasSuffix("…"))
        XCTAssertNil(RecordingFragments.humanize(error: nil)); XCTAssertNil(RecordingFragments.humanize(error: "  "))
    }

    func testEveryStepThatDoesNotEnterSaysWhyWithItsRealReason() {
        func step(_ action: ScoutAction, success: Bool = true, error: String? = nil) -> RecordedStep { RecordedStep(index: 0, action: action, startedAt: Date(), durationMilliseconds: 1, success: success, error: error) }
        let failedTap = RecordingFragments.explanation(for: step(.tap(x: 192, y: 757), success: false, error: "No se pudo tocar el elemento"))
        XCTAssertEqual(failedTap, "Falló cuando se ejecutó (no se pudo tocar el elemento). No hizo nada, así que no entra: repetirlo volvería a fallar.")
        let failedRead = RecordingFragments.explanation(for: step(.accessibilityTree, success: false, error: "runner_busy: x"))
        XCTAssertEqual(failedRead, "Falló al leer la pantalla (el runner no respondió a tiempo). No cambió nada, así que no entra.")
        XCTAssertTrue(RecordingFragments.explanation(for: step(.tap(x: 1, y: 1), success: false))!.hasPrefix("Falló cuando se ejecutó."), "sin motivo guardado no inventa uno")
        XCTAssertEqual(RecordingFragments.explanation(for: step(.accessibilityTree)), "Solo lee la pantalla y no cambia nada: no entra.")
        XCTAssertTrue(RecordingFragments.explanation(for: step(.assertVisible(.init(strategy: .label, value: "x"))))!.contains("resultado del escenario"))
        XCTAssertTrue(RecordingFragments.explanation(for: step(.runFragment(name: "login", alias: nil)))!.contains("otro fragmento"))
        XCTAssertNil(RecordingFragments.explanation(for: step(.tapElement(.init(strategy: .label, value: "x")))), "un paso que puede entrar no lleva explicación")
        XCTAssertFalse([failedTap, failedRead].compactMap { $0 }.joined().contains("al grabarse"))
    }

    /// El artefacto real de un proyecto (si existe en esta Mac) se decodifica con el mismo código.
    func testARealProjectArtifactDecodesWhenAvailable() throws {
        let root = URL(fileURLWithPath: "/Users/oswaldoleon/Documents/cuycoders/workspace/BMO-Demo")
        let artifact = root.appendingPathComponent("output/transferencia-cuentas-propias-10-soles.cuyscout.json")
        guard FileManager.default.fileExists(atPath: artifact.path) else { throw XCTSkip("Sin el proyecto BMO-Demo en esta Mac") }
        let source = try RecordingFragments.load(name: "x", artifact: artifact, replayValues: root.appendingPathComponent("fixtures/replay-values/transferencia-cuentas-propias-10-soles.json"))
        XCTAssertGreaterThan(source.steps.count, 10); XCTAssertEqual(source.platform, .android)
        XCTAssertTrue(source.steps.contains { RecordingFragments.eligibility(of: $0) == .eligible })
    }
}
