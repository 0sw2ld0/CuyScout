import Foundation

public enum AppiumExportFormat: String, CaseIterable, Sendable {
    case typescript
    case python

    public var fileExtension: String {
        switch self {
        case .typescript: "ts"
        case .python: "py"
        }
    }

    public var displayName: String {
        switch self {
        case .typescript: "TypeScript"
        case .python: "Python"
        }
    }

    public func source(fromArtifactData data: Data) throws -> String {
        let artifact: SessionArtifactBundle
        do { artifact = try JSONDecoder().decode(SessionArtifactBundle.self, from: data) }
        catch { throw ScoutError.invalidRequest("No se pudo leer el artefacto CuyScout: \(error.localizedDescription)") }
        guard artifact.schemaVersion == "cuyscout.session-artifact.v1" else {
            throw ScoutError.invalidRequest("Versión de artefacto CuyScout no compatible")
        }
        guard let recording = artifact.recording, !recording.steps.isEmpty else {
            throw ScoutError.invalidRequest("Este artefacto no contiene una prueba grabada para exportar")
        }
        // Se regenera desde los pasos: un artefacto antiguo trae el código que generó la versión
        // de CuyScout de entonces (sin esperas, repitiendo intentos fallidos).
        let current = RecordedSession(sessionID: recording.sessionID, startedAt: recording.startedAt, stoppedAt: recording.stoppedAt, steps: recording.steps)
        let source = switch self {
        case .typescript: current.generatedAppiumTypeScript
        case .python: current.generatedAppiumPython
        }
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ScoutError.invalidRequest("La exportación Appium \(displayName) está vacía")
        }
        return source
    }
}
