import XCTest
@testable import CuyScoutCore

/// Un proyecto con iOS y Android: un comando por plataforma y una prueba grabada por plataforma.
final class PlatformRunTests: XCTestCase {
    private func root() -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Platform Run " + UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }; return root
    }

    private func bothPlatforms(_ path: URL, platform: Device.Platform = .android, vscode: Bool = true) throws {
        let android = AndroidProjectConfiguration(applicationId: "com.example.wallet", driverId: "android-emulator")
        try ProjectUpdater.write(options: .init(appName: "Wallet", appPath: "/apps/Wallet.app", cuyscoutRepoPath: "", platform: .ios),
                                 vscode: vscode, to: path, simulatorApp: "/apps/Wallet.app")
        try ProjectUpdater.write(options: .init(appName: "Wallet", appPath: android.apk, cuyscoutRepoPath: "", platform: platform, android: android),
                                 vscode: vscode, to: path)
    }

    private func bash(_ script: String, in project: URL, environment: [String: String] = [:]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", "PROJECT_DIR=\"$1\"; source \"$1/scripts/android-project.sh\"; \(script)", "bash", project.path]
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        let output = Pipe(); process.standardOutput = output; process.standardError = output
        try process.run(); let data = output.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func testScenarioStemKeepsSinglePlatformNamesAndSuffixesTheOthers() {
        XCTAssertEqual(ScenarioStem.stem(base: "pago", platform: .android, multiPlatform: false), "pago")
        XCTAssertEqual(ScenarioStem.stem(base: "pago", platform: .android, multiPlatform: true), "pago.android")
        XCTAssertEqual(ScenarioStem.stem(base: "pago.ios", platform: .android, multiPlatform: true), "pago.ios", "no se suma un segundo sufijo")
        XCTAssertEqual(ScenarioStem.split("pago.android").base, "pago")
        XCTAssertEqual(ScenarioStem.split("pago.android").platform, .android)
        XCTAssertNil(ScenarioStem.split("pago").platform)
        XCTAssertEqual(ScenarioStem.split(".ios").base, ".ios", "un nombre que es solo el sufijo no se parte")
    }

    func testAppShowsPlatformVariantsInsteadOfTheBareFeatureRow() {
        let names = ScenarioStem.displayNames(artifacts: ["pago.ios", "pago.android", "solo"], features: ["pago", "solo", "nuevo"], lastRuns: ["pago.ios"])
        XCTAssertEqual(names, ["nuevo", "pago.android", "pago.ios", "solo"])
        let legacy = ScenarioStem.displayNames(artifacts: ["pago"], features: ["pago"], lastRuns: [])
        XCTAssertEqual(legacy, ["pago"], "un proyecto de una plataforma no cambia")
    }

    func testPlatformsAreDetectedFromTheConfigAndWhatIsBeingWritten() {
        let ios = ProjectScaffolder.Options(appName: "A", appPath: "/a.app", cuyscoutRepoPath: "")
        XCTAssertEqual(ProjectUpdater.configuredPlatforms(options: ios, config: [:]), [.ios])
        var android = ios; android.platform = .android
        XCTAssertEqual(ProjectUpdater.configuredPlatforms(options: android, config: ["simulator": "", "physical": ""]), [.android])
        XCTAssertEqual(ProjectUpdater.configuredPlatforms(options: android, config: ["simulator": "/a.app"]), [.ios, .android],
                       "iOS que ya existía y Android que llega")
        XCTAssertEqual(ProjectUpdater.configuredPlatforms(options: ios, config: ["android": ["applicationId": "com.example.a"]]), [.ios, .android])
    }

    func testPlatformPromptsAndAgentsSectionExistOnlyWithBothPlatforms() throws {
        XCTAssertEqual(Set(VSCodeScaffolder.promptFiles().keys.map { ($0 as NSString).lastPathComponent }),
                       ["nuevo-escenario.prompt.md", "ejecutar-escenario.prompt.md", "reproducir-escenario.prompt.md"])
        let both = VSCodeScaffolder.promptFiles(platforms: [.ios, .android])
        let android = try XCTUnwrap(both[".github/prompts/ejecutar-escenario-android.prompt.md"])
        XCTAssertTrue(android.contains("CUYSCOUT_PLATFORM=android scripts/open-session.sh"))
        XCTAssertTrue(android.contains("CUYSCOUT_PLATFORM=android scripts/close-session.sh \"$SESSION\" <escenario> --discard"))
        XCTAssertFalse(android.contains("CUYSCOUT_PLATFORM=ios"))
        XCTAssertTrue(try XCTUnwrap(both[".github/prompts/ejecutar-escenario-ios.prompt.md"]).contains("CUYSCOUT_PLATFORM=ios scripts/open-session.sh"))
        XCTAssertEqual(VSCodeScaffolder.promptFiles(platforms: [.android]).count, 3)

        var options = ProjectScaffolder.Options(appName: "A", appPath: "/a.app", cuyscoutRepoPath: "")
        XCTAssertFalse(ProjectScaffolder.agentsMarkdownBlock(for: options).contains("## Dos plataformas"))
        options.configuredPlatforms = [.ios, .android]
        for platform in [Device.Platform.ios, .android] {
            options.platform = platform
            let block = ProjectScaffolder.agentsMarkdownBlock(for: options)
            XCTAssertTrue(block.contains("## Dos plataformas"))
            let marker = ProjectScaffolder.agentsMarkdownEndMarker
            XCTAssertEqual(block.components(separatedBy: marker).count, 2, "el marcador final sigue siendo único")
            XCTAssertLessThan(try XCTUnwrap(block.range(of: "## Dos plataformas")).lowerBound, try XCTUnwrap(block.range(of: marker)).lowerBound,
                              "la sección va dentro del bloque de CuyScout, antes del marcador final")
        }
    }

    func testProjectGetsThePlatformPromptsAndStaysCurrent() throws {
        let path = root(); try bothPlatforms(path)
        let prompts = try FileManager.default.contentsOfDirectory(atPath: path.appendingPathComponent(".github/prompts").path)
        XCTAssertTrue(prompts.contains("ejecutar-escenario-ios.prompt.md") && prompts.contains("ejecutar-escenario-android.prompt.md"))
        XCTAssertFalse(ProjectUpdater.needsUpdate(path))
        let agents = try String(contentsOf: path.appendingPathComponent("AGENTS.md"), encoding: .utf8)
        XCTAssertTrue(agents.contains("## Dos plataformas"))

        let single = root()
        try ProjectUpdater.write(options: .init(appName: "Wallet", appPath: "/apps/Wallet.app", cuyscoutRepoPath: ""), vscode: true, to: single, simulatorApp: "/apps/Wallet.app")
        XCTAssertFalse(FileManager.default.fileExists(atPath: single.appendingPathComponent(".github/prompts/ejecutar-escenario-ios.prompt.md").path))
    }

    func testGeneratedScriptsChooseThePlatformAndNameOutputsPerPlatform() throws {
        let files = ProjectScaffolder.files(for: .init(appName: "A", appPath: "/a.app", cuyscoutRepoPath: ""))
        XCTAssertTrue(files["scripts/open-session.sh"]!.contains("scout_require_platform"))
        let close = files["scripts/close-session.sh"]!
        XCTAssertTrue(close.contains(#"SCENARIO_NAME="$(scout_stem "${SCENARIO_NAME}" "${SESSION_PLATFORM}")""#), "la plataforma es la de la sesión que se cierra")
        XCTAssertTrue(close.contains(#"[[ "${RAW_SCENARIO_NAME}" != "scenario" ]]"#), "--discard exige el nombre que se dio, no el sufijado")
        XCTAssertTrue(close.contains(#"${CUYSCOUT_URL}/sessions""#), "la plataforma se lee de GET /sessions")
        XCTAssertFalse(close.contains(#"SESSION_PLATFORM="$(scout_curl -sf "${CUYSCOUT_URL}/session/${SESSION}/artifacts""#), "leerla no puede exportar: --discard no exporta nada")
        XCTAssertTrue(files["scripts/replay-cuyscout.sh"]!.contains(#"scout_resolve_stem "${TARGET}""#))
        XCTAssertTrue(files["scripts/replay-appium.sh"]!.contains(#"scout_resolve_stem "${SCENARIO_ARG}""#))
        XCTAssertTrue(files["scripts/replay-appium.sh"]!.contains(#"scout_values_file "${SCENARIO}""#))
    }

    func testShellHelpersHonorCuyscoutPlatformAndPickTheRightFiles() throws {
        let path = root(); try bothPlatforms(path)
        XCTAssertEqual(try bash("scout_platforms", in: path), "ios android")
        XCTAssertEqual(try bash("scout_config platform", in: path), "android", "el proyecto quedó con Android por defecto")
        XCTAssertEqual(try bash("scout_config platform", in: path, environment: ["CUYSCOUT_PLATFORM": "ios"]), "ios")
        XCTAssertEqual(try bash("scout_config platform", in: path, environment: ["CUYSCOUT_PLATFORM": "windows"]), "android", "un valor inválido se ignora")
        XCTAssertEqual(try bash("scout_stem pago", in: path), "pago.android")
        XCTAssertEqual(try bash("scout_stem pago", in: path, environment: ["CUYSCOUT_PLATFORM": "ios"]), "pago.ios")
        XCTAssertEqual(try bash("scout_stem pago ios", in: path), "pago.ios", "la plataforma de la sesión gana al proyecto")
        XCTAssertEqual(try bash("scout_stem pago.ios.cuyscout.json", in: path), "pago.ios")

        let output = path.appendingPathComponent("output")
        try Data().write(to: output.appendingPathComponent("pago.ios.cuyscout.json"))
        XCTAssertEqual(try bash("scout_resolve_stem pago.ios", in: path), "pago.ios", "un nombre completo que existe se respeta")
        XCTAssertEqual(try bash("scout_resolve_stem pago", in: path, environment: ["CUYSCOUT_PLATFORM": "ios"]), "pago.ios")

        let values = path.appendingPathComponent("fixtures/replay-values")
        try FileManager.default.createDirectory(at: values, withIntermediateDirectories: true)
        try "{}".write(to: values.appendingPathComponent("pago.json"), atomically: true, encoding: .utf8)
        XCTAssertTrue(try bash("scout_values_file pago.android", in: path).hasSuffix("fixtures/replay-values/pago.json"), "sin valores propios usa los del escenario base")
        try "{}".write(to: values.appendingPathComponent("pago.android.json"), atomically: true, encoding: .utf8)
        XCTAssertTrue(try bash("scout_values_file pago.android", in: path).hasSuffix("fixtures/replay-values/pago.android.json"))
    }

    func testOnlyAStoppedAndroidEmulatorMatchingTheSelectionCanBePoweredOn() {
        let stopped = Device(id: "Pixel_8", name: "Pixel_8", runtime: "Android", state: "Shutdown", kind: .simulator, platform: .android)
        let running = Device(id: "emulator-5554", name: "Pixel_7", runtime: "Android 15", state: "Booted", kind: .simulator, platform: .android)
        let phone = Device(id: "R58M", name: "Galaxy", runtime: "Android 14", state: "Shutdown", kind: .physical, platform: .android)
        let iphone = Device(id: "Pixel_8", name: "Pixel_8", runtime: "iOS 18", state: "Shutdown", kind: .simulator, platform: .ios)
        XCTAssertEqual([running, phone, stopped].stoppedAVD(matching: "Pixel_8")?.id, "Pixel_8")
        XCTAssertNil([running].stoppedAVD(matching: "Pixel_7"), "uno que ya corre no se ofrece")
        XCTAssertNil([phone].stoppedAVD(matching: "R58M"), "un físico no se enciende desde aquí")
        XCTAssertNil([iphone].stoppedAVD(matching: "Pixel_8"), "un simulador de iOS tampoco")
        XCTAssertNil([stopped].stoppedAVD(matching: ""), "«Automático» no señala un AVD concreto")
    }

    func testSwitchingBetweenEmulatorAndPhysicalClearsTheChosenTargetAndKeepsTheRest() throws {
        var android = AndroidProjectConfiguration(apk: "/apps/Wallet.apk", applicationId: "com.example.wallet", activity: ".Main", driverId: "android-emulator", avd: "Pixel_8")
        android.selectDriver("android-device")
        XCTAssertEqual(android.driverId, "android-device")
        XCTAssertNil(android.avd, "el AVD era del emulador")
        XCTAssertEqual([android.apk, android.applicationId, android.activity], ["/apps/Wallet.apk", "com.example.wallet", ".Main"])
        XCTAssertNoThrow(try android.validate())
        android.deviceId = "R58M1234ABC"
        android.selectDriver("android-emulator")
        XCTAssertEqual(android.driverId, "android-emulator")
        XCTAssertNil(android.deviceId, "el serial era del teléfono")
        XCTAssertNoThrow(try android.validate())
    }

    func testRequestingAPlatformTheProjectLacksFailsClearly() throws {
        let path = root()
        try ProjectUpdater.write(options: .init(appName: "Wallet", appPath: "/apps/Wallet.app", cuyscoutRepoPath: ""), vscode: false, to: path, simulatorApp: "/apps/Wallet.app")
        XCTAssertEqual(try bash("scout_platforms; scout_multi_platform && echo multi || echo single", in: path), "ios\nsingle")
        XCTAssertEqual(try bash("scout_stem pago", in: path), "pago", "un proyecto de una plataforma conserva sus nombres")
        let message = try bash("scout_require_platform; echo \"código=$?\"", in: path, environment: ["CUYSCOUT_PLATFORM": "android"])
        XCTAssertTrue(message.contains("no tiene android configurado"), message)
        XCTAssertTrue(message.hasSuffix("código=1"), message)
    }
}
