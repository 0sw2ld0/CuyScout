import Foundation
import CuyScoutCore

/// Explicit gateway mode keeps all advertised tools on the same HTTP engine/runner.
final class GatewayClient {
    static let supported: Set<String> = ["cuyscout_help", "cuyscout_status", "cuyscout_doctor", "cuyscout_list_devices", "cuyscout_list_sessions", "cuyscout_create_session", "cuyscout_end_session", "cuyscout_set_timeouts", "cuyscout_session_readiness", "cuyscout_observe", "cuyscout_decide", "cuyscout_execute", "cuyscout_validate_test_plan", "cuyscout_export_appium_typescript"]
    let address: String
    let profileToken: String?
    init(address: String, profileToken: String? = nil) { self.address = address; self.profileToken = profileToken }
    private final class Reply: @unchecked Sendable {
        // Written by callback, read only after semaphore completion.
        var data: Data?; var response: URLResponse?; var error: Error?
    }
    func call(_ name: String, args: [String: Any]) throws -> Any {
        guard Self.supported.contains(name) else { throw ScoutError.unsupported("Tool unavailable in gateway mode; use tools/list") }
        guard let base = URL(string: address), ["http", "https"].contains(base.scheme), base.host != nil,
              base.user == nil, base.password == nil, base.query == nil, base.fragment == nil else {
            throw ScoutError.invalidRequest("CUYSCOUT_GATEWAY_URL must be an HTTP(S) URL without credentials, query or fragment")
        }
        func required(_ key: String) throws -> String {
            guard let value = args[key] as? String, !value.isEmpty else { throw ScoutError.invalidRequest("Missing argument: \(key)") }; return value
        }
        let global: Set<String> = ["cuyscout_status", "cuyscout_doctor", "cuyscout_list_devices", "cuyscout_list_sessions", "cuyscout_create_session"]
        let sid = global.contains(name) ? "" : try required("sessionId").addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        var path = "/session/\(sid)"; var method = "GET"; var body: [String: Any]?
        switch name {
        case "cuyscout_status": path = "/status"
        case "cuyscout_doctor": path = "/doctor"
        case "cuyscout_list_devices": path = "/devices"
        case "cuyscout_list_sessions": path = "/sessions"
        case "cuyscout_create_session":
            path = "/session"; method = "POST"
            var capabilities: [String: Any] = ["platformName": "iOS", "appium:automationName": "XCUITest"]
            for (input, capability) in [("appPath", "appium:app"), ("deviceId", "appium:udid"), ("bundleIdentifier", "appium:bundleId"), ("driverId", "appium:driverId"), ("waitSeconds", "appium:sessionWaitTimeout"), ("noReset", "appium:noReset"), ("projectDir", "cuyscout:projectDir")] {
                if let value = args[input] { capabilities[capability] = value }
            }
            body = ["capabilities": ["alwaysMatch": capabilities]]
        case "cuyscout_end_session": method = "DELETE"
        case "cuyscout_set_timeouts":
            path += "/timeouts"; method = "POST"
            guard let timeouts = args["timeouts"] as? [String: Any] else { throw ScoutError.invalidRequest("timeouts object required") }; body = timeouts
        case "cuyscout_session_readiness": path += "/readiness"
        case "cuyscout_observe": path += "/observe?maxActions=\(min(200, max(1, args["maxActions"] as? Int ?? 20)))"
        case "cuyscout_decide":
            path += "/decide"; method = "POST"
            var input = args; input.removeValue(forKey: "sessionId"); body = input
        case "cuyscout_execute":
            path += "/actions"; method = "POST"
            guard let action = args["action"] as? [String: Any], action["type"] is String else { throw ScoutError.invalidRequest("action.type required; copy observe.actions[i].action, not the suggestion wrapper") }
            _ = try JSONDecoder().decode(ScoutAction.self, from: JSONSerialization.data(withJSONObject: action))
            body = action
        case "cuyscout_validate_test_plan": path += "/recording/plan/validate"
        case "cuyscout_export_appium_typescript": path += "/recording/appium/typescript"
        default: throw ScoutError.unsupported(name)
        }
        guard let url = URL(string: address.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path) else { throw ScoutError.invalidRequest("Invalid gateway URL") }
        var request = URLRequest(url: url); request.httpMethod = method; request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = ProcessInfo.processInfo.environment["CUYSCOUT_TOKEN"] ?? profileToken { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForResource = 120
        let client = URLSession(configuration: config)
        defer { client.invalidateAndCancel() }
        let reply = Reply(); let done = DispatchSemaphore(value: 0)
        client.dataTask(with: request) { data, response, error in
            reply.data = data; reply.response = response; reply.error = error; done.signal()
        }.resume()
        done.wait()
        if let error = reply.error {
            throw ScoutError.commandFailed("Gateway connection failed (\((error as NSError).code)). Check configured URL, gateway process and sandbox/network permissions. Do not recreate sessions or retry irreversible actions; their outcome may be unknown.")
        }
        guard let response = reply.response as? HTTPURLResponse else { throw ScoutError.commandFailed("Gateway returned no HTTP response") }
        let data = reply.data ?? Data()
        guard (200..<300).contains(response.statusCode) else {
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let value = object?["value"] as? [String: Any]
            let message = LessonRedactor.redact(String((value?["message"] as? String ?? "").prefix(500)))
            if let hint = value?["hint"] as? String {
                throw ScoutError.commandFailed("Gateway HTTP \(response.statusCode): \(value?["error"] as? String ?? "request_failed"). \(message) Siguiente paso: \(hint)")
            }
            throw ScoutError.commandFailed("Gateway HTTP \(response.statusCode): \(value?["error"] as? String ?? "request_failed"). \(message) Observe/readiness before retry; invalid session id requires a new session only after confirming the old session is closed.")
        }
        if name == "cuyscout_export_appium_typescript" { return ["format": "appium-webdriverio-typescript", "code": String(decoding: data, as: UTF8.self)] }
        let decoded = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        let value = (decoded as? [String: Any])?["value"] ?? decoded
        return value is NSNull ? ["ok": true] : value
    }
}
