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
        let source = switch self {
        case .typescript: recording.generatedAppiumTypeScript
        case .python: recording.generatedAppiumPython
        }
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ScoutError.invalidRequest("La exportación Appium \(displayName) está vacía")
        }
        return source
    }
}
