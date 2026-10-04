import XCTest
@testable import CuyScoutCore

final class IntelAppAndReplayKindTests: XCTestCase {
    private let old = "com.apple.CoreSimulator.SimRuntime.iOS-18-3"
    private let universal = "com.apple.CoreSimulator.SimRuntime.iOS-26-4"

    private func sim(_ name: String, _ runtime: String, booted: Bool = false) -> Device {
        Device(id: "\(name)-\(runtime)", name: name, runtime: runtime, state: booted ? "Booted" : "Shutdown")
    }

    func testIntelAppsPreferABootedThenNewestUniversalSimulator() {
        let versions = [old: "18.3", universal: "26.4"]
        let booted = sim("iPhone 16", old, booted: true)
        XCTAssertEqual(RosettaSimulator.preferredIntelDevice([sim("iPhone 17 Pro", universal), booted], versions: versions), booted)
        XCTAssertEqual(RosettaSimulator.preferredIntelDevice([sim("iPhone 16 Pro", old), sim("iPhone 17", universal), sim("iPhone 17 Pro", universal)], versions: versions)?.name, "iPhone 17 Pro")
        XCTAssertNil(RosettaSimulator.preferredIntelDevice([], versions: versions))
    }

    func testReplayOnAnotherDevicePrefersAStandardIPhone() {
        let recorded = Device(id: "00000000-0000000000000001", name: "iPhone de alguien", runtime: "iOS 26.4", state: "connected", kind: .physical)
        let small = sim("iPhone SE (3rd generation)", universal, booted: true)
        let renamed = sim("Simulador de pruebas", universal, booted: true)
        let standard = sim("iPhone 17 Pro", universal)
        XCTAssertEqual(ScoutEngine.preferredReplayDevice(from: [small, renamed, standard], recorded: recorded), standard)
        // Si la prueba se grabó justo en un SE, se respeta ese modelo.
        let recordedSE = sim("iPhone SE (3rd generation)", old)
        XCTAssertEqual(ScoutEngine.preferredReplayDevice(from: [small, standard], recorded: recordedSE), small)
    }

    func testRejectionExplainsWhichRuntimeWorks() {
        let message = ScoutEngine.intelAppRejection(sim("iPhone 17 Pro", "com.apple.CoreSimulator.SimRuntime.iOS-26-5"))
        XCTAssertTrue(message.contains("iOS-26-5"))
        XCTAssertTrue(message.contains("x86_64"))
    }

    func testReplayOnAnotherKindUsesThatKindsDriver() {
        XCTAssertEqual(ScoutEngine.driverID("ios-device", for: .simulator), "ios-simulator")
        XCTAssertEqual(ScoutEngine.driverID("ios-simulator", for: .physical), "ios-device")
        XCTAssertEqual(ScoutEngine.driverID("custom", for: .physical), "custom")
    }

    func testReplayScriptFollowsTheProjectLikeOpenSession() throws {
        let options = ProjectScaffolder.Options(appName: "Demo", appPath: "/tmp/Demo.app", cuyscoutRepoPath: "")
        let script = try XCTUnwrap(ProjectScaffolder.files(for: options)["scripts/replay-cuyscout.sh"])
        XCTAssertTrue(script.contains(#""deviceKind": os.environ["REPLAY_KIND"]"#))
        XCTAssertTrue(script.contains("ios-device) TARGET_KIND=\"physical\""))
        XCTAssertTrue(script.contains("export CUYSCOUT_NEEDS_PHYSICAL=1"))
        XCTAssertTrue(ProjectScaffolder.agentsMarkdownBlock(for: options).contains("aunque la prueba se haya grabado en un iPhone"))
    }
}

final class ReplayOnlyGoodRecordingsTests: XCTestCase {
    func testScriptsAndPromptReplayOnlyAGoodRecording() throws {
        let options = ProjectScaffolder.Options(appName: "Demo", appPath: "/tmp/Demo.app", cuyscoutRepoPath: "")
        let files = ProjectScaffolder.files(for: options)
        let replay = try XCTUnwrap(files["scripts/replay-cuyscout.sh"])
        XCTAssertTrue(replay.contains("exit 5"))
        XCTAssertTrue(replay.contains("CUYSCOUT_REPLAY_FORCE"))
        let close = try XCTUnwrap(files["scripts/close-session.sh"])
        XCTAssertTrue(close.contains(#"reason in ("fallo_app", "grabacion_incompleta")"#), "una grabación incompleta cuenta como fallida")
        XCTAssertTrue(close.contains("/recording/plan\""))
        let prompts = VSCodeScaffolder.promptFiles()
        let run = try XCTUnwrap(prompts[".github/prompts/ejecutar-escenario.prompt.md"])
        XCTAssertTrue(run.contains("aunque ya exista una grabación"), "ejecutar siempre vuelve a probar con el agente")
        XCTAssertTrue(run.contains("rules/*.md"))
        let replayPrompt = try XCTUnwrap(prompts[".github/prompts/reproducir-escenario.prompt.md"])
        XCTAssertTrue(replayPrompt.contains("código 5"))
        XCTAssertTrue(replayPrompt.contains("no lo repitas"))
        XCTAssertTrue(ProjectScaffolder.agentsMarkdownBlock(for: options).contains("sale con código 5"))
    }
}

final class ExecuteMeansGenerateTests: XCTestCase {
    func testAgentsSaysExecutingGeneratesAgain() {
        let options = ProjectScaffolder.Options(appName: "Demo", appPath: "/tmp/Demo.app", cuyscoutRepoPath: "")
        let agents = ProjectScaffolder.agentsMarkdownBlock(for: options)
        XCTAssertTrue(agents.contains("usa este modo aunque ya exista una"))
        XCTAssertTrue(agents.contains("Solo cuando lo piden explícitamente"))
    }
}

final class DuplicateRuntimeTests: XCTestCase {
    func testTwoRuntimesWithTheSameIdentifierDoNotCrash() throws {
        // Xcode puede dejar iOS 26.4 y 26.4.1 con el mismo identificador.
        let json = #"""
        {"runtimes": [
          {"identifier": "com.apple.CoreSimulator.SimRuntime.iOS-26-4", "name": "iOS 26.4", "version": "26.4", "isAvailable": true, "platform": "iOS", "supportedArchitectures": ["x86_64", "arm64"], "supportedDeviceTypes": []},
          {"identifier": "com.apple.CoreSimulator.SimRuntime.iOS-26-4", "name": "iOS 26.4", "version": "26.4.1", "isAvailable": true, "platform": "iOS", "supportedArchitectures": ["x86_64", "arm64"], "supportedDeviceTypes": []}
        ]}
        """#
        let runtimes = RosettaSimulator.runtimes(from: Data(json.utf8))
        XCTAssertEqual(runtimes.count, 2)
        XCTAssertEqual(RosettaSimulator.versionsByIdentifier(runtimes), ["com.apple.CoreSimulator.SimRuntime.iOS-26-4": "26.4.1"])
    }
}

final class SemanticTapTests: XCTestCase {
    private func element(_ type: String, id: String = "", label: String = "", _ x: Double, _ y: Double, _ w: Double, _ h: Double) -> [String: Any] {
        ["type": type, "identifier": id, "label": label, "frame": ["x": x, "y": y, "width": w, "height": h]]
    }
    private let interactive: (String) -> Bool = { ["button", "cell", "textfield"].contains($0.lowercased()) }

    func testCoordinateTapOnALabelledButtonBecomesASelector() {
        let elements = [
            element("Other", 0, 0, 402, 874),
            element("Button", label: "Ingresar con clave", 16, 776, 370, 48),
            element("StaticText", label: "Ingresar con clave", 30, 790, 200, 20)
        ]
        let selector = ScoutEngine.semanticSelector(at: CGPoint(x: 201, y: 800), in: elements, isInteractive: interactive)
        XCTAssertEqual(selector, ScoutSelector(strategy: .label, value: "Ingresar con clave"))
    }

    func testIdentifierWinsAndAmbiguousOrEmptyControlsStayAsCoordinates() {
        let withID = [element("Button", id: "btn_login", label: "Ingresar", 0, 0, 100, 40)]
        XCTAssertEqual(ScoutEngine.semanticSelector(at: CGPoint(x: 50, y: 20), in: withID, isInteractive: interactive)?.strategy, .accessibilityIdentifier)
        let twins = [element("Button", label: "Ver", 0, 0, 100, 40), element("Button", label: "Ver", 0, 100, 100, 40)]
        XCTAssertNil(ScoutEngine.semanticSelector(at: CGPoint(x: 50, y: 20), in: twins, isInteractive: interactive), "con dos 'Ver' el selector podría tocar el otro")
        let unnamed = [element("Button", 0, 0, 100, 40)]
        XCTAssertNil(ScoutEngine.semanticSelector(at: CGPoint(x: 50, y: 20), in: unnamed, isInteractive: interactive))
        XCTAssertNil(ScoutEngine.semanticSelector(at: CGPoint(x: 500, y: 500), in: withID, isInteractive: interactive))
    }

    func testAgentsTellsToTapBySelector() {
        let options = ProjectScaffolder.Options(appName: "Demo", appPath: "/tmp/Demo.app", cuyscoutRepoPath: "")
        XCTAssertTrue(ProjectScaffolder.agentsMarkdownBlock(for: options).contains("Toca por selector, nunca por coordenadas"))
    }
}

final class UnlabeledControlTests: XCTestCase {
    func testACloseButtonIsOfferedInPointsWithItsPosition() throws {
        let screen = CGSize(width: 402, height: 874)
        let close = try XCTUnwrap(ScoutEngine.unlabeledSuggestion(type: "Button", frame: CGRect(x: 340, y: 210, width: 30, height: 30), screen: screen))
        XCTAssertEqual(close.action, .tap(x: 355, y: 225))
        XCTAssertTrue(close.reason.contains("arriba a la derecha"))
        XCTAssertTrue(close.reason.contains("X de cierre"))
        XCTAssertTrue(close.reason.contains("puntos"))
        let bottom = try XCTUnwrap(ScoutEngine.unlabeledSuggestion(type: "Cell", frame: CGRect(x: 0, y: 700, width: 402, height: 60), screen: screen))
        XCTAssertTrue(bottom.reason.contains("abajo"))
        XCTAssertNil(ScoutEngine.unlabeledSuggestion(type: "Image", frame: CGRect(x: 0, y: 0, width: 40, height: 40), screen: screen))
    }

    func testAgentsWarnsAboutScreenshotPixels() {
        let options = ProjectScaffolder.Options(appName: "Demo", appPath: "/tmp/Demo.app", cuyscoutRepoPath: "")
        let agents = ProjectScaffolder.agentsMarkdownBlock(for: options)
        XCTAssertTrue(agents.contains("No calcules coordenadas desde una captura"))
        XCTAssertTrue(agents.contains("3 píxeles por punto"))
    }
}

final class ReplayFailureMessageTests: XCTestCase {
    func testExplainsWhatWasMissingWhatWasThereAndWhatToDo() {
        let message = ScoutEngine.replayFailureMessage(
            step: 5, action: .typeElement(.init(strategy: .label, value: "Clave, cuadro de texto, 0 de 6"), text: "<redacted>"),
            selector: .init(strategy: .label, value: "Clave, cuadro de texto, 0 de 6"),
            screenTexts: ["Bienvenido", "Ingresa tu clave"],
            similar: [SelectorRepair(selector: .init(strategy: .label, value: "Clave, cuadro de texto, 2 de 6"), score: 0.9, reason: "label")])
        XCTAssertTrue(message.hasPrefix("Paso 5: no se pudo escribir en el campo «Clave, cuadro de texto, 0 de 6» (buscado por su texto)"))
        XCTAssertTrue(message.contains("En la pantalla había: «Bienvenido», «Ingresa tu clave»"))
        XCTAssertTrue(message.contains("«Clave, cuadro de texto, 2 de 6» (90 %)"))
        XCTAssertTrue(message.contains("el texto del elemento cambia entre corridas"))
        XCTAssertTrue(message.contains("/ejecutar-escenario"))
    }

    func testAnEmptyScreenPointsToAnotherScreenOrLoading() {
        let message = ScoutEngine.replayFailureMessage(step: 2, action: .tapElement(.init(strategy: .accessibilityIdentifier, value: "btn_ok")),
                                                       selector: .init(strategy: .accessibilityIdentifier, value: "btn_ok"), screenTexts: [], similar: [])
        XCTAssertTrue(message.contains("no se pudo tocar «btn_ok» (buscado por su identificador)"))
        XCTAssertTrue(message.contains("La pantalla no mostraba textos"))
        XCTAssertTrue(message.contains("la app mostró otra pantalla"))
    }
}
