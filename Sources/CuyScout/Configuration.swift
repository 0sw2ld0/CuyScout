import Foundation
import Darwin

enum ScoutConfigurationError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { "Configuración inválida: \(String(describing: self))" }
}

enum ScoutConfiguration {
    static func applyFromDefaultFile() throws {
        let path = ProcessInfo.processInfo.environment["CUYSCOUT_CONFIG"] ?? ".cuyscout.yaml"
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: url.path), let text = try? String(contentsOf: url, encoding: .utf8) {
            let values = parse(text)
            try validateInteger(values["server.port"], name: "server.port", minimum: 1, maximum: 65535)
            let mappings: [String: String] = [
                "server.token": "CUYSCOUT_TOKEN",
                "server.tokenScopes": "CUYSCOUT_TOKEN_SCOPES",
                "server.logFormat": "CUYSCOUT_LOG_FORMAT",
                "server.profile": "CUYSCOUT_PROFILE",
                "server.bindAddress": "CUYSCOUT_BIND_ADDRESS",
                "server.tls.cert": "CUYSCOUT_TLS_CERT",
                "server.tls.key": "CUYSCOUT_TLS_KEY",
                "artifacts.directory": "CUYSCOUT_ARTIFACT_DIR",
                "artifacts.retention": "CUYSCOUT_ARTIFACT_RETENTION",
                "session.autosaveInterval": "CUYSCOUT_AUTOSAVE_INTERVAL",
                "session.eventRetention": "CUYSCOUT_EVENT_RETENTION",
                "session.redactSensitive": "CUYSCOUT_REDACT_SENSITIVE"
            ]
            for (key, environmentKey) in mappings where ProcessInfo.processInfo.environment[environmentKey] == nil {
                if let value = values[key] { setenv(environmentKey, value, 0) }
            }
            if ProcessInfo.processInfo.environment["CUYSCOUT_CONFIG"] == nil { setenv("CUYSCOUT_CONFIG", path, 0) }
        }
        applyProfileDefaults()
        try validate()
    }

    private static func validate() throws {
        let environment = ProcessInfo.processInfo.environment
        if let raw = environment["CUYSCOUT_PROFILE"], !["local", "ci", "device-farm"].contains(raw.lowercased()) { throw ScoutConfigurationError.invalid("server.profile debe ser local, ci o device-farm") }
        if let raw = environment["CUYSCOUT_BIND_ADDRESS"], raw.isEmpty || raw.contains(where: { $0 == " " || $0 == "\n" }) { throw ScoutConfigurationError.invalid("server.bindAddress debe ser una dirección válida") }
        let bindAddress = environment["CUYSCOUT_BIND_ADDRESS"] ?? "127.0.0.1"
        if !["127.0.0.1", "localhost", "::1"].contains(bindAddress.lowercased()), environment["CUYSCOUT_TOKEN"]?.isEmpty != false { throw ScoutConfigurationError.invalid("CUYSCOUT_TOKEN es obligatorio cuando server.bindAddress no es local") }
        if let raw = environment["CUYSCOUT_LOG_FORMAT"], raw.lowercased() != "json" { throw ScoutConfigurationError.invalid("server.logFormat solo admite json") }
        try validateInteger(environment["CUYSCOUT_PORT_START"], name: "CUYSCOUT_PORT_START", minimum: 1024, maximum: 65535)
        try validateInteger(environment["CUYSCOUT_PORT_COUNT"], name: "CUYSCOUT_PORT_COUNT", minimum: 1, maximum: 10000)
        try validateInteger(environment["CUYSCOUT_ARTIFACT_RETENTION"], name: "artifacts.retention", minimum: 0, maximum: nil)
        try validateInteger(environment["CUYSCOUT_AUTOSAVE_INTERVAL"], name: "session.autosaveInterval", minimum: 0, maximum: nil)
        try validateInteger(environment["CUYSCOUT_EVENT_RETENTION"], name: "session.eventRetention", minimum: 10, maximum: 10000)
        if let raw = environment["CUYSCOUT_REDACT_SENSITIVE"], !["true", "false"].contains(raw.lowercased()) { throw ScoutConfigurationError.invalid("session.redactSensitive debe ser true o false") }
        let tlsCert = environment["CUYSCOUT_TLS_CERT"]; let tlsKey = environment["CUYSCOUT_TLS_KEY"]
        if (tlsCert != nil) != (tlsKey != nil) { throw ScoutConfigurationError.invalid("server.tls.cert y server.tls.key deben configurarse juntos") }
        if let cert = tlsCert, !FileManager.default.fileExists(atPath: cert) { throw ScoutConfigurationError.invalid("server.tls.cert no existe: \(cert)") }
        if let key = tlsKey, !FileManager.default.fileExists(atPath: key) { throw ScoutConfigurationError.invalid("server.tls.key no existe: \(key)") }
    }

    private static func validateInteger(_ raw: String?, name: String, minimum: Int, maximum: Int?) throws {
        guard let raw else { return }; guard let value = Int(raw), value >= minimum, maximum == nil || value <= maximum! else { throw ScoutConfigurationError.invalid("\(name) debe ser un entero entre \(minimum) y \(maximum.map(String.init) ?? "sin máximo")") }
    }

    private static func applyProfileDefaults() {
        let profile = ProcessInfo.processInfo.environment["CUYSCOUT_PROFILE"]?.lowercased() ?? "local"
        setenvIfMissing("CUYSCOUT_PROFILE", profile)
        switch profile {
        case "ci":
            setenvIfMissing("CUYSCOUT_LOG_FORMAT", "json")
            setenvIfMissing("CUYSCOUT_REDACT_SENSITIVE", "true")
            setenvIfMissing("CUYSCOUT_AUTOSAVE_INTERVAL", "5")
        case "device-farm":
            setenvIfMissing("CUYSCOUT_LOG_FORMAT", "json")
            setenvIfMissing("CUYSCOUT_REDACT_SENSITIVE", "true")
            setenvIfMissing("CUYSCOUT_EVENT_RETENTION", "1000")
        default: break
        }
    }

    private static func setenvIfMissing(_ key: String, _ value: String) {
        guard ProcessInfo.processInfo.environment[key] == nil else { return }
        setenv(key, value, 0)
    }

    static func configuredPort(arguments: [String]) -> UInt16 {
        if let argument = arguments.dropFirst().first, let port = UInt16(argument) { return port }
        let path = ProcessInfo.processInfo.environment["CUYSCOUT_CONFIG"] ?? ".cuyscout.yaml"
        guard let text = try? String(contentsOfFile: path, encoding: .utf8), let raw = parse(text)["server.port"], let port = UInt16(raw) else { return 4723 }
        return port
    }

    private static func parse(_ text: String) -> [String: String] {
        var result: [String: String] = [:]; var sections: [String] = []
        for rawLine in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let line = String(rawLine); let withoutComment = line.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? line
            let trimmed = withoutComment.trimmingCharacters(in: .whitespacesAndNewlines); guard !trimmed.isEmpty else { continue }
            let indentation = withoutComment.prefix { $0 == " " }.count
            guard let separator = trimmed.firstIndex(of: ":") else { continue }
            let key = trimmed[..<separator].trimmingCharacters(in: .whitespaces); let rawValue = trimmed[trimmed.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            let depth = indentation / 2
            while sections.count > depth { sections.removeLast() }
            if rawValue.isEmpty { sections.append(String(key)); continue }
            let value = rawValue.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            result[(sections + [String(key)]).joined(separator: ".")] = value
        }
        return result
    }
}
