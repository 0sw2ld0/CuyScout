import XCTest
@testable import CuyScoutCore

final class AppiumArtifactExporterTests: XCTestCase {
    func testExportsBothLanguagesFromSavedArtifact() throws {
        let selector = ScoutSelector(strategy: .accessibilityIdentifier, value: "login")
        let recording = RecordedSession(sessionID: "recorded", startedAt: Date(), stoppedAt: Date(),
            steps: [RecordedStep(index: 0, action: .tapElement(selector), startedAt: Date(),
                                 durationMilliseconds: 1, success: true)])
        let artifact = bundle(recording: recording)
        let data = try JSONEncoder().encode(artifact)

        XCTAssertEqual(AppiumExportFormat.typescript.fileExtension, "ts")
        XCTAssertEqual(AppiumExportFormat.python.fileExtension, "py")
        XCTAssertEqual(try AppiumExportFormat.typescript.source(fromArtifactData: data), recording.generatedAppiumTypeScript)
        XCTAssertEqual(try AppiumExportFormat.python.source(fromArtifactData: data), recording.generatedAppiumPython)
    }

    func testRejectsArtifactWithoutRecording() throws {
        let data = try JSONEncoder().encode(bundle(recording: nil))
        XCTAssertThrowsError(try AppiumExportFormat.python.source(fromArtifactData: data))
        XCTAssertThrowsError(try AppiumExportFormat.typescript.source(fromArtifactData: Data("{}".utf8)))
    }

    private func bundle(recording: RecordedSession?) -> SessionArtifactBundle {
        let session = Session(id: "recorded", device: Device(id: "sim", name: "iPhone", runtime: "iOS", state: "Shutdown"),
                              bundleIdentifier: "com.example.app", createdAt: Date())
        let metrics = SessionMetrics(totalCommands: 0, successfulCommands: 0, failedCommands: 0,
                                     failureRate: 0, averageDurationMilliseconds: 0,
                                     p95DurationMilliseconds: 0, commandCounts: [:])
        return SessionArtifactBundle(session: session, events: [], metrics: metrics, checkpoints: [],
                                     testPlan: nil, recording: recording)
    }
}
