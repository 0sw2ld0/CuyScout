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

    // MARK: Appium en Android sin actividad configurada

    /// Un `adb` falso que registra sus argumentos y responde como `cmd package resolve-activity --brief`.
    private func fakeADB(in dir: URL, reply: String) throws -> (adb: URL, log: URL) {
        let adb = dir.appendingPathComponent("adb"), log = dir.appendingPathComponent("adb.log")
        try "#!/bin/bash\necho \"$*\" >> \"\(log.path)\"\nprintf '%b' '\(reply)'\n".write(to: adb, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: adb.path)
        return (adb, log)
    }

    func testTheLauncherActivityOfAnInstalledAppIsResolvedThroughAdb() throws {
        let project = root(); try bothPlatforms(project)
        let fake = try fakeADB(in: project, reply: "priority=0 preferredOrder=0 match=0x108000 specificIndex=-1 isDefault=false\\r\\ncom.bcp.bank.bcp.dev/com.bcp.bank.bcp.ui.auth.MainActivity\\r\\n")
        let output = try bash("scout_launcher_activity '\(fake.adb.path)' 9tlvcmpfln75zpeq com.bcp.bank.bcp.dev", in: project)
        XCTAssertEqual(output, "com.bcp.bank.bcp.ui.auth.MainActivity", "solo la actividad, sin el paquete y sin el retorno de carro")
        let call = try String(contentsOf: fake.log, encoding: .utf8)
        XCTAssertTrue(call.contains("-s 9tlvcmpfln75zpeq shell cmd package resolve-activity --user 0 --brief"), "con --user 0: un teléfono con perfil de trabajo tiene más de un usuario")
    }

    func testTheAppIsBroughtToTheForegroundOnlyWhenAnotherScreenHasTheFocus() throws {
        let project = root(); try bothPlatforms(project)
        let focused = try fakeADB(in: project.appendingPathComponent("scripts"), reply: "  mCurrentFocus=Window{97f65e0 u0 com.bcp.bank.bcp.dev/com.bcp.bank.bcp.ui.auth.MainActivity}\\n")
        XCTAssertEqual(try bash("scout_ensure_app_foreground '\(focused.adb.path)' S com.bcp.bank.bcp.dev X; echo \"[$?]\"", in: project), "[0]")
        XCTAssertFalse(try String(contentsOf: focused.log, encoding: .utf8).contains("am start"), "con el foco puesto no se relanza nada")
        let launcher = project.appendingPathComponent("launcher")
        try FileManager.default.createDirectory(at: launcher, withIntermediateDirectories: true)
        let other = try fakeADB(in: launcher, reply: "  mCurrentFocus=Window{97f65e0 u0 com.miui.home/com.miui.home.launcher.Launcher}\\n")
        let output = try bash("scout_ensure_app_foreground '\(other.adb.path)' S com.bcp.bank.bcp.dev com.bcp.bank.bcp.ui.auth.MainActivity; echo \"[$?]\"", in: project)
        XCTAssertTrue(output.hasSuffix("[0]"), output)
        XCTAssertTrue(try String(contentsOf: other.log, encoding: .utf8).contains("-s S shell am start -n com.bcp.bank.bcp.dev/com.bcp.bank.bcp.ui.auth.MainActivity"))
        let script = try String(contentsOf: project.appendingPathComponent("scripts/open-session.sh"), encoding: .utf8)
        let ensure = try XCTUnwrap(script.range(of: "scout_ensure_app_foreground \"$ADB_BIN\""))
        let ready = try XCTUnwrap(script.range(of: "Sesión ${SESSION} lista en"))
        XCTAssertLessThan(ensure.lowerBound, ready.lowerBound, "la app tiene el foco antes de devolver la sesión")
    }

    func testNoActivityIsReportedWhenTheAppIsNotInstalledOrBelongsToAnotherPackage() throws {
        let project = root(); try bothPlatforms(project)
        let missing = try fakeADB(in: project.appendingPathComponent("scripts"), reply: "No activity found\\n")
        XCTAssertEqual(try bash("scout_launcher_activity '\(missing.adb.path)' S com.example.wallet; echo \"[$?]\"", in: project), "[1]", "no inventa una actividad")
        let other = try fakeADB(in: project, reply: "priority=0\\nanother.app/.Main\\n")
        XCTAssertEqual(try bash("scout_launcher_activity '\(other.adb.path)' S com.example.wallet; echo \"[$?]\"", in: project), "[1]", "ni acepta la actividad de otro paquete")
    }

    func testTheSDKRootIsDerivedFromAdbWhenTheEnvironmentHasNone() throws {
        let project = root(); try bothPlatforms(project)
        // <raíz>/platform-tools/adb, alcanzado a través de un enlace como el de Homebrew.
        let sdk = project.appendingPathComponent("sdk-real"), tools = sdk.appendingPathComponent("platform-tools")
        try FileManager.default.createDirectory(at: tools, withIntermediateDirectories: true)
        let fake = try fakeADB(in: tools, reply: "")
        let bin = project.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let link = bin.appendingPathComponent("adb")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fake.adb)
        let real = URL(fileURLWithPath: realpath(sdk.path, nil).map { String(cString: $0) } ?? sdk.path).path
        let output = try bash("unset ANDROID_HOME ANDROID_SDK_ROOT; scout_export_sdk_root '\(link.path)'; echo \"$ANDROID_HOME|$ANDROID_SDK_ROOT\"", in: project)
        XCTAssertEqual(output, "\(real)|\(real)", "Appium necesita la raíz del SDK aunque solo exista un adb suelto")
        let kept = try bash("export ANDROID_HOME='\(real)'; unset ANDROID_SDK_ROOT; scout_export_sdk_root '\(link.path)'; echo \"$ANDROID_SDK_ROOT\"", in: project)
        XCTAssertEqual(kept, real, "si solo hay una de las dos variables, se copia a la otra")
        let script = try String(contentsOf: project.appendingPathComponent("scripts/replay-appium.sh"), encoding: .utf8)
        let adb = try XCTUnwrap(script.range(of: "scout_export_sdk_root \"$ADB\""))
        let server = try XCTUnwrap(script.range(of: "APPIUM_LEVEL=info"))
        XCTAssertLessThan(adb.lowerBound, server.lowerBound, "las variables existen antes de levantar Appium")
    }

    func testVerboseAppiumLogsNeverKeepTheReplayValuesInClear() throws {
        let project = root(); try bothPlatforms(project)
        let script = try String(contentsOf: project.appendingPathComponent("scripts/replay-appium.sh"), encoding: .utf8)
        let start = try XCTUnwrap(script.range(of: "scout_redact() {"))
        let end = try XCTUnwrap(script.range(of: "\n}\n", range: start.upperBound..<script.endIndex))
        let function = String(script[start.lowerBound..<end.upperBound])
        let log = project.appendingPathComponent("appium.log")
        try """
        POST /value {"text":"s3cretPW"}
        proxy body: {"value":["s","3","c","r","e","t","P","W"]}
        amount {"text":"10.00"} y texto normal
        """.write(to: log, atomically: true, encoding: .utf8)
        let out = try bash("VALUES='{\"3.text\":\"s3cretPW\",\"9.text\":\"10.00\"}'; \(function)\nscout_redact < '\(log.path)'", in: project)
        XCTAssertFalse(out.contains("s3cretPW"), out)
        XCTAssertFalse(out.contains("\"s\",\"3\""), "tampoco carácter a carácter: \(out)")
        XCTAssertFalse(out.contains("10.00"), out)
        XCTAssertTrue(out.contains("texto normal"), "el resto del log se conserva")
        XCTAssertTrue(script.contains("| scout_redact | tee"), "la salida en pantalla también se tacha")
    }

    func testHugeLogLinesAreShortenedOnScreenButKeptInTheFile() throws {
        let project = root(); try bothPlatforms(project)
        let script = try String(contentsOf: project.appendingPathComponent("scripts/replay-appium.sh"), encoding: .utf8)
        let start = try XCTUnwrap(script.range(of: "scout_redact() {"))
        let end = try XCTUnwrap(script.range(of: "\n}\n", range: start.upperBound..<script.endIndex))
        let function = String(script[start.lowerBound..<end.upperBound])
        let log = project.appendingPathComponent("big.log")
        try ("corta\n" + String(repeating: "A", count: 5000) + "\nfin\n").write(to: log, atomically: true, encoding: .utf8)
        let screen = try bash("VALUES='{}'; \(function)\nCUYSCOUT_REDACT_MAXLINE=100 scout_redact < '\(log.path)'", in: project)
        XCTAssertTrue(screen.contains("corta") && screen.contains("fin"), String(screen.prefix(600)))
        XCTAssertTrue(screen.contains("+4901 caracteres"), screen)
        XCTAssertLessThan(screen.count, 400)
        let file = try bash("VALUES='{}'; \(function)\nscout_redact < '\(log.path)' | wc -c", in: project)
        XCTAssertGreaterThan(Int(file) ?? 0, 5000, "sin límite el archivo queda completo")
        XCTAssertTrue(script.contains("CUYSCOUT_REDACT_MAXLINE=1200 scout_redact"), "en pantalla sí se acortan")
        XCTAssertTrue(script.contains("rm -rf \"${OUT_DIR}/${SCENARIO}.fallo\""), "la evidencia es de la última ejecución")
    }

    func testTheAndroidAppiumScriptResolvesTheActivityInsteadOfStoppingAtTheFirstCheck() throws {
        let project = root(); try bothPlatforms(project)
        let script = try String(contentsOf: project.appendingPathComponent("scripts/replay-appium.sh"), encoding: .utf8)
        XCTAssertTrue(script.contains("scout_launcher_activity \"$ADB\" \"$UDID\" \"$BUNDLE_ID\""))
        let resolve = try XCTUnwrap(script.range(of: "scout_launcher_activity \"$ADB\""))
        let device = try XCTUnwrap(script.range(of: "get-state"))
        XCTAssertGreaterThan(resolve.lowerBound, device.lowerBound, "se resuelve cuando ya se conoce el dispositivo")
        XCTAssertEqual(script.components(separatedBy: "Define ANDROID_APP_ACTIVITY o configura android.apk.").count - 1, 1, "el aviso solo sale si no se pudo averiguar")
    }

    func testTheAppiumScriptStillParsesAndOffersVerboseAppiumLogging() throws {
        let project = root(); try bothPlatforms(project)
        let path = project.appendingPathComponent("scripts/replay-appium.sh").path
        let check = Process(); check.executableURL = URL(fileURLWithPath: "/bin/bash"); check.arguments = ["-n", path]
        let errors = Pipe(); check.standardError = errors
        try check.run(); check.waitUntilExit()
        XCTAssertEqual(check.terminationStatus, 0, String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
        let script = try String(contentsOfFile: path, encoding: .utf8)
        XCTAssertTrue(script.contains("CUYSCOUT_APPIUM_VERBOSE") && script.contains("--log-level \"${APPIUM_LEVEL}\""))
        XCTAssertTrue(script.contains("tail -n 0 -F \"${APPIUM_LOG}\""), "el log de Appium se muestra mientras corre la prueba")
        XCTAssertTrue(script.contains("APPIUM_LEVEL=info"), "sin la variable, el nivel sigue siendo info")
    }
}
