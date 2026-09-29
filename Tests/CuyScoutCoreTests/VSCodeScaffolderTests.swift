import XCTest
@testable import CuyScoutCore

final class VSCodeScaffolderTests: XCTestCase {
    func testPromptsPointToAgentsMarkdownAndNeverRunTheNewScenario() throws {
        let prompts = VSCodeScaffolder.promptFiles()
        let create = try XCTUnwrap(prompts[".github/prompts/nuevo-escenario.prompt.md"])
        XCTAssertTrue(create.hasPrefix("---\nmode: agent"))
        XCTAssertTrue(create.contains("[AGENTS.md](../../AGENTS.md)"))
        XCTAssertTrue(create.contains("${input:descripcion:"))
        XCTAssertTrue(create.contains("No ejecutes la prueba"))
        XCTAssertNotNil(prompts[".github/prompts/ejecutar-escenario.prompt.md"])
    }

    func testCreatesSettingsWhenMissing() throws {
        let merged = try XCTUnwrap(VSCodeScaffolder.mergedSettings(existing: nil))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(merged.utf8)) as? [String: Any])
        XCTAssertEqual((object["[cucumber]"] as? [String: Any])?["editor.tabSize"] as? Int, 2)
        XCTAssertEqual(object["chat.useAgentsMdFile"] as? Bool, true)
    }

    func testKeepsTheTeamsExistingSettings() throws {
        let existing = #"{"editor.fontSize": 15, "[cucumber]": {"editor.tabSize": 4}}"#
        let merged = try XCTUnwrap(VSCodeScaffolder.mergedSettings(existing: existing))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(merged.utf8)) as? [String: Any])
        XCTAssertEqual(object["editor.fontSize"] as? Int, 15)
        XCTAssertEqual((object["[cucumber]"] as? [String: Any])?["editor.tabSize"] as? Int, 4, "no pisa lo que el equipo eligió")
        XCTAssertEqual((object["[cucumber]"] as? [String: Any])?["editor.formatOnSave"] as? Bool, true)
    }

    func testLeavesCommentedSettingsUntouched() {
        XCTAssertNil(VSCodeScaffolder.mergedSettings(existing: "{\n  // mío\n  \"a\": 1\n}"))
    }

    func testAddsRecommendationsWithoutDuplicates() throws {
        let merged = try XCTUnwrap(VSCodeScaffolder.mergedExtensions(existing: #"{"recommendations": ["cucumberopen.cucumber-official", "esbenp.prettier-vscode"]}"#))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(merged.utf8)) as? [String: Any])
        XCTAssertEqual(object["recommendations"] as? [String], ["cucumberopen.cucumber-official", "esbenp.prettier-vscode", "GitHub.copilot-chat"])
    }

    func testApplyIsIdempotent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("vscode-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        try VSCodeScaffolder.apply(to: root)
        let again = try VSCodeScaffolder.apply(to: root)
        XCTAssertTrue(again.contains(".vscode/settings.json (ya estaba configurado)"))
        XCTAssertTrue(again.contains(".vscode/extensions.json (ya estaba configurado)"))
    }
}
