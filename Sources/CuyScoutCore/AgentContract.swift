import Foundation

/// Machine-readable onboarding shared by HTTP and MCP; no repository access needed.
public enum AgentContract {
    public static let instructions = """
    Start with cuyscout_help. No source files or AGENT-GUIDE.md are required.
    MCP: read result.structuredContent, or JSON-decode result.content[0].text. These carry the same payload.
    Object results are direct; array/scalar results use {value:...}. Errors have isError:true.
    HTTP observe/readiness/session responses wrap data in value; MCP removes that HTTP envelope.
    Create a session, preserve its sessionId (legacy local mode uses id), set implicit=8000,
    and require interactionReady == true before acting. Missing readiness fields are errors.
    Observe returns stateId:string, texts:string[], actions:[{action:{type,selector,text?},risk,reason}].
    Copy actions[i].action into cuyscout_execute's action argument and add sessionId.
    For typeElement replace <text> with the intended input. Never invent selectors or coordinates.
    Verify visible texts against the goal before irreversible actions. An operation number may only
    exist after payment: validate the summary before, then the receipt and operation number after.
    Do not automatically retry payments after timeouts; observe the current state first.
    Export with cuyscout_export_appium_typescript before ending the session. Replace redacted values
    with runtime variables and add assertions; export is not proof of compilation or successful replay.
    Close with cuyscout_end_session in finally even when assertions fail.
    A connection failure can be a sandbox/network permission issue, not a server crash. Check
    connectivity/permissions; never recreate a session or retry a payment to repair connectivity.
    """

    public static var help: [String: Any] { [
        "version": 1, "instructions": instructions,
        "workflow": ["cuyscout_create_session", "cuyscout_set_timeouts", "cuyscout_session_readiness", "cuyscout_observe", "cuyscout_execute", "cuyscout_validate_test_plan", "cuyscout_export_appium_typescript", "cuyscout_end_session"],
        "exampleObservation": ["stateId": "state:example", "changed": true, "context": "NATIVE_APP", "title": "Example", "texts": ["amount_label: S/ 120.00"], "actions": [["risk": "medium", "reason": "Editable control", "action": ["type": "typeElement", "selector": ["strategy": "accessibilityIdentifier", "value": "observed_field_id"], "text": "<text>"]]]],
        "exampleExecuteArguments": ["sessionId": "<active sessionId>", "action": ["type": "typeElement", "selector": ["strategy": "accessibilityIdentifier", "value": "observed_field_id"], "text": "user input"]],
        "http": ["help": "GET /agent-help", "create": "POST /session", "readiness": "GET /session/:id/readiness", "observe": "GET /session/:id/observe", "execute": "POST /session/:id/actions", "validate": "GET /session/:id/recording/plan/validate", "export": "GET /session/:id/recording/appium/typescript (plain text)", "close": "DELETE /session/:id"]
    ] }

    public static var observationSchema: [String: Any] { [
        "type": "object", "required": ["stateId", "texts", "actions", "context", "changed", "title"],
        "properties": [
            "stateId": ["type": "string"], "context": ["type": "string"], "title": ["type": "string"], "changed": ["type": "boolean"],
            "texts": ["type": "array", "items": ["type": "string"], "description": "Visible strings, often identifier: label. Not objects."],
            "actions": ["type": "array", "items": ["type": "object", "required": ["action", "reason"], "properties": ["action": ["type": "object", "required": ["type"], "properties": ["type": ["type": "string"], "selector": ["type": "object", "required": ["strategy", "value"], "properties": ["strategy": ["type": "string"], "value": ["type": "string"]]], "text": ["type": "string"]]], "risk": ["type": "string"], "reason": ["type": "string"]]]]
        ]
    ] }
}
