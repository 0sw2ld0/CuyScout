import XCTest
@testable import CuyScoutCore

/// Los pasos de lectura no deben invalidar un plan; un paso que actúa y falló, o una acción no exportable, sí.
final class PlanValidationTests: XCTestCase {
    private let field = ScoutSelector(strategy: .accessibilityIdentifier, value: "amount")
    private func plan(_ steps: [(ScoutAction, Bool)]) -> TestPlan {
        TestPlan(sessionID: "s", steps: steps.enumerated().map { TestPlanStep(id: "step-\($0.offset)", action: $0.element.0, success: $0.element.1, durationMilliseconds: 1) }, warnings: [])
    }
    func testFailedReadingsAreExplorationNoiseButFailedActionsAreErrors() {
        let noisy = TestPlanValidator.validate(plan([(.tapElement(field), true), (.accessibilityTreeWithOptions(AccessibilityOptions()), false), (.findElement(field), false)]))
        XCTAssertTrue(noisy.valid, noisy.errors.joined(separator: "\n"))
        XCTAssertTrue(noisy.executable)
        XCTAssertEqual(noisy.warnings.filter { $0.contains("lectura fallida") }.count, 2)
        let broken = TestPlanValidator.validate(plan([(.tapElement(field), false)]))
        XCTAssertFalse(broken.valid)
        XCTAssertTrue(broken.errors.contains { $0.contains("terminó con error") })
    }
    func testFailedAttemptsTheAgentMovedPastDoNotBlockThePlan() {
        let transfer = ScoutSelector(strategy: .label, value: "Transferir")
        let card = ScoutSelector(strategy: .accessibilityIdentifier, value: "card.action")
        let result = TestPlanValidator.validate(plan([(.tapElement(transfer), false), (.tapElement(card), true), (.assertVisible(field), true)]))
        XCTAssertTrue(result.valid, result.errors.joined(separator: "\n"))
        XCTAssertTrue(result.executable)
        XCTAssertTrue(result.warnings.contains { $0.contains("step-0") && $0.contains("intento fallido") })
        XCTAssertFalse(result.warnings.contains { $0.contains("pasos fallidos y requiere revisión") })
        // Sin nada que funcione después, el resultado de la acción es incierto: sigue siendo un error.
        XCTAssertFalse(TestPlanValidator.validate(plan([(.tapElement(card), true), (.tapElement(transfer), false), (.screenshot, true)])).valid)
        // Una secuencia fallida deja el prefijo ejecutado sin saber.
        XCTAssertFalse(TestPlanValidator.validate(plan([(.sequence([.tapElement(card), .tapElement(transfer)]), false), (.tapElement(card), true)])).valid)
    }
    func testAPlanWithoutAssertionsWarnsThatGreenDoesNotProveTheResult() {
        let without = TestPlanValidator.validate(plan([(.tapElement(field), true), (.screenshot, true)]))
        XCTAssertTrue(without.valid)
        XCTAssertTrue(without.warnings.contains { $0.contains("ninguna aserción") })
        let with = TestPlanValidator.validate(plan([(.tapElement(field), true), (.sequence([.assertVisible(field)]), true)]))
        XCTAssertFalse(with.warnings.contains { $0.contains("ninguna aserción") })
    }
    func testReadingsDoNotBlockExecutableButNonExportableActionsStillDo() {
        XCTAssertTrue(TestPlanValidator.validate(plan([(.tapElement(field), true), (.screenshot, true), (.accessibilityTree, true)])).executable)
        let shake = TestPlanValidator.validate(plan([(.tapElement(field), true), (.shake, true)]))
        XCTAssertFalse(shake.executable)
        XCTAssertTrue(shake.warnings.contains { $0.contains("no exportables") })
    }
    func testFuzzyLabelSelectorsWarnThatTheyAreNotExportedToAppium() {
        let result = TestPlanValidator.validate(plan([(.tapElement(ScoutSelector(strategy: .labelStartsWith, value: "Cuenta Sueldo")), true)]))
        XCTAssertTrue(result.valid)
        XCTAssertTrue(result.warnings.contains { $0.contains("labelStartsWith") && $0.contains("Appium") })
    }
    func testMaestroExportTranslatesPrefixAndFragmentToRegex() {
        let actions: [ScoutAction] = [.tapElement(ScoutSelector(strategy: .labelStartsWith, value: "Cuenta Sueldo")), .tapElement(ScoutSelector(strategy: .labelContains, value: "2046"))]
        let steps = actions.enumerated().map { RecordedStep(index: $0.offset, action: $0.element, startedAt: Date(), durationMilliseconds: 1, success: true) }
        let flow = MaestroFlowExporter.make(steps: steps, appID: "com.example.app")
        XCTAssertTrue(flow.contains("- tapOn: \"Cuenta Sueldo.*\""), flow)
        XCTAssertTrue(flow.contains("- tapOn: \".*2046.*\""), flow)
    }
}
