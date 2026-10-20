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
