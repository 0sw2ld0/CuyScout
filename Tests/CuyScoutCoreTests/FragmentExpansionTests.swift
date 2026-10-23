import XCTest
@testable import CuyScoutCore

final class FragmentExpansionTests: XCTestCase {
    private var project: URL!
    private let phone = Device(id: "phone", name: "Phone", runtime: "Android 14", state: "Booted", isAvailable: true, kind: .physical, platform: .android)

    override func setUpWithError() throws {
        project = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: project.appendingPathComponent("output"), withIntermediateDirectories: true)
        let login = SessionFragment(name: "login", platform: .android, bundleIdentifier: "com.example.app", defaultAlias: "demo", variables: ["1.text": "password"],
                                    exitCheck: .init(selector: ScoutSelector(strategy: .label, value: "Inicio"), timeout: 15), skipIfAlreadyDone: true,
                                    steps: [.tapElement(ScoutSelector(strategy: .label, value: "Ingresar")), .typeElement(ScoutSelector(strategy: .accessibilityIdentifier, value: "clave"), text: "<redacted>")])
        try FragmentStore.save(login, in: project, overwrite: false)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: project) }

    private func recording() -> [RecordedStep] {
        [RecordedStep(index: 0, action: .runFragment(name: "login", alias: nil), startedAt: Date(), durationMilliseconds: 1, success: true),
         RecordedStep(index: 1, action: .tapElement(ScoutSelector(strategy: .label, value: "Transferir")), startedAt: Date(), durationMilliseconds: 1, success: true)]
    }

    func testAFragmentBecomesItsStepsAndItsExitCheck() throws {
        let steps = try FragmentExpansion.expand(recording(), platform: .android, project: project)
        XCTAssertEqual(steps.count, 2, "las rutas de los valores del replay siguen siendo las de la grabación")
        guard case .sequence(let actions) = steps[0].action else { return XCTFail("el fragmento debe quedar como secuencia") }
        XCTAssertEqual(actions.count, 3)
        XCTAssertEqual(actions[1], .typeElement(ScoutSelector(strategy: .accessibilityIdentifier, value: "clave"), text: "<redacted>"), "la clave nunca entra en lo exportado")
        XCTAssertEqual(actions[2], .waitFor(ScoutSelector(strategy: .label, value: "Inicio"), timeout: 15))
    }

    func testTheAppiumScriptNoLongerCarriesRunFragment() throws {
        let session = Session(id: "s", device: phone, bundleIdentifier: "com.example.app", createdAt: Date(), driverID: "android-device")
        let metrics = SessionMetrics(totalCommands: 0, successfulCommands: 0, failedCommands: 0, failureRate: 0, averageDurationMilliseconds: 0, p95DurationMilliseconds: 0, commandCounts: [:])
        let artifact = SessionArtifactBundle(session: session, events: [], metrics: metrics, checkpoints: [], testPlan: nil,
                                             recording: RecordedSession(sessionID: "s", startedAt: Date(), stoppedAt: Date(), steps: recording(), session: session))
        let data = try JSONEncoder().encode(artifact)
        let script = try AppiumExportFormat.typescript.source(fromArtifactData: data, project: project)
        XCTAssertFalse(script.contains("\"runFragment\""), "Appium no sabe ejecutar un fragmento")
        XCTAssertTrue(script.contains("\"sequence\"") && script.contains("\"Ingresar\""))
        XCTAssertThrowsError(try AppiumExportFormat.typescript.source(fromArtifactData: data), "sin la carpeta del proyecto no hay fragmento que expandir")
        let flow = try MaestroFlowExporter.source(fromArtifactData: data, project: project)
        XCTAssertTrue(flow.contains("Ingresar") && !flow.contains("runFragment"))
    }

    func testTheProjectOfASavedArtifact() {
        let artifact = project.appendingPathComponent("output/escenario.cuyscout.json")
        XCTAssertEqual(FragmentExpansion.project(forArtifact: artifact)?.standardizedFileURL, project.standardizedFileURL)
        XCTAssertNil(FragmentExpansion.project(forArtifact: URL(fileURLWithPath: "/tmp/suelto.cuyscout.json")))
    }
}
