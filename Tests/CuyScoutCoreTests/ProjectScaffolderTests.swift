import XCTest
@testable import CuyScoutCore

final class ProjectScaffolderTests: XCTestCase {
    private func options() -> ProjectScaffolder.Options {
        ProjectScaffolder.Options(appName: "CuyWallet", appPath: "/path/to/CuyWallet.app",
            cuyscoutRepoPath: "/path/to/CuyScout", port: 4723)
    }

    func testGeneratesOnlyTheScriptsAndNeverTouchesFeatures() {
        let files = ProjectScaffolder.files(for: options())
        XCTAssertEqual(Set(files.keys), ["scripts/cuyscout-connection.sh", "scripts/ensure-cuyscout.sh", "scripts/open-session.sh", "scripts/close-session.sh", "scripts/replay-cuyscout.sh", "fixtures/replay-values/.gitignore"])
        XCTAssertTrue(files["scripts/ensure-cuyscout.sh"]!.contains("/path/to/CuyScout"))
        XCTAssertTrue(files["scripts/ensure-cuyscout.sh"]!.contains("4723"))
        XCTAssertTrue(files["scripts/open-session.sh"]!.contains("CUYWALLET_APP_PATH"))
        XCTAssertTrue(files["scripts/open-session.sh"]!.contains("/path/to/CuyWallet.app"))
        XCTAssertTrue(files["scripts/open-session.sh"]!.contains("CUYSCOUT_DRIVER_ID"))
        XCTAssertTrue(files["scripts/open-session.sh"]!.contains("CUYSCOUT_DEVICE_ID"))
        XCTAssertTrue(files["scripts/open-session.sh"]!.contains("Authorization: Bearer"))
        XCTAssertTrue(files["scripts/cuyscout-connection.sh"]!.contains("gateway-connection.json"))
        XCTAssertTrue(files["scripts/cuyscout-connection.sh"]!.contains("0o077"))
        XCTAssertTrue(files["scripts/close-session.sh"]!.contains(".cuyscout.json"))
        XCTAssertTrue(files["scripts/close-session.sh"]!.contains("recording/replay-values"))
        XCTAssertEqual(files["fixtures/replay-values/.gitignore"], "*\n!.gitignore\n")
        XCTAssertTrue(files["scripts/replay-cuyscout.sh"]!.contains("/artifacts/import?overwrite=true"))
        XCTAssertTrue(files["scripts/replay-cuyscout.sh"]!.contains("/replay"))
        XCTAssertTrue(files["scripts/replay-cuyscout.sh"]!.contains("fixtures/replay-values"))
        XCTAssertTrue(files["scripts/replay-cuyscout.sh"]!.contains("CUYSCOUT_REPLAY_DEVICE_ID"))
        XCTAssertTrue(files["scripts/replay-cuyscout.sh"]!.contains("/replay/preflight"))
        XCTAssertTrue(files["scripts/ensure-cuyscout.sh"]!.contains("/Applications/CuyScout.app/Contents/MacOS/cuyscout"))
        XCTAssertFalse(files["scripts/replay-cuyscout.sh"]!.contains("npm"))
        XCTAssertTrue(ProjectScaffolder.agentsMarkdownBlock(for: options()).contains("MCP primero"))
        XCTAssertTrue(ProjectScaffolder.agentsMarkdownBlock(for: options()).contains("HTTP/curl"))
    }

    func testAgentsMarkdownExplainsHowToWriteScenarios() {
        let block = ProjectScaffolder.agentsMarkdownBlock(for: options())
        XCTAssertTrue(block.contains("## Escribir un escenario (`features/`)"))
        XCTAssertTrue(block.contains("Credenciales por alias"))
        XCTAssertTrue(block.contains("espera a\nque lo revisen antes de ejecutarlo") || block.contains("antes de ejecutarlo"))
        XCTAssertTrue(block.contains("```gherkin"))
    }

    func testShellScriptsAreMarkedExecutable() {
        XCTAssertEqual(Set(ProjectScaffolder.executablePaths),
            ["scripts/ensure-cuyscout.sh", "scripts/open-session.sh", "scripts/close-session.sh", "scripts/replay-cuyscout.sh"])
    }

    func testGeneratedReplayScriptHasValidShellSyntax() throws {
        for (name, contents) in ProjectScaffolder.files(for: options()) where name.hasSuffix(".sh") {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("cuyscout-script-\(UUID().uuidString).sh")
            defer { try? FileManager.default.removeItem(at: file) }
            try contents.write(to: file, atomically: true, encoding: .utf8)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-n", file.path]
            try process.run()
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0, name)
        }
    }

    func testConnectionHelperLoadsPrivateAppProfile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("cuyscout-connection-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let helper = directory.appendingPathComponent("cuyscout-connection.sh")
        let profileURL = directory.appendingPathComponent("gateway-connection.json")
        try ProjectScaffolder.files(for: options())["scripts/cuyscout-connection.sh"]!.write(to: helper, atomically: true, encoding: .utf8)
        try LocalGatewayProfile(url: "http://192.168.1.2:4723", token: "private-token").save(to: profileURL)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", "source \"$1\"; printf '%s|%s' \"$CUYSCOUT_URL\" \"$CUYSCOUT_TOKEN\"", "bash", helper.path]
        var environment = ProcessInfo.processInfo.environment
        environment["CUYSCOUT_PROFILE"] = profileURL.path
        environment.removeValue(forKey: "CUYSCOUT_URL")
        environment.removeValue(forKey: "CUYSCOUT_TOKEN")
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self), "http://192.168.1.2:4723|private-token")
    }

    func testSanitizesAppNameIntoAValidEnvironmentVariablePrefix() {
        var custom = options()
        custom.appName = "Cuy Wallet 2.0"
        let files = ProjectScaffolder.files(for: custom)
        XCTAssertTrue(files["scripts/open-session.sh"]!.contains("CUY_WALLET_2_0_APP_PATH"))
    }

    func testCreatesAgentsMarkdownWhenMissing() {
        let merged = ProjectScaffolder.mergedAgentsMarkdown(existingContent: nil, options: options())
        XCTAssertTrue(merged.contains(ProjectScaffolder.agentsMarkdownStartMarker))
        XCTAssertTrue(merged.contains(ProjectScaffolder.agentsMarkdownEndMarker))
        XCTAssertTrue(merged.contains("CuyWallet"))
        XCTAssertTrue(merged.contains("Modo generar"))
        XCTAssertTrue(merged.contains("Modo reproducir"))
    }

    func testUpdatesOnlyTheManagedBlockAndPreservesHandwrittenContent() {
        let existing = """
        # Notas del equipo

        Recuerda correr los tests en el simulador de iPhone 17 Pro.

        \(ProjectScaffolder.agentsMarkdownStartMarker)
        contenido viejo que debe desaparecer
        \(ProjectScaffolder.agentsMarkdownEndMarker)

        ## Otra sección manual
        Esto tampoco se debe borrar.
        """
        let merged = ProjectScaffolder.mergedAgentsMarkdown(existingContent: existing, options: options())
        XCTAssertTrue(merged.contains("Recuerda correr los tests en el simulador de iPhone 17 Pro."))
        XCTAssertTrue(merged.contains("Otra sección manual"))
        XCTAssertFalse(merged.contains("contenido viejo que debe desaparecer"))
        XCTAssertTrue(merged.contains("CuyWallet"))
    }

    func testAppendsManagedBlockWhenExistingFileHasNoMarkers() {
        let existing = "# README escrito a mano\n\nSin marcadores todavía.\n"
        let merged = ProjectScaffolder.mergedAgentsMarkdown(existingContent: existing, options: options())
        XCTAssertTrue(merged.contains("Sin marcadores todavía."))
        XCTAssertTrue(merged.contains(ProjectScaffolder.agentsMarkdownStartMarker))
    }

    func testCredentialsFixtureIsValidJSONWithADemoUser() throws {
        let data = Data(ProjectScaffolder.credentialsFixture().utf8)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(json?["demo_user"])
    }
}
