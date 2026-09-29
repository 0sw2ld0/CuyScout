import XCTest
@testable import CuyScoutCore

final class LessonFeedbackTests: XCTestCase {
    private func store() -> LessonStore {
        LessonStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("lessons-\(UUID().uuidString).json"))
    }

    private func candidate(_ title: String = "Elegir la cuenta de origen") -> LearnedLesson {
        LearnedLesson(scope: .project, projectKey: "com.example.app", title: title, observation: "o", recommendation: "r", confidence: 0.5)
    }

    func testHelpedRaisesConfidenceAndFailedLowersItAndCountsFailures() throws {
        let store = store()
        let lesson = try store.record(candidate())
        let helped = try XCTUnwrap(store.feedback(id: lesson.id, helped: true))
        XCTAssertEqual(helped.confidence, 0.65, accuracy: 0.001)
        let failed = try XCTUnwrap(store.feedback(id: lesson.id, helped: false))
        XCTAssertEqual(failed.confidence, 0.40, accuracy: 0.001)
        XCTAssertEqual(failed.failures, 1)
    }

    func testDiscardedLessonIsNoLongerDeliveredButStaysAuditable() throws {
        let store = store()
        let lesson = try store.record(candidate())
        try store.feedback(id: lesson.id, helped: false)
        XCTAssertTrue(store.search().isEmpty, "0.25 < umbral: no debe entregarse a los agentes")
        XCTAssertEqual(store.search(includeDiscarded: true).count, 1)
    }

    func testProposingADiscardedLessonAgainDoesNotRevivesIt() throws {
        let store = store()
        let lesson = try store.record(candidate())
        try store.feedback(id: lesson.id, helped: false)
        let again = try store.record(candidate())
        XCTAssertTrue(again.isDiscarded)
        XCTAssertTrue(store.search().isEmpty)
    }

    func testUnknownLessonReturnsNil() throws {
        XCTAssertNil(try store().feedback(id: "no-existe", helped: true))
    }

    func testLessonsFileWithoutFailuresFieldStillLoads() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("legacy-\(UUID().uuidString).json")
        let legacy = #"[{"id":"L1","scope":"global","title":"t","observation":"o","recommendation":"r","tags":[],"confidence":0.8,"createdAt":0,"updatedAt":0,"occurrences":1}]"#
        try Data(legacy.utf8).write(to: url)
        let lessons = LessonStore(fileURL: url).search()
        XCTAssertEqual(lessons.map(\.id), ["L1"])
        XCTAssertNil(lessons[0].failures)
    }
}
