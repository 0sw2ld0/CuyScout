import Foundation

/// Only a recognized password-saving prompt may be dismissed automatically.
/// An arbitrary alert must remain a test failure, never an implicit acceptance.
enum ReplayInterruption {
    static func mayRetry(_ action: ScoutAction) -> Bool {
        switch action {
        case .assertVisible, .assertText, .waitFor, .findElement, .findElements,
             .accessibilityTree, .accessibilityTreeWithOptions, .screenshot:
            return true
        default:
            return false
        }
    }

    static func declinePasswordSaving(_ alert: AlertSnapshot) -> String? {
        let message = alert.text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let passwordTerms = ["password", "contrasena", "clave"]
        let saveTerms = ["save", "guardar"]
        guard passwordTerms.contains(where: message.contains), saveTerms.contains(where: message.contains) else { return nil }
        let declineLabels = ["not now", "ahora no", "don't save", "do not save", "no guardar", "no, gracias", "cancel", "cancelar"]
        return alert.buttons.first { button in
            let normalized = button.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return declineLabels.contains(normalized)
        }
    }
}
