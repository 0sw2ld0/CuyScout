import Foundation

/// Machine-readable onboarding shared by HTTP and MCP; no repository access needed.
public enum AgentContract {
    /// HTTP clients must not receive MCP argument envelopes as their primary examples.
    public static var httpHelp: [String: Any] { [
        "version": 2, "mode": "http", "instructions": """
        Use HTTP only. Create a session with POST /session (W3C capabilities); preserve value.sessionId.
        Session creation can take tens of seconds. A shell/tool yielding a running command ID is
        NOT an HTTP failure: wait/poll that SAME command for its final response within your deadline.
        Never repeat POST /session while its result is pending or uncertain. A later device_busy
        error does not invalidate an earlier successful session. Recover the original response;
        if it cannot be recovered, stop and ask the owner, never close another client's session.
        POST /session/ID/timeouts with {"implicit":8000}. GET /session/ID/readiness until
        value.interactionReady === true. Missing readiness fields are errors, not readiness.
        GET /session/ID/observe returns {value:{stateId,changed,texts:string[],actions:[{action,risk,reason}]}}.
        POST /session/ID/actions with the EXACT contents of value.actions[i].action as the JSON body.
        The body is {"type":"typeElement","selector":{"strategy":"accessibilityIdentifier","value":"observed_field_id"},"text":"input"}.
        DO NOT wrap it in {"action":...}; DO NOT include sessionId in the body. The session ID is in the URL.
        Replace <text> with intended input. Copy observed selectors; do not invent IDs or coordinates.
        Observe AFTER completing or changing form fields, not only when first opening the form.
        A summary may appear inline on that SAME form; do not assume a payment button opens a review
        screen. Treat pay/pagar/confirm as potentially final. If the summary is missing, STOP, do not tap
        to discover what happens. Record assertText actions for the observed recipient/service,
        reference and amount BEFORE the final tap; observe alone is not a recorded assertion.
        Example: {"type":"assertText","selector":{"strategy":"accessibilityIdentifier",
        "value":"observed_summary_id"},"expected":"exact observed summary"}. Stop if any check fails.
        A sequence {"type":"sequence","actions":[...]} stops at its first failure.
        Observe each transition. Verify the visible summary before irreversible actions, then verify
        the receipt/operation number afterwards. Never automatically retry payments after a timeout.
        An empty observation immediately after a tap may be a transition, not a failed tap. Wait for
        the observed destination with waitFor, or retry ONLY observe within a bounded timeout.
        GET /session/ID/recording/plan/validate returns an unwrapped JSON object with valid/executable.
        GET /session/ID/recording/appium/typescript returns plain text, not a JSON envelope.
        GET /session/ID/artifacts returns a complete cuyscout.session-artifact.v1 package.
        POST /session/ID/recording/replay-values returns the concrete input map before deletion;
        store it outside version control. The generated close-session.sh does this automatically.
        POST /artifacts/import accepts that package and returns its sessionID; then
        POST /artifacts/ID/replay executes it through CuyScout without Node or Appium.
        Export BEFORE DELETE /session/ID. Close the session even if the scenario fails.
        Export is a log of attempts, not a verified replay. Parameterize redacted inputs, add observed
        summary/receipt assertions and waits. Replace duplicate navigation taps with a destination wait
        and only conditional recovery of reversible navigation; never replay payment retries blindly.
        The exported code is standalone TypeScript: run npx tsx replay.ts with webdriverio installed.
        Do NOT rewrite its helpers: they preserve native CuyScout existence and label/value semantics.
        Set IOS_UDID, IOS_BUNDLE_ID, APPIUM_HOST/PORT, CUYSCOUT_REPLAY_AUTHORIZED=yes and supply
        redacted values via CUYSCOUT_REPLAY_VALUES using the zero-based paths printed in the artifact.
        The code targets Appium/WebdriverIO, not this HTTP API. Only replay with explicit authorization
        in a fresh demo installation. Generated/compiled code alone is not proof of successful replay.
        """,
        "endpoints": help["http"]!, "exampleObservation": ["value": help["exampleObservation"]!],
        "exampleExecuteBody": (help["exampleExecuteArguments"] as! [String: Any])["action"]!,
        "exampleTimeoutBody": ["implicit": 8000]
    ] }

    public static func httpBody(_ data: Data) throws -> [String: Any] {
        guard let value = try? JSONSerialization.jsonObject(with: data), let object = value as? [String: Any] else {
            throw ScoutError.invalidRequest("Expected a valid JSON object. No action performed; see GET /agent-help.")
        }
        return object
    }

    public static func decodeHTTPAction(_ data: Data) throws -> ScoutAction {
        let object = try httpBody(data)
        guard object["type"] is String else {
            throw ScoutError.invalidRequest("HTTP /actions requires the raw observed action {type,selector,text?}, not {action:...} or the suggestion wrapper. Copy observe.value.actions[i].action as the entire body. No action performed; see GET /agent-help.")
        }
        guard !["<text>", "<redacted>"].contains(object["text"] as? String ?? "") else {
            throw ScoutError.invalidRequest("Replace the text placeholder with intended input. No action performed.")
        }
        do { return try JSONDecoder().decode(ScoutAction.self, from: data) }
        catch {
            throw ScoutError.invalidRequest("Invalid HTTP action arguments: copy the observed action exactly; typeElement requires selector:{strategy,value} and text:string. No action performed; see GET /agent-help.")
        }
    }

    public static let instructions = """
    Start with cuyscout_help. No source files or AGENT-GUIDE.md are required.
    MCP: read result.structuredContent, or JSON-decode result.content[0].text. These carry the same payload.
    Object results are direct; array/scalar results use {value:...}. Errors have isError:true.
    For raw stdio transport, serialize requests with JSON.stringify/json.dumps; send one complete
    JSON object per line. JSON-RPC parse error -32700 rejects that input before any app action;
    fix the request syntax, not the app. Native MCP clients normally handle serialization for you.
    HTTP observe/readiness/session responses wrap data in value; MCP removes that HTTP envelope.
    Create a session, preserve its sessionId (legacy local mode uses id), and set implicit=8000.
    Session creation can take tens of seconds. Wait for the SAME pending tool invocation to finish;
    do not create a second session because the first invocation yielded without its final result.
    A device_busy error may mean the earlier creation succeeded. Recover its original response
    or stop and ask the owner; never take over or close another client's session.
    Require interactionReady == true before acting. Missing readiness fields are errors.
    Observe returns stateId:string, texts:string[], actions:[{action:{type,selector,text?},risk,reason}].
    Copy actions[i].action into cuyscout_execute's action argument and add sessionId.
    For typeElement replace <text> with the intended input. Never invent selectors or coordinates.
    Observe AFTER completing or changing form fields. A summary may appear inline on the same form.
    Never assume pay/pagar/confirm opens a review screen: it may execute the final action immediately.
    If the summary is missing, STOP. Record assertText for observed service/recipient, reference and
    amount BEFORE the final tap; observe alone does not record assertions for replay.
    Execute each check as {"type":"assertText","selector":{"strategy":"accessibilityIdentifier",
    "value":"observed_summary_id"},"expected":"exact observed summary"}; stop on failure.
    Every value the goal names (source/destination account, service, amount) must be chosen
    explicitly and seen in the summary; a value the app preselects does not count as chosen unless
    it matches. If nothing matches exactly (typo, nickname), pick the closest and say so; if truly
    ambiguous, stop and ask. Never report success while a requested value is missing on screen.
    Verify visible texts against the goal before irreversible actions. An operation number may only
    exist after payment: validate the summary before, then the receipt and operation number after.
    Do not automatically retry payments after timeouts; observe the current state first.
    Empty texts/actions immediately after a tap may be a transition. Use waitFor on the observed
    destination, or bounded observe-only polling; never repeat the tap to fix a transient empty read.
    Export with cuyscout_export_appium_typescript before ending the session. Replace redacted values
    with runtime variables and add assertions; export is not proof of compilation or successful replay.
    The export is an Appium/WebdriverIO test, not a CuyScout MCP client. It needs an Appium server,
    webdriverio and tsx: run npx tsx replay.ts directly. Do not rewrite its helpers or change native
    existence waits to waitForDisplayed; keyboard visibility differs across drivers. Supply IOS_UDID,
    IOS_BUNDLE_ID, APPIUM_HOST/PORT, CUYSCOUT_REPLAY_AUTHORIZED=yes and CUYSCOUT_REPLAY_VALUES
    (zero-based action paths such as {"0.text":"input","5.expected":"expected summary"}).
    Export preserves attempts, including successful taps that did not change the screen. Do not
    blindly replay duplicate navigation taps: wait for the observed destination control first;
    retry only a reversible navigation action, conditionally, if the destination remains absent
    and the original control is still visible. Never retry a payment automatically.
    Wait for controls after transitions and assert observed summary/receipt identifiers and values.
    Keep assertions parameterized (escape regex input or compare normalized exact values).
    Replaying may repeat irreversible effects: require explicit authorization and a fresh demo
    installation. If no replay environment/authorization is available, report UNVERIFIED, not passed.
    Close with cuyscout_end_session in finally even when assertions fail.
    A connection failure can be a sandbox/network permission issue, not a server crash. Check
    connectivity/permissions; never recreate a session or retry a payment to repair connectivity.
    """

    public static var help: [String: Any] { [
        "version": 1, "instructions": instructions,
        "workflow": ["cuyscout_create_session", "cuyscout_set_timeouts", "cuyscout_session_readiness", "cuyscout_observe", "cuyscout_execute", "cuyscout_validate_test_plan", "cuyscout_export_appium_typescript", "cuyscout_end_session"],
        "exampleObservation": ["stateId": "state:example", "changed": true, "context": "NATIVE_APP", "title": "Example", "texts": ["amount_label: S/ 120.00"], "actions": [["risk": "medium", "reason": "Editable control", "action": ["type": "typeElement", "selector": ["strategy": "accessibilityIdentifier", "value": "observed_field_id"], "text": "<text>"]]]],
        "exampleExecuteArguments": ["sessionId": "<active sessionId>", "action": ["type": "typeElement", "selector": ["strategy": "accessibilityIdentifier", "value": "observed_field_id"], "text": "user input"]],
        "exampleTimeoutArguments": ["sessionId": "<active sessionId>", "timeouts": ["implicit": 8000]],
        "http": ["help": "GET /agent-help", "create": "POST /session", "readiness": "GET /session/:id/readiness", "observe": "GET /session/:id/observe", "execute": "POST /session/:id/actions", "decide": "POST /session/:id/decide (only when agent-state.decision is present: Laya picks the control for a step)", "decisionSwitch": "GET|POST /decision/laya", "validate": "GET /session/:id/recording/plan/validate", "export": "GET /session/:id/recording/appium/typescript (plain text)", "exportArtifact": "GET /session/:id/artifacts", "replayValues": "POST /session/:id/recording/replay-values", "importArtifact": "POST /artifacts/import", "replayArtifact": "POST /artifacts/:id/replay", "close": "DELETE /session/:id"]
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
