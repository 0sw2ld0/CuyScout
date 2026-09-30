import Foundation

/// Motor de decisión rápida opcional (Laya, API compatible con Jev) que corre como servicio
/// local compartido. Está **desactivado por defecto**: CuyScout no lo necesita para operar.
/// Activo, `/doctor` lo reporta, `agent-state` lo anuncia y `POST /session/:id/decide` lo usa
/// para elegir el control que cumple un paso sin gastar tokens del LLM.
public enum LayaService {
    public static let environmentKey = "CUYSCOUT_LAYA_URL"
    public static let enabledKey = "CUYSCOUT_LAYA_ENABLED"
    public static let defaultURL = URL(string: "http://127.0.0.1:8791")!

    public static func configuredURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        guard let raw = environment[environmentKey]?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        return URL(string: raw.hasSuffix("/") ? String(raw.dropLast()) : raw)
    }

    public static func configuredEnabled(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        ["true", "1", "yes"].contains(environment[enabledKey]?.lowercased() ?? "")
    }

    public static func isValid(_ raw: String) -> Bool {
        guard let url = URL(string: raw), let scheme = url.scheme?.lowercased() else { return false }
        return ["http", "https"].contains(scheme) && url.host != nil
    }

    /// `GET <url>/health` con timeout corto; el detalle incluye los checkpoints cargados.
    public static func check(url: URL?, enabled: Bool = true, timeout: TimeInterval = 2) -> DoctorCheck {
        guard enabled else {
            return DoctorCheck(name: "laya", available: false, detail: "Desactivado (opcional): actívalo con decision.layaEnabled, \(enabledKey)=true o POST /decision/laya")
        }
        guard let url else {
            return DoctorCheck(name: "laya", available: false, detail: "No configurado (opcional): define decision.layaURL o \(environmentKey)")
        }
        let health = self.health(url: url, timeout: timeout)
        guard health.reachable else {
            return DoctorCheck(name: "laya", available: false, detail: "\(url.absoluteString) no responde; arráncalo con laya-service.sh start")
        }
        return DoctorCheck(name: "laya", available: true, detail: "\(url.absoluteString) responde; cargados: \(health.loaded.joined(separator: ", "))")
    }

    public static func health(url: URL, timeout: TimeInterval = 2) -> (reachable: Bool, loaded: [String]) {
        var request = URLRequest(url: url.appendingPathComponent("health"))
        request.timeoutInterval = timeout
        guard let (status, body) = send(request, timeout: timeout), status == 200 else { return (false, []) }
        let loaded = ((try? JSONSerialization.jsonObject(with: body)) as? [String: Any])?["loaded"] as? [String] ?? []
        return (true, loaded)
    }

    static func send(_ request: URLRequest, timeout: TimeInterval) -> (Int, Data)? {
        let done = DispatchSemaphore(value: 0)
        var body: Data?
        var status = 0
        URLSession.direct.dataTask(with: request) { data, response, _ in
            body = data; status = (response as? HTTPURLResponse)?.statusCode ?? 0; done.signal()
        }.resume()
        guard done.wait(timeout: .now() + timeout + 1) == .success, status != 0 else { return nil }
        return (status, body ?? Data())
    }
}

/// Estado del interruptor de Laya, compartido por el gateway (`/doctor`, `agent-state`,
/// `/decide`). Arranca desde la configuración y se puede cambiar en caliente.
public struct LayaSettings: Codable, Sendable, Equatable {
    public let enabled: Bool
    public let url: String
    public init(enabled: Bool, url: String) { self.enabled = enabled; self.url = url }
}

public final class LayaSwitch: @unchecked Sendable {
    public static let shared = LayaSwitch()
    private let lock = NSLock()
    private var enabled: Bool
    private var url: URL

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        enabled = LayaService.configuredEnabled(environment: environment)
        url = LayaService.configuredURL(environment: environment) ?? LayaService.defaultURL
    }

    public var settings: LayaSettings { lock.lock(); defer { lock.unlock() }; return LayaSettings(enabled: enabled, url: url.absoluteString) }

    @discardableResult
    public func update(enabled: Bool?, url raw: String?) throws -> LayaSettings {
        var newURL: URL?
        if let raw {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            guard LayaService.isValid(trimmed), let parsed = URL(string: trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed) else {
                throw ScoutError.invalidRequest("url debe ser http(s), por ejemplo http://127.0.0.1:8791")
            }
            newURL = parsed
        }
        lock.lock(); defer { lock.unlock() }
        if let enabled { self.enabled = enabled }
        if let newURL { url = newURL }
        return LayaSettings(enabled: self.enabled, url: url.absoluteString)
    }

    /// Cliente listo para decidir, o nil si Laya está desactivado.
    public func activeModel() -> DecisionModel? {
        let current = settings
        guard current.enabled, let url = URL(string: current.url) else { return nil }
        return LayaClient(url: url)
    }
}

/// Modelo que elige una opción entre varias y devuelve su confianza (0–1).
public protocol DecisionModel: Sendable {
    func choose(state: String, options: [String: String]) throws -> (choice: String, confidence: Double)
}

/// Cliente HTTP de `POST /v1/systemone` (pregunta `choice`).
public struct LayaClient: DecisionModel {
    public let url: URL
    public let model: String?
    public let timeout: TimeInterval
    public init(url: URL, model: String? = nil, timeout: TimeInterval = 10) { self.url = url; self.model = model; self.timeout = timeout }

    public func choose(state: String, options: [String: String]) throws -> (choice: String, confidence: Double) {
        var body: [String: Any] = ["state": state, "questions": ["accion": ["type": "choice", "instructions": "¿Qué acción cumple el paso?", "criteria": options]]]
        if let model { body["model"] = model }
        var request = URLRequest(url: url.appendingPathComponent("v1/systemone"))
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        guard let (status, data) = LayaService.send(request, timeout: timeout) else {
            throw ScoutError.commandFailed("Laya no responde en \(url.absoluteString); arráncalo con laya-service.sh start")
        }
        guard status == 200,
              let answer = (((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["answers"] as? [String: Any])?["accion"] as? [String: Any],
              let choice = answer["choice"] as? String else {
            throw ScoutError.commandFailed("Laya respondió \(status) sin una elección válida")
        }
        let probabilities = answer["probabilities"] as? [String: Double] ?? [:]
        return (choice, probabilities[choice] ?? probabilities.values.max() ?? 0)
    }
}

extension URLSession {
    /// Sesión que ignora el proxy del sistema. CuyScout solo habla con servicios de esta Mac
    /// (gateway, Laya) o de su red local; un proxy corporativo (p. ej. un PAC) puede capturar
    /// esas conexiones y cortarlas ("La conexión de red se ha perdido").
    public static let direct: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        return URLSession(configuration: configuration)
    }()
}
