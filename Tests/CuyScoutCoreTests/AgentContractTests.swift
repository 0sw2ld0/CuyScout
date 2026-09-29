import XCTest
@testable import CuyScoutCore

final class AgentContractTests: XCTestCase {
    func testSessionCreationExplainsPendingInvocationAndOwnership() {
        for help in [AgentContract.instructions, AgentContract.httpHelp["instructions"] as! String] {
            XCTAssertTrue(help.contains("SAME"))
            XCTAssertTrue(help.contains("device_busy"))
            XCTAssertTrue(help.contains("original response"))
            XCTAssertTrue(help.contains("another client's session"))
        }
    }
    func testPaymentRiskAndInlineSummaryGuidanceAreAvailableWithoutRepository() {
        let engine = ScoutEngine()
        for value in ["btn_service_pay", "Botón Pagar ahora", "transferir", "purchase"] {
            let action = ScoutAction.tapElement(.init(strategy: .accessibilityIdentifier, value: value))
            XCTAssertEqual(engine.suggestionRisk(action, selectorValue: value), "high")
            XCTAssertTrue(engine.suggestionReason(action, semantics: value, fallback: "button").contains("assertText"))
        }
        for help in [AgentContract.instructions, AgentContract.httpHelp["instructions"] as! String] {
            XCTAssertTrue(help.contains("inline"))
            XCTAssertTrue(help.contains("assertText"))
            XCTAssertTrue(help.contains("CUYSCOUT_REPLAY_VALUES"))
            XCTAssertTrue(help.contains("STOP"))
        }
    }
    func testHTTPHelpHasRawExecutableBodyAndSeparateTimeoutBody() throws {
        XCTAssertEqual(AgentContract.httpHelp["mode"] as? String, "http")
        let body = try XCTUnwrap(AgentContract.httpHelp["exampleExecuteBody"] as? [String: Any])
        XCTAssertNil(body["action"])
        XCTAssertNil(body["sessionId"])
        let decoded = try AgentContract.decodeHTTPAction(JSONSerialization.data(withJSONObject: body))
        XCTAssertEqual(decoded, .typeElement(ScoutSelector(strategy: .accessibilityIdentifier, value: "observed_field_id"), text: "user input"))
    }

    func testHTTPRejectsWrappedMalformedAndIncompleteActionsAsClientErrors() {
        for input in [#"{"action":{"type":"typeElement"}}"#, #"{"type":"typeElement"}"#, "{", #"{"type":"typeElement","text":"<text>"}"#] {
            XCTAssertThrowsError(try AgentContract.decodeHTTPAction(Data(input.utf8))) { error in
                XCTAssertEqual((error as? ScoutError)?.httpStatus, 400)
                XCTAssertTrue(error.localizedDescription.contains("No action performed"))
            }
        }
    }
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
