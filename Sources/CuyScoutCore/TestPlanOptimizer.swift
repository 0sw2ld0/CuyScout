import Foundation

/// Removes successful inspection calls without changing the recorded interactions.
public enum TestPlanOptimizer {
    public static func optimize(_ plan: TestPlan) -> TestPlan {
        var removed = 0
        func compact(_ action: ScoutAction) -> ScoutAction? {
            switch action {
            case .sequence(let actions):
                // Preserve an originally empty sequence so validation can report it.
                guard !actions.isEmpty else { return action }
                let children = actions.compactMap { compact($0) }
                return children.isEmpty ? nil : .sequence(children)
            case .accessibilityTree, .accessibilityTreeWithOptions, .accessibilityDiff,
                 .findElement, .findElements, .findElementFromElement, .findElementsFromElement,
                 .screenshot, .elementAttribute, .elementDisplayed, .elementEnabled,
                 .elementRect, .elementScreenshot, .elementSelected, .elementName,
                 .elementProperty, .activeElement:
                removed += 1
                return nil
            default:
                // Repeated taps, text, gestures, waits and assertions can all matter.
                return action
            }
        }
        let steps = plan.steps.compactMap { step -> TestPlanStep? in
            // A failed inspection is evidence, not disposable noise. In a failed
            // sequence the executed prefix is unknown, so preserve it in full.
            guard step.success else { return step }
            guard let action = compact(step.action) else { return nil }
            return TestPlanStep(id: step.id, action: action, success: step.success,
                                durationMilliseconds: step.durationMilliseconds)
        }
        var warnings = plan.warnings
        if removed > 0 {
            warnings.append("Optimización: se eliminaron \(removed) observaciones exitosas sin efecto en la prueba.")
        }
        return TestPlan(sessionID: plan.sessionID, steps: steps, warnings: warnings)
    }
}
