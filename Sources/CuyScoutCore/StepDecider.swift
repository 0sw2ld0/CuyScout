import Foundation

/// Pedido de `POST /session/:id/decide`: qué paso cumplir en la pantalla actual.
public struct DecideRequest: Codable, Sendable, Equatable {
    /// Paso en lenguaje natural, corto y atómico («Tocar el botón para iniciar sesión»).
    public let step: String
    /// tocar | escribir | seleccionar | confirmar (también tap | type | select | confirm).
    public let intent: String?
    /// Formas de nombrar el valor que un «seleccionar» debe elegir («Cuywallet», «cuenta cuywallet»).
    public let options: [String]?
    /// Valores de selector ya usados o probados: no se vuelven a proponer.
    public let exclude: [String]?
    /// Valores que el paso NO debe elegir («distinta de la cuenta de origen»): se descartan por
    /// nombre antes de preguntar. Laya no entiende negaciones; esto lo resuelve sin adivinar.
    public let avoid: [String]?
    /// Una acción irreversible exige más confianza a Laya.
    public let irreversible: Bool?
    /// Confianza mínima para aceptar lo que elige Laya (0.35 por defecto; 0.6 si es irreversible).
    public let minConfidence: Double?
    /// Lo ya elegido en pasos anteriores, como contexto («origen: Cuywallet»).
    public let context: String?
    public init(step: String, intent: String? = nil, options: [String]? = nil, exclude: [String]? = nil, avoid: [String]? = nil, irreversible: Bool? = nil, minConfidence: Double? = nil, context: String? = nil) {
        self.step = step; self.intent = intent; self.options = options; self.exclude = exclude; self.avoid = avoid; self.irreversible = irreversible; self.minConfidence = minConfidence; self.context = context
    }
}

public struct DecisionCandidate: Codable, Sendable, Equatable {
    public let id: String
    public let label: String
    /// Acción lista para `POST /session/:id/actions` (en un campo, reemplaza `<text>` por el valor).
    public let action: ScoutAction
    public init(id: String, label: String, action: ScoutAction) { self.id = id; self.label = label; self.action = action }
}

public struct DecideResult: Codable, Sendable, Equatable {
    /// `chosen`: ejecuta `candidate.action`. `needs_llm`: elige tú entre `candidates`.
    public let decision: String
    /// Quién eligió: `match` (coincidencia determinista), `single_option` o `laya`.
    public let engine: String?
    public let reason: String
    public let candidate: DecisionCandidate?
    public let confidence: Double?
    /// La pantalla es un aviso del sistema que interrumpe el paso; descártalo y vuelve a decidir.
    public let interruption: Bool
    /// Opciones acotadas al paso (tipo de acción, sin navegación global ni repetidos).
    public let candidates: [DecisionCandidate]
    public let stateId: String
    public let latencyMs: Int
}

/// Cascada de decisión medida en el benchmark (Scripts/evidence/run-20260926-laya-benchmark):
/// coincidencia determinista → opción única → Laya con umbral → derivar al LLM. Nunca deja que
/// Laya adivine un valor que el paso nombra: si no hay coincidencia clara, deriva.
public struct StepDecider {
    public enum Intent: String { case tap = "tocar", type = "escribir", select = "seleccionar", confirm = "confirmar" }
    public static let defaultMinConfidence = 0.35
    public static let irreversibleMinConfidence = 0.6
    static let prefixes = ["btn": "botón", "button": "botón", "input": "campo", "field": "campo", "tab": "pestaña", "cell": "fila",
                           "switch": "interruptor", "link": "enlace", "label": "texto", "row": "fila", "card": "tarjeta", "item": "elemento"]

    let model: DecisionModel

    public init(model: DecisionModel) { self.model = model }

    public static func intent(_ raw: String?) throws -> Intent {
        switch raw.map(normalize) ?? "tocar" {
        case "tocar", "tap", "": return .tap
        case "escribir", "type": return .type
        case "seleccionar", "select": return .select
        case "confirmar", "confirm": return .confirm
        default: throw ScoutError.invalidRequest("intent debe ser tocar, escribir, seleccionar o confirmar; para verificar usa los textos de /observe")
        }
    }

    public func decide(_ request: DecideRequest, observation: AgentObservation) throws -> DecideResult {
        let started = Date()
        let step = request.step.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !step.isEmpty else { throw ScoutError.invalidRequest("step es obligatorio") }
        let intent = try Self.intent(request.intent)
        let options = Self.candidates(from: observation)
        func result(_ decision: String, _ engine: String?, _ reason: String, _ chosen: DecisionCandidate?, _ confidence: Double?, interruption: Bool = false, candidates: [DecisionCandidate]) -> DecideResult {
            DecideResult(decision: decision, engine: engine, reason: reason, candidate: chosen, confidence: confidence.map { ($0 * 1000).rounded() / 1000 },
                         interruption: interruption, candidates: candidates, stateId: observation.stateId, latencyMs: Int(Date().timeIntervalSince(started) * 1000))
        }

        if Self.isInterruption(observation, options) {
            if let (choice, confidence) = try? model.choose(state: "Descartar el aviso del sistema sin aceptar nada", options: Self.criteria(options)),
               confidence >= 0.5, let chosen = options.first(where: { $0.id == choice }) {
                return result("chosen", "laya", "system_alert_dismissed", chosen, confidence, interruption: true, candidates: options)
            }
            return result("needs_llm", nil, "system_alert_needs_choice", nil, nil, interruption: true, candidates: options)
        }

        let excluded = Set(request.exclude ?? [])
        let wantsTyping = intent == .type
        let avoided = (request.avoid ?? []).map(Self.normalize).filter { !$0.isEmpty }
        let candidates = options.filter { candidate in
            guard let selector = Self.selector(of: candidate.action), !excluded.contains(selector.value), !Self.isGlobalNavigation(selector) else { return false }
            guard avoided.isEmpty || Self.match([candidate], wanted: avoided) == nil else { return false }
            return wantsTyping == Self.isTyping(candidate.action)
        }
        guard !candidates.isEmpty else {
            let others = options.filter { Self.selector(of: $0.action).map { !excluded.contains($0.value) } ?? false }
            return result("needs_llm", nil, "no_candidates_for_intent", nil, nil, candidates: others)
        }
        let wanted = (request.options ?? []).map(Self.normalize).filter { !$0.isEmpty }
        if intent == .select, !wanted.isEmpty, let matched = Self.match(candidates, wanted: wanted) {
            return result("chosen", "match", "named_value_matched", matched, 1, candidates: candidates)
        }
        if candidates.count == 1 {
            return result("chosen", "single_option", "only_option_for_intent", candidates[0], 1, candidates: candidates)
        }
        // Si el paso nombra qué elegir y ninguna opción coincide, no se deja adivinar a Laya.
        if intent == .select, !wanted.isEmpty, candidates.allSatisfy({ Self.selector(of: $0.action)?.strategy == .label }) {
            return result("needs_llm", nil, "named_value_not_on_screen", nil, nil, candidates: candidates)
        }
        let context = request.context?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let state = "Paso a cumplir: \(step)" + (context.isEmpty ? "" : " (ya elegido: \(context))")
        let irreversible = request.irreversible == true || intent == .confirm
        let threshold = max(request.minConfidence ?? Self.defaultMinConfidence, irreversible ? Self.irreversibleMinConfidence : 0)
        do {
            let (choice, confidence) = try model.choose(state: state, options: Self.criteria(candidates))
            guard let chosen = candidates.first(where: { $0.id == choice }) else {
                return result("needs_llm", nil, "laya_invalid_choice", nil, confidence, candidates: candidates)
            }
            if confidence >= threshold { return result("chosen", "laya", "laya_confident", chosen, confidence, candidates: candidates) }
            return result("needs_llm", "laya", "low_confidence", chosen, confidence, candidates: candidates)
        } catch {
            return result("needs_llm", nil, "laya_unavailable: \(error.localizedDescription)", nil, nil, candidates: candidates)
        }
    }

    // MARK: - Opciones

    static func candidates(from observation: AgentObservation) -> [DecisionCandidate] {
        var labels: [String: String] = [:]
        for text in observation.texts {
            guard let range = text.range(of: ": ") else { continue }
            let key = String(text[..<range.lowerBound])
            if !key.contains(" ") { labels[key] = String(text[range.upperBound...]) }
        }
        return observation.actions.enumerated().compactMap { index, suggestion in
            guard let selector = selector(of: suggestion.action) else { return nil }
            let verb = isTyping(suggestion.action) ? "escribir en" : "tocar"
            let name: String
            if selector.strategy == .accessibilityIdentifier {
                let parts = selector.value.split(whereSeparator: { "_-.".contains($0) }).map(String.init)
                if let head = parts.first.flatMap({ prefixes[$0.lowercased()] }) { name = ([head] + parts.dropFirst()).joined(separator: " ") }
                else { name = "control " + parts.joined(separator: " ") }
            } else {
                name = selector.value
            }
            let extra = labels[selector.value].map { " (\($0))" } ?? ""
            return DecisionCandidate(id: "a\(index)", label: "\(verb) \(name)\(extra)", action: suggestion.action)
        }
    }

    static func criteria(_ candidates: [DecisionCandidate]) -> [String: String] {
        Dictionary(candidates.map { ($0.id, $0.label) }) { first, _ in first }
    }

    static func selector(of action: ScoutAction) -> ScoutSelector? {
        switch action {
        case .tapElement(let selector), .typeElement(let selector, _): return selector
        default: return nil
        }
    }

    static func isTyping(_ action: ScoutAction) -> Bool {
        if case .typeElement = action { return true }
        return false
    }

    static func isGlobalNavigation(_ selector: ScoutSelector) -> Bool {
        selector.value.contains(".") || ["barra de pestanas", "tab bar"].contains(normalize(selector.value))
    }

    /// Aviso del sistema: pocas acciones, todas por label, y un texto que pregunta.
    static func isInterruption(_ observation: AgentObservation, _ options: [DecisionCandidate]) -> Bool {
        let selectors = options.compactMap { selector(of: $0.action) }
        return !selectors.isEmpty && selectors.count <= 3 && selectors.allSatisfy { $0.strategy == .label }
            && observation.texts.contains { $0.trimmingCharacters(in: .whitespaces).hasSuffix("?") }
    }

    /// Elige la opción cuyas palabras aparecen más en alguna forma de nombrar lo pedido.
    static func match(_ candidates: [DecisionCandidate], wanted: [String]) -> DecisionCandidate? {
        var best: DecisionCandidate?; var bestScore = 0.0; var tie = false
        for candidate in candidates {
            let tokens = words(normalize(candidate.label), minimum: 3).filter { !["tocar", "control", "boton", "escribir", "campo"].contains($0) }
            guard !tokens.isEmpty else { continue }
            let score = wanted.map { want in
                let compact = want.replacingOccurrences(of: " ", with: "")
                return Double(tokens.filter { fuzzyContains(compact, $0) }.count) / Double(tokens.count)
            }.max() ?? 0
            if score > bestScore { best = candidate; bestScore = score; tie = false }
            else if score == bestScore && score > 0 { tie = true }
        }
        return bestScore >= 0.5 && !tie ? best : nil
    }

    // MARK: - Texto

    public static func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es"))
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func words(_ text: String, minimum: Int) -> [String] {
        text.split(whereSeparator: { !($0.isLetter || $0.isNumber) }).map(String.init).filter { $0.count >= minimum }
    }

    /// ¿Aparece `token` en `text`, tolerando un error de tipeo («waller» ≈ «wallet»)?
    static func fuzzyContains(_ text: String, _ token: String, ratio: Double = 0.8) -> Bool {
        if text.contains(token) { return true }
        let source = Array(text), target = Array(token)
        guard target.count >= 4, source.count >= target.count else { return false }
        for start in 0...(source.count - target.count) where similarity(Array(source[start..<start + target.count]), target) >= ratio { return true }
        return false
    }

    static func similarity(_ left: [Character], _ right: [Character]) -> Double {
        guard !left.isEmpty || !right.isEmpty else { return 1 }
        var previous = Array(0...right.count)
        for (i, a) in left.enumerated() {
            var current = [i + 1] + Array(repeating: 0, count: right.count)
            for (j, b) in right.enumerated() { current[j + 1] = min(previous[j + 1] + 1, current[j] + 1, previous[j] + (a == b ? 0 : 1)) }
            previous = current
        }
        return 1 - Double(previous[right.count]) / Double(max(left.count, right.count))
    }
}
