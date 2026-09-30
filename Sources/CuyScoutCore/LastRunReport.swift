import Foundation

/// Resultado de la última corrida de un agente sobre un escenario, que escribe
/// `scripts/close-session.sh` en `output/<escenario>.last-run.json`. Distingue "la app
/// falló" de "el entorno no dejó probar" (servicio caído, dispositivo), que no es un fallo
/// del escenario.
public struct LastRunReport: Codable, Sendable, Equatable {
    public enum Status: String, Codable, Sendable {
        case recorded
        case blockedEnvironment = "blocked_environment"
        case failed
        case discarded
    }

    public let scenario: String
    public let status: Status
    public let sessionId: String?
    public let finishedAt: String?
    public let reason: String?
    public let step: String?
    public let screenTexts: [String]?

    public static func fileName(for scenario: String) -> String { "\(scenario).last-run.json" }

    public static func load(scenario: String, outputDirectory: URL) -> LastRunReport? {
        let file = outputDirectory.appendingPathComponent(fileName(for: scenario))
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(LastRunReport.self, from: data)
    }

    public var finishedDate: Date? { finishedAt.flatMap { ISO8601DateFormatter().date(from: $0) } }

    public var title: String {
        switch status {
        case .recorded: "Grabada por el agente"
        case .blockedEnvironment: "Bloqueado por entorno"
        case .failed: "Falló"
        case .discarded: "Descartada"
        }
    }

    /// Motivo legible (`servicio_no_disponible` → "servicio no disponible").
    public var reasonText: String? { reason.map { $0.replacingOccurrences(of: "_", with: " ") } }
}
