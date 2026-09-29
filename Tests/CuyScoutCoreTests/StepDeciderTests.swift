import XCTest
@testable import CuyScoutCore

private struct FakeModel: DecisionModel {
    var choice: String
    var confidence: Double
    var fails = false
    func choose(state: String, options: [String: String]) throws -> (choice: String, confidence: Double) {
        if fails { throw ScoutError.commandFailed("sin conexión") }
        return (choice, confidence)
    }
}

private func observation(_ actions: [ScoutAction], texts: [String] = []) -> AgentObservation {
    AgentObservation(context: "NATIVE_APP", url: "", title: "", stateId: "state:test", changed: true,
                     actions: actions.map { ActionSuggestion(action: $0, reason: "test") }, texts: texts, exploration: nil)
}

private func tap(_ value: String, _ strategy: ScoutSelector.Strategy = .accessibilityIdentifier) -> ScoutAction { .tapElement(ScoutSelector(strategy: strategy, value: value)) }
private func type(_ value: String) -> ScoutAction { .typeElement(ScoutSelector(strategy: .accessibilityIdentifier, value: value), text: "<text>") }

final class StepDeciderTests: XCTestCase {
    func testSingleOptionOfTheIntentIsChosenWithoutAskingLaya() throws {
        let screen = observation([type("input_email"), tap("btn_login")])
        let result = try StepDecider(model: FakeModel(choice: "a0", confidence: 0.99)).decide(DecideRequest(step: "Tocar iniciar sesión", intent: "tocar"), observation: screen)
        XCTAssertEqual(result.decision, "chosen")
        XCTAssertEqual(result.engine, "single_option")
        XCTAssertEqual(result.candidate?.action, tap("btn_login"))
    }

    func testNamedValueIsMatchedDeterministicallyEvenWithATypo() throws {
        let screen = observation([tap("Cuenta Ahorros", .label), tap("Cuywallet Soles", .label)])
        let result = try StepDecider(model: FakeModel(choice: "a0", confidence: 0.99)).decide(DecideRequest(step: "Seleccionar origen", intent: "seleccionar", options: ["cuywaller"]), observation: screen)
        XCTAssertEqual(result.engine, "match")
        XCTAssertEqual(result.candidate?.action, tap("Cuywallet Soles", .label))
    }

    func testNamedValueNotOnScreenIsNeverGuessedByLaya() throws {
        let screen = observation([tap("Cuenta Ahorros", .label), tap("Cuenta Sueldo", .label)])
        let result = try StepDecider(model: FakeModel(choice: "a0", confidence: 0.99)).decide(DecideRequest(step: "Seleccionar origen", intent: "seleccionar", options: ["Cuywallet"]), observation: screen)
        XCTAssertEqual(result.decision, "needs_llm")
        XCTAssertEqual(result.reason, "named_value_not_on_screen")
        XCTAssertEqual(result.candidates.count, 2)
    }

    func testLayaDecidesAboveThresholdAndDefersBelowIt() throws {
        let screen = observation([tap("btn_transfer"), tap("btn_pay"), tap("tab.home")])
        let request = DecideRequest(step: "Ir a transferir", intent: "tocar")
        let confident = try StepDecider(model: FakeModel(choice: "a0", confidence: 0.8)).decide(request, observation: screen)
        XCTAssertEqual(confident.engine, "laya")
        XCTAssertEqual(confident.candidate?.action, tap("btn_transfer"))
        XCTAssertEqual(confident.candidates.count, 2, "la navegación global no es candidata")
        let unsure = try StepDecider(model: FakeModel(choice: "a0", confidence: 0.2)).decide(request, observation: screen)
        XCTAssertEqual(unsure.decision, "needs_llm")
        XCTAssertEqual(unsure.reason, "low_confidence")
    }

    func testIrreversibleStepsRequireMoreConfidence() throws {
        let screen = observation([tap("btn_confirm"), tap("btn_cancel")])
        let result = try StepDecider(model: FakeModel(choice: "a0", confidence: 0.5)).decide(DecideRequest(step: "Confirmar la transferencia", intent: "confirmar"), observation: screen)
        XCTAssertEqual(result.decision, "needs_llm")
    }

    func testAvoidedValuesAreFilteredBeforeAskingLaya() throws {
        let screen = observation([tap("Cuenta Corriente ****1234", .label), tap("Wallet Digital CUY", .label)])
        let result = try StepDecider(model: FakeModel(choice: "a1", confidence: 0.99)).decide(DecideRequest(step: "Seleccionar un destino distinto del origen", intent: "seleccionar", avoid: ["Wallet Digital CUY"]), observation: screen)
        XCTAssertEqual(result.engine, "single_option")
        XCTAssertEqual(result.candidate?.action, tap("Cuenta Corriente ****1234", .label))
    }

    func testExcludedControlsAreNotProposedAgain() throws {
        let screen = observation([tap("btn_next"), tap("btn_back")])
        let result = try StepDecider(model: FakeModel(choice: "a0", confidence: 0.99)).decide(DecideRequest(step: "Continuar", exclude: ["btn_next"]), observation: screen)
        XCTAssertEqual(result.engine, "single_option")
        XCTAssertEqual(result.candidate?.action, tap("btn_back"))
    }

    func testSystemAlertIsReportedAsInterruption() throws {
        let screen = observation([tap("Guardar contraseña", .label), tap("Ahora no", .label)], texts: ["¿Guardar contraseña?"])
        let result = try StepDecider(model: FakeModel(choice: "a1", confidence: 0.9)).decide(DecideRequest(step: "Tocar transferir"), observation: screen)
        XCTAssertTrue(result.interruption)
        XCTAssertEqual(result.candidate?.action, tap("Ahora no", .label))
    }

    func testUnavailableLayaDefersToTheLLMInsteadOfFailing() throws {
        let screen = observation([tap("btn_a"), tap("btn_b")])
        let result = try StepDecider(model: FakeModel(choice: "a0", confidence: 1, fails: true)).decide(DecideRequest(step: "Tocar algo"), observation: screen)
        XCTAssertEqual(result.decision, "needs_llm")
        XCTAssertTrue(result.reason.hasPrefix("laya_unavailable"))
    }

    func testRejectsVerifyIntent() {
        XCTAssertThrowsError(try StepDecider.intent("verificar"))
        XCTAssertEqual(try StepDecider.intent("type"), .type)
    }

    func testCandidateLabelsReadLikeTheScreen() {
        let labels = StepDecider.candidates(from: observation([tap("btn_login"), type("input_email")], texts: ["btn_login: Iniciar sesión"])).map(\.label)
        XCTAssertEqual(labels, ["tocar botón login (Iniciar sesión)", "escribir en campo email"])
    }
}

final class LayaSwitchTests: XCTestCase {
    func testDisabledByDefault() {
        let laya = LayaSwitch(environment: [:])
        XCTAssertFalse(laya.settings.enabled)
        XCTAssertEqual(laya.settings.url, "http://127.0.0.1:8791")
        XCTAssertNil(laya.activeModel())
        XCTAssertNil(DecisionEngineInfo.current(laya))
    }

    func testEnablesFromConfigurationAndAtRuntime() throws {
        XCTAssertTrue(LayaSwitch(environment: ["CUYSCOUT_LAYA_ENABLED": "true"]).settings.enabled)
        let laya = LayaSwitch(environment: [:])
        try laya.update(enabled: true, url: "http://10.0.0.5:9000/")
        XCTAssertEqual(laya.settings, LayaSettings(enabled: true, url: "http://10.0.0.5:9000"))
        XCTAssertNotNil(laya.activeModel())
        XCTAssertEqual(DecisionEngineInfo.current(laya)?.endpoint, "POST /session/:id/decide")
        XCTAssertThrowsError(try laya.update(enabled: nil, url: "10.0.0.5:9000"))
    }

    func testDoctorReportsDisabledAsOptional() {
        XCTAssertTrue(LayaService.check(url: LayaService.defaultURL, enabled: false).detail.contains("Desactivado"))
    }
}
