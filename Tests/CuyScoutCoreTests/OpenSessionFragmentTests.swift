import XCTest
@testable import CuyScoutCore

/// open-session.sh ejecuta el fragmento del escenario y avisa si el proyecto es de una versión anterior.
final class OpenSessionFragmentTests: XCTestCase {
    private var script: String {
        ProjectScaffolder.files(for: ProjectScaffolder.Options(appName: "Demo", appPath: "/tmp/Demo.app", cuyscoutRepoPath: ""))["scripts/open-session.sh"] ?? ""
    }

    func testOpenSessionRunsTheScenarioFragmentWithoutFailingTheSession() {
        XCTAssertTrue(script.contains("--escenario|--scenario) SCENARIO="))
        XCTAssertTrue(script.contains("grep -oE '@fragment:[A-Za-z0-9_-]+' \"${FEATURE_FILE}\""))
        XCTAssertTrue(script.contains("/session/${SESSION}/fragments/${FRAGMENT}/run"))
        XCTAssertTrue(script.contains("FRAGMENTO_OK") && script.contains("FRAGMENTO_FALLO"))
        // Un fallo del fragmento no corta el script: el agente recibe la sesión y hace el tramo a mano.
        XCTAssertTrue(script.contains("-d '{}' || true)"))
        XCTAssertTrue(script.contains("--sin-fragmento) RUN_FRAGMENT=0"))
    }

    func testOpenSessionWarnsWhenTheProjectIsFromAnOlderVersion() {
        XCTAssertTrue(script.contains(#"if [[ -n "${GATEWAY_SCAFFOLD}" && "${GATEWAY_SCAFFOLD}" != "${PROJECT_SCAFFOLD}" ]]; then"#))
    }

    func testAgentInstructionsOpenTheSessionWithTheScenario() {
        let options = ProjectScaffolder.Options(appName: "Demo", appPath: "/tmp/Demo.app", cuyscoutRepoPath: "")
        XCTAssertTrue(ProjectScaffolder.agentsMarkdownBlock(for: options).contains("scripts/open-session.sh --escenario <escenario>"))
        XCTAssertTrue(VSCodeScaffolder.promptFiles().values.contains { $0.contains("scripts/open-session.sh --escenario <escenario>") })
    }

    func testAnOutdatedProjectGetsTheNoticeOnceThroughObserve() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("outdated-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(#"{"scaffoldVersion":"vieja"}"#.utf8).write(to: root.appendingPathComponent(".cuyscout-project.json"))
        let engine = ScoutEngine(artifactStore: ArtifactStore(directory: root.appendingPathComponent("store")))
        let session = try engine.createSession(deviceID: nil, bundleIdentifier: "com.example.app")
        try engine.setProjectDirectory(sessionID: session.id, path: root.path)
        XCTAssertEqual(engine.takeProjectNotice(sessionID: session.id), ScoutEngine.outdatedProjectNotice)
        XCTAssertNil(engine.takeProjectNotice(sessionID: session.id), "una sola vez por sesión")

        try Data(#"{"scaffoldVersion":"\#(ProjectUpdater.currentVersion)"}"#.utf8).write(to: root.appendingPathComponent(".cuyscout-project.json"))
        let current = try engine.createSession(deviceID: nil, bundleIdentifier: "com.example.app")
        try engine.setProjectDirectory(sessionID: current.id, path: root.path)
        XCTAssertNil(engine.takeProjectNotice(sessionID: current.id), "un proyecto al día no recibe aviso")
    }
}
