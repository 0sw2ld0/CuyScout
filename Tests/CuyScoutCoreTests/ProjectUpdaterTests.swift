import XCTest
@testable import CuyScoutCore

final class ProjectUpdaterTests: XCTestCase {
    private func temporaryProject() -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("updater-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    func testAFreshProjectIsUpToDateUntilTheTemplatesChange() throws {
        let root = temporaryProject()
        try ProjectUpdater.write(options: .init(appName: "Demo", appPath: "", cuyscoutRepoPath: "", port: 4723), vscode: false, to: root,
                                 physicalBundleID: "com.example.demo")
        XCTAssertFalse(ProjectUpdater.needsUpdate(root))
        var config = try XCTUnwrap(ProjectUpdater.readConfig(root))
        XCTAssertEqual(config["physicalBundleId"] as? String, "com.example.demo")
        config[ProjectUpdater.versionKey] = "version-anterior"
        try JSONSerialization.data(withJSONObject: config).write(to: root.appendingPathComponent(ProjectUpdater.configFile))
        XCTAssertTrue(ProjectUpdater.needsUpdate(root))
        XCTAssertFalse(ProjectUpdater.needsUpdate(temporaryProject()), "una carpeta sin CuyScout no es un proyecto")
    }

    func testUpdatingAnOldProjectKeepsItsContentAndSettings() throws {
        let root = temporaryProject()
        // Proyecto creado por una versión anterior: archivos generados, sin metadatos guardados.
        var legacy = ProjectScaffolder.Options(appName: "Mi App", appPath: "/apps/MiApp.app", cuyscoutRepoPath: "/repos/CuyScout", port: 4800)
        legacy.useMCP = true
        try ProjectUpdater.write(options: legacy, vscode: true, to: root)
        let config: [String: Any] = ["simulator": "/apps/MiApp.app", "physical": "", "physicalBundleId": "com.example.miapp"]
        try JSONSerialization.data(withJSONObject: config).write(to: root.appendingPathComponent(ProjectUpdater.configFile))
        let feature = root.appendingPathComponent("features/pago.feature")
        try "Feature: Pago\n".write(to: feature, atomically: true, encoding: .utf8)
        let credentials = root.appendingPathComponent("fixtures/credentials.test.json")
        try #"{"qa":{"password":"x"}}"#.write(to: credentials, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("rules"), withIntermediateDirectories: true)
        let rule = root.appendingPathComponent("rules/regla.md")
        try "**Qué hacer:** algo\n".write(to: rule, atomically: true, encoding: .utf8)
        try "#!/bin/bash\n# viejo\n".write(to: root.appendingPathComponent("scripts/open-session.sh"), atomically: true, encoding: .utf8)
        XCTAssertTrue(ProjectUpdater.needsUpdate(root))

        let (options, vscode) = ProjectUpdater.inferSettings(for: root)
        XCTAssertEqual(options.appName, "Mi App")
        XCTAssertEqual(options.cuyscoutRepoPath, "/repos/CuyScout")
        XCTAssertEqual(options.port, 4800)
        XCTAssertTrue(options.useMCP)
        XCTAssertTrue(vscode)

        try ProjectUpdater.update(root)
        XCTAssertFalse(ProjectUpdater.needsUpdate(root))
        XCTAssertEqual(try String(contentsOf: feature, encoding: .utf8), "Feature: Pago\n")
        XCTAssertEqual(try String(contentsOf: credentials, encoding: .utf8), #"{"qa":{"password":"x"}}"#)
        XCTAssertEqual(try String(contentsOf: rule, encoding: .utf8), "**Qué hacer:** algo\n")
        XCTAssertFalse(try String(contentsOf: root.appendingPathComponent("scripts/open-session.sh"), encoding: .utf8).contains("# viejo"))
        let updated = try XCTUnwrap(ProjectUpdater.readConfig(root))
        XCTAssertEqual(updated["physicalBundleId"] as? String, "com.example.miapp")
        XCTAssertEqual(updated["simulator"] as? String, "/apps/MiApp.app")
        XCTAssertEqual(updated["mcp"] as? Bool, true)
    }
}
