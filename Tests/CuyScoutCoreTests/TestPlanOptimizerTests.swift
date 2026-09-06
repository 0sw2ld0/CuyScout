import XCTest
@testable import CuyScoutCore

final class TestPlanOptimizerTests: XCTestCase {
    private let selector = ScoutSelector(strategy: .accessibilityIdentifier, value: "continue")

    private func plan(_ actions: [ScoutAction]) -> TestPlan {
        TestPlan(sessionID: "fixture", steps: actions.enumerated().map {
            TestPlanStep(id: "step-\($0.offset + 1)", action: $0.element, success: true, durationMilliseconds: 10)
        }, warnings: [])
    }

    func testRepeatedInteractionsAreNotDiscarded() {
        let actions: [ScoutAction] = [.tapElement(selector), .tapElement(selector),
                                     .type("1"), .type("1"), .navigateBack, .navigateBack]
        XCTAssertEqual(TestPlanOptimizer.optimize(plan(actions)).steps.map(\.action), actions)
    }

    func testGesturesAndSubmissionSurviveOptimization() {
        let actions: [ScoutAction] = [.submit(selector), .doubleTap(selector),
                                     .longPress(selector, duration: 2),
                                     .waitFor(selector, timeout: 5), .assertVisible(selector)]
        XCTAssertEqual(TestPlanOptimizer.optimize(plan(actions)).steps.map(\.action), actions)
    }

    func testRemovesNestedObservationsAndPreservesOriginalStepIDs() {
        let original = plan([.screenshot, .sequence([.accessibilityTree,
            .sequence([.findElement(selector), .tapElement(selector)]), .type("1")])])
        let result = TestPlanOptimizer.optimize(original)
        XCTAssertEqual(result.steps.map(\.id), ["step-2"])
        XCTAssertEqual(result.steps.first?.action, .sequence([.sequence([.tapElement(selector)]), .type("1")]))
        XCTAssertEqual(result.steps.first?.durationMilliseconds, 10)
        XCTAssertTrue(result.warnings.contains { $0.contains("3 observaciones") })
        XCTAssertEqual(TestPlanOptimizer.optimize(result), result)
    }

    func testFailedObservationsAndSequencesRemainReviewable() {
        let steps = [ScoutAction.findElement(selector), .sequence([.screenshot, .tapElement(selector)])].enumerated().map {
            TestPlanStep(id: "failed-\($0.offset)", action: $0.element, success: false, durationMilliseconds: 20)
        }
        let original = TestPlan(sessionID: "fixture", steps: steps, warnings: ["Revisar fallos"])
        XCTAssertEqual(TestPlanOptimizer.optimize(original), original)
        XCTAssertFalse(TestPlanValidator.validate(TestPlanOptimizer.optimize(original)).valid)
    }

    func testObservationOnlyPlanDoesNotBecomeAnExecutableSuccess() {
        let result = TestPlanOptimizer.optimize(plan([.sequence([.screenshot, .accessibilityTree])]))
        XCTAssertTrue(result.steps.isEmpty)
        XCTAssertFalse(TestPlanValidator.validate(result).executable)
    }

    func testEmptySequenceRemainsInvalid() {
        let result = TestPlanOptimizer.optimize(plan([.sequence([])]))
        XCTAssertEqual(result.steps.count, 1)
        XCTAssertFalse(TestPlanValidator.validate(result).valid)
    }

    func testNestedExecutableSequencesValidateAfterCompaction() {
        let original = plan([.sequence([.accessibilityTree, .sequence([.tapElement(selector)])])])
        XCTAssertFalse(TestPlanValidator.validate(original).executable)
        XCTAssertTrue(TestPlanValidator.validate(TestPlanOptimizer.optimize(original)).executable)
    }

    func testStateIdentityDetectsInteractionAvailability() {
        for flag in ["enabled", "exists", "selected"] {
            let before = "{\"elements\":[{\"identifier\":\"continue\",\"type\":\"button\",\"\(flag)\":false}]}"
            let after = before.replacingOccurrences(of: "false", with: "true")
            XCTAssertNotEqual(StateIdentity.stableID(before), StateIdentity.stableID(after), flag)
        }
    }

    func testStateIdentityDoesNotConfuseFieldSeparatorsWithContent() {
        let first = #"{"elements":[{"type":"button","identifier":"a|b","label":"c"}]}"#
        let second = #"{"elements":[{"type":"button","identifier":"a","label":"b|c"}]}"#
        XCTAssertNotEqual(StateIdentity.stableID(first), StateIdentity.stableID(second))
    }
}
