import Foundation

public struct LessonLearningReport: Codable, Sendable, Equatable {
    public let candidates: [LearnedLesson]
    public let persisted: [LearnedLesson]
    public init(candidates: [LearnedLesson], persisted: [LearnedLesson] = []) { self.candidates = candidates; self.persisted = persisted }
}

public enum LessonInference {
    public static func infer(steps: [RecordedStep], exploration: ExplorationReport? = nil, scope: LessonScope, projectKey: String? = nil, sessionID: String? = nil) -> [LearnedLesson] {
        var lessons: [LearnedLesson] = []
        let contextSessionID = scope == .session ? sessionID : nil
        let contextProjectKey = scope == .project ? projectKey : nil

        if exploration?.status == .loopDetected {
            lessons.append(LearnedLesson(scope: scope, projectKey: contextProjectKey, sessionID: contextSessionID, title: "Evitar ciclo de exploración detectado", observation: "La exploración volvió a estados o acciones ya recorridos hasta activar la protección anti-bucle.", recommendation: "Cambiar de acción, restaurar un checkpoint o finalizar la ruta cuando el estado no cambie.", evidence: "reason=\(exploration?.reason ?? "loop_detected"); repeatedStates=\(exploration?.repeatedStateCount ?? 0)", tags: ["exploration", "loop", "checkpoint"], confidence: 0.95))
        }

        let failures = Dictionary(grouping: steps.filter { !$0.success }, by: { failureCategory($0.error) })
        for (category, values) in failures where values.count >= 2 {
            lessons.append(LearnedLesson(scope: scope, projectKey: contextProjectKey, sessionID: contextSessionID, title: "Fallo recurrente de \(category)", observation: "La sesión registró \(values.count) fallos clasificados como \(category).", recommendation: recommendation(for: category), evidence: "category=\(category); occurrences=\(values.count)", tags: ["failure", category], confidence: min(0.95, 0.7 + Double(values.count) * 0.05)))
        }

        if keyboardObstructionLikely(in: steps) {
            lessons.append(LearnedLesson(scope: scope, projectKey: contextProjectKey, sessionID: contextSessionID, title: "El teclado puede ocultar controles después de escribir", observation: "Una interacción de elemento falló poco después de rellenar un campo.", recommendation: "Cerrar el teclado o desplazar la vista antes de buscar y pulsar el siguiente control.", evidence: "pattern=type_then_element_failure", tags: ["keyboard", "form", "scroll"], confidence: 0.82))
        }

        let slowSteps = steps.filter { $0.durationMilliseconds >= 2_000 }
        if slowSteps.count >= 2 {
            lessons.append(LearnedLesson(scope: scope, projectKey: contextProjectKey, sessionID: contextSessionID, title: "La interfaz requiere sincronización explícita", observation: "Se observaron \(slowSteps.count) comandos de al menos dos segundos.", recommendation: "Esperar una condición semántica de estabilidad o visibilidad en lugar de reintentar inmediatamente.", evidence: "slowCommands=\(slowSteps.count); thresholdMs=2000", tags: ["timing", "wait", "stability"], confidence: 0.8))
        }
        return lessons
    }

    /// Clasifica por el texto del fallo tal como queda grabado. CuyScout emite sus mensajes
    /// en español y los códigos W3C en inglés, así que se reconocen ambos vocabularios: con
    /// solo las palabras inglesas, un selector roto se aprendía como "fallo del producto" y
    /// la recomendación resultante mandaba al agente a reportar un bug inexistente.
    private static func failureCategory(_ error: String?) -> String {
        let value = (error ?? "")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        func any(_ needles: [String]) -> Bool { needles.contains { value.contains($0) } }
        if any(["no such element", "stale element", "not visible", "hittable",
                "no se encontro el elemento", "elemento no existe", "referencia de elemento"]) { return "selector" }
        if any(["timeout", "bridge", "device", "connection",
                "esperando respuesta", "puente", "runner", "simulador"]) { return "infrastructure" }
        if any(["invalid", "unsupported", "not registered",
                "no soportada", "requiere", "registra primero", "invalida"]) { return "environment" }
        return "product"
    }

    private static func recommendation(for category: String) -> String {
        switch category {
        case "selector": return "Actualizar o reparar el selector usando identidad y atributos semánticos estables."
        case "infrastructure": return "Comprobar la salud del runner y reintentar únicamente como fallo de infraestructura."
        case "environment": return "Validar capabilities, contexto y dependencias antes de repetir la acción."
        default: return "Conservar la evidencia y reportar el comportamiento como posible fallo del producto."
        }
    }

    private static func keyboardObstructionLikely(in steps: [RecordedStep]) -> Bool {
        for index in steps.indices where !steps[index].success && failureCategory(steps[index].error) == "selector" {
            let start = max(0, index - 2)
            if steps[start..<index].contains(where: { isTyping($0.action) }) { return true }
        }
        return false
    }

    private static func isTyping(_ action: ScoutAction) -> Bool { if case .type = action { return true }; if case .typeElement = action { return true }; return false }
}
