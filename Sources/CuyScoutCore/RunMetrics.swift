import Foundation

/// Cuánto tardó y cuánto le costó al agente una corrida, medido desde el gateway: el tiempo
/// total y por fase, cuántos comandos usó y el volumen que CuyScout le devolvió, que es lo que
/// entra al contexto del modelo. Los tokens son una estimación (≈ 4 caracteres por token, y
/// cada captura cuenta como imagen): sirven para comparar corridas, no son la factura.
public struct RunMetrics: Codable, Sendable, Equatable {
    /// Desde que se creó la sesión hasta el cierre.
    public var totalSeconds: Int
    /// Hasta que la sesión quedó lista (dispositivo, app y runner).
    public var preparationSeconds: Int?
    /// Tiempo en que el gateway estuvo atendiendo comandos del agente (dispositivo + app).
    public var deviceSeconds: Int
    /// El resto: el agente pensando entre comandos.
    public var agentSeconds: Int
    public var requests: Int
    public var observations: Int
    public var actions: Int
    public var failures: Int
    public var screenshots: Int
    /// Bytes de texto devueltos al agente.
    public var bytesToAgent: Int
    public var estimatedTokens: Int

    /// Tokens que se estiman por cada captura que el agente pidió (una imagen de iPhone).
    public static let tokensPerScreenshot = 1_500

    public init(totalSeconds: Int, preparationSeconds: Int?, deviceSeconds: Int, agentSeconds: Int, requests: Int, observations: Int,
                actions: Int, failures: Int, screenshots: Int, bytesToAgent: Int, estimatedTokens: Int) {
        self.totalSeconds = totalSeconds; self.preparationSeconds = preparationSeconds; self.deviceSeconds = deviceSeconds
        self.agentSeconds = agentSeconds; self.requests = requests; self.observations = observations; self.actions = actions
        self.failures = failures; self.screenshots = screenshots; self.bytesToAgent = bytesToAgent; self.estimatedTokens = estimatedTokens
    }

    /// «12 min 4 s», «48 s».
    public static func duration(_ seconds: Int) -> String {
        seconds >= 60 ? "\(seconds / 60) min\(seconds % 60 == 0 ? "" : " \(seconds % 60) s")" : "\(seconds) s"
    }

    /// «~45 k tokens», «~800 tokens».
    public static func tokens(_ value: Int) -> String {
        value >= 1_000 ? "~\(Int((Double(value) / 1_000).rounded())) k tokens" : "~\(value) tokens"
    }

    public var summary: String {
        "\(Self.duration(totalSeconds)) · \(requests) comandos · \(Self.tokens(estimatedTokens))"
    }
}

/// Acumulador por sesión (lo llena el gateway con cada petición del agente).
struct RunMetricsAccumulator: Sendable {
    let startedAt: Date
    var readyAt: Date?
    var requests = 0
    var observations = 0
    var actions = 0
    var failures = 0
    var screenshots = 0
    var bytesToAgent = 0
    var deviceMilliseconds = 0

    /// Peticiones del agente sobre la sesión (no las del runner: `/bridge`).
    mutating func record(route: String, method: String, status: Int, milliseconds: Int, responseBytes: Int) {
        requests += 1
        deviceMilliseconds += max(0, milliseconds)
        if status >= 400 { failures += 1 }
        let isScreenshot = route.hasSuffix("/screenshot") || route.contains("/screenshot/")
        if isScreenshot { screenshots += 1 } else { bytesToAgent += max(0, responseBytes) }
        if route.hasSuffix("/observe") || route.hasSuffix("/agent-state") || route.hasSuffix("/source") || route.hasSuffix("/readiness") {
            observations += 1
        } else if method == "POST", route.hasSuffix("/actions") || route.contains("/element") || route.hasSuffix("/decide") {
            actions += 1
        }
    }

    func metrics(now: Date = Date()) -> RunMetrics {
        let total = Int(now.timeIntervalSince(startedAt))
        let device = deviceMilliseconds / 1_000
        return RunMetrics(totalSeconds: total, preparationSeconds: readyAt.map { Int($0.timeIntervalSince(startedAt)) },
                          deviceSeconds: device, agentSeconds: max(0, total - device - (readyAt.map { Int($0.timeIntervalSince(startedAt)) } ?? 0)),
                          requests: requests, observations: observations, actions: actions, failures: failures, screenshots: screenshots,
                          bytesToAgent: bytesToAgent, estimatedTokens: bytesToAgent / 4 + screenshots * RunMetrics.tokensPerScreenshot)
    }
}
