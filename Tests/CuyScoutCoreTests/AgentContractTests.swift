import XCTest
@testable import CuyScoutCore

final class AgentContractTests: XCTestCase {
    func testToolOnlyHelpExplainsConditionalNavigationRecoveryAndReplay() {
        XCTAssertTrue(AgentContract.instructions.contains("not a CuyScout MCP client"))
        XCTAssertTrue(AgentContract.instructions.contains("conditionally"))
        XCTAssertTrue(AgentContract.instructions.contains("UNVERIFIED"))
        XCTAssertTrue(AgentContract.instructions.contains("Never retry a payment automatically"))
    }
    func testHelpExampleActionUsesRealDecoder() throws {
        let args = try XCTUnwrap(AgentContract.help["exampleExecuteArguments"] as? [String: Any])
        let payload = try XCTUnwrap(args["action"] as? [String: Any])
        let action = try JSONDecoder().decode(ScoutAction.self, from: JSONSerialization.data(withJSONObject: payload))
        XCTAssertEqual(action, .typeElement(ScoutSelector(strategy: .accessibilityIdentifier, value: "observed_field_id"), text: "user input"))
    }

    func testObservationSchemaMatchesSerializedModelIncludingOptionalRisk() throws {
        let observation = AgentObservation(context: "NATIVE_APP", url: "", title: "Fixture", stateId: "state:test", changed: false,
            actions: [ActionSuggestion(action: .tapElement(ScoutSelector(strategy: .accessibilityIdentifier, value: "button")), reason: "Visible")],
            texts: ["label: Visible"], exploration: nil)
        let wire = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(observation)) as? [String: Any])
        for field in AgentContract.observationSchema["required"] as? [String] ?? [] { XCTAssertNotNil(wire[field], field) }
        let properties = try XCTUnwrap(AgentContract.observationSchema["properties"] as? [String: Any])
        let actions = try XCTUnwrap(properties["actions"] as? [String: Any])
        let items = try XCTUnwrap(actions["items"] as? [String: Any])
        let suggestion = try XCTUnwrap((wire["actions"] as? [[String: Any]])?.first)
        for field in items["required"] as? [String] ?? [] { XCTAssertNotNil(suggestion[field], field) }
        XCTAssertEqual(wire["texts"] as? [String], ["label: Visible"])
        XCTAssertNotNil(suggestion["action"])
        XCTAssertNil(suggestion["selector"])
    }
}
