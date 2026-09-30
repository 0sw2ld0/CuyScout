import XCTest
@testable import CuyScoutCore

final class ProjectRulesTests: XCTestCase {
    private func temporaryProject() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("rules-project-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "{}".write(to: root.appendingPathComponent(".cuyscout-project.json"), atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    func testRuleIDsAreReadableSlugsAndFileNamesStayInsideTheFolder() {
        XCTAssertEqual(ProjectRuleFile.id(forTitle: "Ingreso con usuario recordado"), "rule:ingreso-con-usuario-recordado")
        XCTAssertEqual(ProjectRuleFile.id(forTitle: "¿Botón «Clave» no es campo?"), "rule:boton-clave-no-es-campo")
        XCTAssertEqual(ProjectRuleFile.id(forTitle: "!!!"), "rule:regla")
        XCTAssertEqual(ProjectRuleFile.fileName(for: "rule:../../etc/passwd"), "etcpasswd.md")
        XCTAssertEqual(ProjectRuleFile.fileName(for: "rule:ingreso"), "ingreso.md")
    }

    func testRenderAndParseRoundTrip() throws {
        let lesson = LearnedLesson(id: "rule:ingreso", scope: .project, title: "Ingreso con usuario recordado",
                                   observation: "La app abre en una pantalla de opciones", recommendation: "Tocar la opción de ingresar con clave",
                                   evidence: "Visto en la pantalla inicial", tags: ["login", "precondicion"], confidence: 0.85, occurrences: 3, failures: 1)
        let text = ProjectRuleFile.render(lesson)
        XCTAssertTrue(text.contains("titulo: Ingreso con usuario recordado"))
        XCTAssertTrue(text.contains("**Qué hacer:** Tocar la opción de ingresar con clave"))
        let parsed = try XCTUnwrap(ProjectRuleFile.parse(text, id: "rule:ingreso"))
        XCTAssertEqual(parsed.title, lesson.title)
        XCTAssertEqual(parsed.observation, lesson.observation)
        XCTAssertEqual(parsed.recommendation, lesson.recommendation)
        XCTAssertEqual(parsed.evidence, lesson.evidence)
        XCTAssertEqual(parsed.tags, ["login", "precondicion"])
        XCTAssertEqual(parsed.confidence, 0.85, accuracy: 0.001)
        XCTAssertEqual(parsed.occurrences, 3)
        XCTAssertEqual(parsed.failures, 1)
    }

    func testParsesAHandWrittenRuleWithoutFrontmatter() throws {
        let parsed = try XCTUnwrap(ProjectRuleFile.parse("Cerrar el tutorial inicial con «Omitir».\n", id: "rule:cerrar-tutorial"))
        XCTAssertEqual(parsed.title, "cerrar tutorial")
        XCTAssertEqual(parsed.recommendation, "Cerrar el tutorial inicial con «Omitir».")
        XCTAssertNil(ProjectRuleFile.parse("   \n", id: "rule:vacia"))
    }

    func testRulesStoreWritesOneMarkdownPerRuleAndMergesRepeats() throws {
        let rules = try temporaryProject().appendingPathComponent("rules")
        let store = LessonStore(rulesDirectory: rules)
        let first = try store.record(LearnedLesson(scope: .project, title: "Ingreso con usuario recordado",
                                                   observation: "Pantalla de opciones", recommendation: "Tocar ingresar con clave", tags: ["login"]))
        XCTAssertEqual(first.id, "rule:ingreso-con-usuario-recordado")
        XCTAssertTrue(FileManager.default.fileExists(atPath: rules.appendingPathComponent("README.md").path))
        let again = try store.record(LearnedLesson(scope: .project, title: "Ingreso con usuario recordado",
                                                   observation: "Pantalla de opciones", recommendation: "Tocar ingresar con clave", tags: ["precondicion"]))
        XCTAssertEqual(again.occurrences, 2)
        let files = try FileManager.default.contentsOfDirectory(atPath: rules.path).sorted()
        XCTAssertEqual(files, ["README.md", "ingreso-con-usuario-recordado.md"])
        XCTAssertEqual(LessonStore(rulesDirectory: rules).search().map(\.tags), [["login", "precondicion"]])
    }

    func testRulesStoreRedactsSecretsAndPicksUpHumanEdits() throws {
        let rules = try temporaryProject().appendingPathComponent("rules")
        let store = LessonStore(rulesDirectory: rules)
        let saved = try store.record(LearnedLesson(scope: .project, title: "Login", observation: "Usuario qa@example.com con clave: 123456",
                                                   recommendation: "Usar el alias del fixture"))
        let file = rules.appendingPathComponent(ProjectRuleFile.fileName(for: saved.id))
        let written = try String(contentsOf: file, encoding: .utf8)
        XCTAssertFalse(written.contains("qa@example.com"))
        XCTAssertFalse(written.contains("123456"))
        try written.replacingOccurrences(of: "Usar el alias del fixture", with: "Usar solo la password del alias")
            .write(to: file, atomically: true, encoding: .utf8)
        XCTAssertEqual(store.search().first?.recommendation, "Usar solo la password del alias")
        let failed = try XCTUnwrap(store.feedback(id: saved.id, helped: false))
        XCTAssertEqual(failed.failures, 1)
        XCTAssertTrue(try String(contentsOf: file, encoding: .utf8).contains("fallos: 1"))
    }

    func testSessionProjectLessonsLiveInTheProjectRulesFolder() throws {
        let project = try temporaryProject()
        let global = LessonStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("lessons-\(UUID().uuidString).json"))
        let engine = ScoutEngine(lessonStore: global)
        let session = try engine.createSession(deviceID: nil, bundleIdentifier: "com.example.rules")
        defer { try? engine.deleteSession(session.id) }
        try engine.setProjectDirectory(sessionID: session.id, path: project.path)
        let lesson = try engine.recordLesson(scope: .project, sessionID: session.id, title: "Botón no es campo",
                                             observation: "La opción menciona la clave pero no es editable", recommendation: "Tocarla y escribir en el campo seguro")
        XCTAssertEqual(lesson.id, "rule:boton-no-es-campo")
        XCTAssertTrue(FileManager.default.fileExists(atPath: project.appendingPathComponent("rules/boton-no-es-campo.md").path))
        XCTAssertTrue(global.search().isEmpty)
        XCTAssertEqual(try engine.lessons(sessionID: session.id).first?.id, lesson.id)
        XCTAssertEqual(try engine.lessonFeedback(id: lesson.id, helped: true, sessionID: session.id).occurrences, 2)
        XCTAssertThrowsError(try engine.lessonFeedback(id: lesson.id, helped: true))
    }

    func testProjectDirectoryMustBeACuyScoutProject() throws {
        let engine = ScoutEngine(lessonStore: LessonStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("lessons-\(UUID().uuidString).json")))
        let session = try engine.createSession(deviceID: nil, bundleIdentifier: "com.example.rules")
        defer { try? engine.deleteSession(session.id) }
        XCTAssertThrowsError(try engine.setProjectDirectory(sessionID: session.id, path: FileManager.default.temporaryDirectory.path))
        XCTAssertThrowsError(try engine.setProjectDirectory(sessionID: session.id, path: "relativa/proyecto"))
        XCTAssertNil(engine.projectDirectory(sessionID: session.id))
    }

    func testActiveSessionsKeepTheirLease() throws {
        let engine = ScoutEngine(lessonStore: LessonStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("lessons-\(UUID().uuidString).json")))
        let session = try engine.createSession(deviceID: nil, bundleIdentifier: "com.example.rules")
        defer { try? engine.deleteSession(session.id) }
        XCTAssertTrue(engine.isLeaseActive(sessionID: session.id))
        XCTAssertNil(engine.activeSessions().first { $0.id == session.id }?.leaseExpired)
        XCTAssertFalse(try engine.sessionReadiness(sessionID: session.id).blockers.contains("session_lease_expired"))
    }

    func testErrorsCarryANextStepHint() {
        XCTAssertEqual(ScoutError.notInteractable("x").w3cCode, "element not interactable")
        XCTAssertEqual(ScoutError.notInteractable("x").httpStatus, 400)
        XCTAssertTrue(ScoutError.notInteractable("x").hint?.contains("No reintentes") == true)
        XCTAssertTrue(ScoutError.invalidRequest("session_lease_expired").hint?.contains("abre una nueva") == true)
        XCTAssertNil(ScoutError.invalidRequest("otra cosa").hint)
    }

    func testOpenSessionPicksTheDriverAndPassesTheProject() throws {
        let script = try XCTUnwrap(ProjectScaffolder.files(for: .init(appName: "Demo", appPath: "", cuyscoutRepoPath: ""))["scripts/open-session.sh"])
        XCTAssertTrue(script.contains(#"DRIVER_ID="${CUYSCOUT_DRIVER_ID:-${DEFAULT_DRIVER}}""#))
        XCTAssertTrue(script.contains(#""cuyscout:projectDir":os.environ["REPLAY_PROJECT_DIR"]"#))
        XCTAssertTrue(script.contains(#"caps["appium:noReset"]=True"#))
        let agents = ProjectScaffolder.agentsMarkdownBlock(for: .init(appName: "Demo", appPath: "", cuyscoutRepoPath: ""))
        XCTAssertTrue(agents.contains("## Alcanzar las precondiciones"))
        XCTAssertTrue(agents.contains("## Reglas aprendidas (`rules/`)"))
        XCTAssertTrue(agents.contains("## Errores de CuyScout y qué hacer"))
    }
}

final class RunnerStalenessTests: XCTestCase {
    func testRunnerIsRebuiltOnlyWhenItsSourcesAreNewer() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("runner-stale-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let project = root.appendingPathComponent("ScoutRunner.xcodeproj")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("Runner.swift")
        try "// v1".write(to: source, atomically: true, encoding: .utf8)
        let xctestrun = root.appendingPathComponent("built.xctestrun")
        try "".write(to: xctestrun, atomically: true, encoding: .utf8)
        let past = Date().addingTimeInterval(-60)
        try FileManager.default.setAttributes([.modificationDate: past], ofItemAtPath: source.path)
        try FileManager.default.setAttributes([.modificationDate: past], ofItemAtPath: project.path)
        XCTAssertFalse(ScoutEngine.runnerIsStale(xctestrun: xctestrun.path, project: project.path))
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: source.path)
        XCTAssertTrue(ScoutEngine.runnerIsStale(xctestrun: xctestrun.path, project: project.path))
    }
}

final class RepeatedActionLimitTests: XCTestCase {
    func testSameActionOnTheSameScreenStopsAfterTheLimit() throws {
        let engine = ScoutEngine(lessonStore: LessonStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("lessons-\(UUID().uuidString).json")))
        let session = try engine.createSession(deviceID: nil, bundleIdentifier: "com.example.retry")
        defer { try? engine.deleteSession(session.id) }
        let retry = ScoutAction.tapElement(ScoutSelector(strategy: .label, value: "Reintentar"))
        for _ in 0..<ScoutEngine.maxSameActionAttempts { XCTAssertNoThrow(try engine.checkRepeatedAction(retry, sessionID: session.id)) }
        XCTAssertThrowsError(try engine.checkRepeatedAction(retry, sessionID: session.id)) { error in
            XCTAssertTrue(error.localizedDescription.contains("retry_limit_reached"))
            XCTAssertNotNil((error as? ScoutError)?.hint)
        }
        // Otra acción rompe la racha; mirar la pantalla no cuenta como acción.
        XCTAssertNoThrow(try engine.checkRepeatedAction(.tapElement(ScoutSelector(strategy: .label, value: "Otra opción")), sessionID: session.id))
        XCTAssertNoThrow(try engine.checkRepeatedAction(retry, sessionID: session.id))
        XCTAssertNoThrow(try engine.checkRepeatedAction(.accessibilityTree, sessionID: session.id))
    }
}
