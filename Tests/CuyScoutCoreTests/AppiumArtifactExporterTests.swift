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

    func testTheAppiumScriptLeavesEvidenceWhenAStepFails() throws {
        let selector = ScoutSelector(strategy: .accessibilityIdentifier, value: "login")
        let recording = RecordedSession(sessionID: "recorded", startedAt: Date(), stoppedAt: Date(),
            steps: [RecordedStep(index: 0, action: .tapElement(selector), startedAt: Date(), durationMilliseconds: 1, success: true)])
        let script = recording.generatedAppiumTypeScript
        XCTAssertTrue(script.contains("CUYSCOUT_FAILURE_DIR"), "la carpeta de evidencia la decide quien ejecuta")
        XCTAssertTrue(script.contains("catch (error) { await saveFailureEvidence(error); throw error; }"), "la prueba sigue fallando, solo que con evidencia")
        for file in ["paso.txt", "pantalla.png", "pantalla.txt"] { XCTAssertTrue(script.contains(file), file) }
        XCTAssertTrue(script.contains("attribute('password') === 'true'"), "los campos seguros no se vuelcan")
        XCTAssertTrue(script.contains("currentStep = `${path}"), "se sabe qué paso falló")
        let phone = Device(id: "9tlvcmpfln75zpeq", name: "Redmi", runtime: "Android 14", state: "Booted", isAvailable: true, kind: .physical, platform: .android)
        let android = TypeScriptReplayExporter.make(steps: recording.steps, session: Session(id: "s", device: phone, bundleIdentifier: "com.example.app", createdAt: Date(), driverID: "android-device"))
        XCTAssertTrue(android.contains("'appium:settings[waitForIdleTimeout]'"), "UiAutomator2 no espera a que la app esté quieta")
        XCTAssertTrue(android.contains("starts-with(@content-desc, ${xpathLiteral(prefix)})"), "un label con saldo se busca por lo que no cambia")
        XCTAssertTrue(android.contains("relaxAmounts = relaxIds = action.type === 'tapElement' || action.type === 'typeElement' || action.type === 'clearElement';"), "las verificaciones siguen siendo exactas: ni el importe ni el contador del id se relajan")
        XCTAssertTrue(android.contains("id_replaced_by_same_prefix") && android.contains("alternatives.length === 1"), "el id con contador solo se sustituye si el exacto no sirve y hay un único elemento visible y habilitado con ese prefijo")
        XCTAssertTrue(android.contains("assertionsChecked++") && android.contains("verified: assertionsChecked > 0") && android.contains("checked no assertion"), "un replay sin aserciones lo dice en voz alta")
        XCTAssertTrue(android.contains("await element.clearValue();\n                await element.addValue(input(action, 'text', path));"), "en Android escribir reemplaza el texto: addValue de Appium agrega y duplicaba la clave al reescribirla")
        XCTAssertFalse(script.contains("await element.clearValue();\n                await element.addValue"), "en iOS el comportamiento no cambia")
        XCTAssertTrue(script.contains("CUYSCOUT_FIND_TIMEOUT_MS"), "el margen para encontrar un elemento se puede subir")
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
