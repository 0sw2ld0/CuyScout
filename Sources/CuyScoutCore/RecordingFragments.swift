import Foundation

/// Crea fragmentos a partir de una grabación ya guardada (`output/<escenario>.cuyscout.json`), sin sesión ni dispositivo.
/// Los textos escritos no están en el artefacto (van redactados): sus valores salen de `fixtures/replay-values/<escenario>.json`
/// y, como en cualquier fragmento, solo se guardan si coinciden con un campo de `fixtures/credentials.test.json`.
public enum RecordingFragments {
    public struct Source: Sendable {
        public let name: String
        public let platform: Device.Platform
        public let bundleIdentifier: String?
        public let steps: [RecordedStep]
        /// `"<índice del paso>.text"` → valor escrito. Vacío si el escenario no tiene valores locales.
        public let replayValues: [String: String]
    }

    public enum Eligibility: Equatable, Sendable {
        case eligible
        case failed          // el paso falló: no se reproduce
        case reading         // solo lee la pantalla
        case assertion       // las aserciones son del escenario, no del tramo
        case nested          // otro fragmento
    }

    public static func load(name: String, artifact: URL, replayValues: URL?) throws -> Source {
        guard let data = try? Data(contentsOf: artifact), let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let recording = object["recording"] as? [String: Any], let rawSteps = recording["steps"] as? [[String: Any]] else {
            throw ScoutError.invalidRequest("El artefacto «\(artifact.lastPathComponent)» no tiene una grabación legible")
        }
        let steps = try rawSteps.map { try JSONDecoder().decode(RecordedStep.self, from: JSONSerialization.data(withJSONObject: $0)) }.sorted { $0.index < $1.index }
        let session = object["session"] as? [String: Any]
        let platformName = ((session?["device"] as? [String: Any])?["platform"] as? String) ?? ""
        guard let platform = Device.Platform(rawValue: platformName) else { throw ScoutError.invalidRequest("El artefacto no indica la plataforma de la grabación") }
        let values = replayValues.flatMap { try? Data(contentsOf: $0) }.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }?.compactMapValues { $0 as? String } ?? [:]
        return Source(name: name, platform: platform, bundleIdentifier: session?["bundleIdentifier"] as? String, steps: steps, replayValues: values)
    }

    public static func eligibility(of step: RecordedStep) -> Eligibility {
        guard step.success else { return .failed }
        if TestPlanValidator.isObservational(step.action) { return .reading }
        switch step.action {
        case .assertText, .assertVisible: return .assertion
        case .runFragment: return .nested
        default: return .eligible
        }
    }

    /// Qué hace el paso, en una línea y sin el texto escrito.
    public static func summary(of action: ScoutAction) -> String {
        func target(_ selector: ScoutSelector) -> String { "«\(selector.value)»" }
        switch action {
        case .tapElement(let selector): return "Tocar \(target(selector))"
        case .typeElement(let selector, _): return "Escribir en \(target(selector))"
        case .type: return "Escribir en el campo enfocado"
        case .tap(let x, let y): return "Tocar por coordenadas (\(Int(x)), \(Int(y)))"
        case .waitFor(let selector, _): return "Esperar \(target(selector))"
        case .swipe: return "Deslizar"
        case .scroll: return "Desplazar"
        case .scrollUntilVisible(let selector, _, _): return "Desplazar hasta \(target(selector))"
        case .longPress(let selector, _): return "Pulsación larga en \(target(selector))"
        case .doubleTap(let selector): return "Doble toque en \(target(selector))"
        case .clearElement(let selector): return "Vaciar \(target(selector))"
        case .pressKey(let key): return "Tecla \(key)"
        case .hideKeyboard: return "Cerrar el teclado"
        case .eraseText(let count): return "Borrar \(count) caracteres"
        case .launch(let id): return "Abrir \(id)"
        case .terminate(let id): return "Cerrar \(id)"
        case .accessibilityTree, .accessibilityTreeWithOptions, .accessibilityDiff: return "Leer la pantalla"
        case .findElement(let selector), .findElements(let selector): return "Buscar \(target(selector))"
        case .assertVisible(let selector): return "Verificar que se ve \(target(selector))"
        case .assertText(let selector, _): return "Verificar el texto de \(target(selector))"
        case .runFragment(let name, _): return "Fragmento «\(name)»"
        default: return String(describing: action).prefix(48).description
        }
    }

    /// El error guardado de un paso, dicho en una frase corta y sin jerga («runner_busy: …» → «el runner no respondió a tiempo»).
    public static func humanize(error: String?) -> String? {
        guard let raw = error?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let lower = raw.lowercased()
        if lower.hasPrefix("runner_busy") { return "el runner no respondió a tiempo" }
        if lower.contains("xctest_runner_starting") || lower.contains("runner_starting") { return "el runner aún estaba arrancando" }
        if lower.contains("not_visible") || lower.contains("oculto") { return "el elemento estaba oculto o tapado" }
        if lower.contains("no se pudo tocar") { return "no se pudo tocar el elemento" }
        if lower.contains("no se encontró el elemento") || lower.contains("no such element") || lower.contains("no existe") { return "el elemento no existía en esa pantalla" }
        let sentence = raw.split(whereSeparator: { ".;\n".contains($0) }).first.map(String.init) ?? raw
        let short = sentence.count > 110 ? String(sentence.prefix(107)) + "…" : sentence
        return short.prefix(1).lowercased() + short.dropFirst()
    }

    /// Por qué un paso no entra en el fragmento, con el motivo real; nil si sí puede entrar.
    public static func explanation(for step: RecordedStep) -> String? {
        switch eligibility(of: step) {
        case .eligible: return nil
        case .failed:
            let reason = humanize(error: step.error).map { " (\($0))" } ?? ""
            return TestPlanValidator.isObservational(step.action)
                ? "Falló al leer la pantalla\(reason). No cambió nada, así que no entra."
                : "Falló cuando se ejecutó\(reason). No hizo nada, así que no entra: repetirlo volvería a fallar."
        case .reading: return "Solo lee la pantalla y no cambia nada: no entra."
        case .assertion: return "Verifica el resultado del escenario, no forma parte del tramo: no entra."
        case .nested: return "Ya es otro fragmento: no se anidan."
        }
    }

    /// Valor que se escribió en un paso (de los valores locales), o nil si el paso no escribe o no hay valor.
    public static func typedValue(of step: RecordedStep, in source: Source) -> String? {
        switch step.action {
        case .typeElement(_, let text), .type(let text):
            return text == "<redacted>" || text == "<text>" ? source.replayValues["\(step.index).text"] : text
        default: return nil
        }
    }

    /// «campo (alias)» de las credenciales con el que coincide lo escrito en el paso; nil si no coincide con ninguno.
    public static func credentialMatch(for step: RecordedStep, in source: Source, credentials: [String: [String: String]]) -> String? {
        guard let value = typedValue(of: step, in: source), !value.isEmpty else { return nil }
        for alias in credentials.keys.sorted() {
            if let field = credentials[alias]?.sorted(by: { $0.key < $1.key }).first(where: { $0.value == value })?.key { return "\(field) (\(alias))" }
        }
        return nil
    }

    /// Valida el plan de la grabación con el validador actual (no el del momento de exportar). Los textos escritos se
    /// completan con los valores locales; si faltan, el aviso de «placeholder» sigue siendo correcto.
    public static func validation(of source: Source) -> TestPlanValidation {
        let steps = source.steps.map { step -> RecordedStep in
            guard let value = typedValue(of: step, in: source) else { return step }
            let action: ScoutAction
            switch step.action {
            case .typeElement(let selector, _): action = .typeElement(selector, text: value)
            case .type: action = .type(value)
            default: return step
            }
            return RecordedStep(index: step.index, action: action, startedAt: step.startedAt, durationMilliseconds: step.durationMilliseconds, success: step.success, error: step.error)
        }
        return TestPlanValidator.validate(TestPlanValidator.plan(sessionID: source.name, steps: steps))
    }

    /// Guarda como fragmento los pasos elegidos (por su índice en la grabación). Solo entran los elegibles; el resto se descarta.
    public static func save(source: Source, selecting indices: Set<Int>, name: String, exitCheck: SessionFragment.Check, in project: URL,
                            alias: String? = nil, allowLiteral: Bool = false, skipIfAlreadyDone: Bool = true, overwrite: Bool = false) throws -> FragmentSaveResult {
        try FragmentStore.validate(name: name)
        let chosen = source.steps.filter { indices.contains($0.index) }
        let kept = chosen.filter { eligibility(of: $0) == .eligible }
        guard !kept.isEmpty else { throw ScoutError.invalidRequest("No hay pasos que guardar: elige al menos uno que actúe (no lecturas, aserciones ni pasos fallidos)") }
        // Con el valor real en cada texto, para que `prepare` lo reconozca en las credenciales y lo sustituya por una variable.
        var actions: [ScoutAction] = []
        for step in kept {
            switch step.action {
            case .typeElement(let selector, _):
                guard let value = typedValue(of: step, in: source) else { throw missingValue(step, source) }
                actions.append(.typeElement(selector, text: value))
            case .type:
                guard let value = typedValue(of: step, in: source) else { throw missingValue(step, source) }
                actions.append(.type(value))
            default: actions.append(step.action)
            }
        }
        let needsCredentials = actions.contains { if case .typeElement = $0 { return true }; if case .type = $0 { return true }; return false }
        let credentials = needsCredentials ? try FragmentStore.credentials(in: project) : [:]
        let prepared = try FragmentStore.prepare(steps: actions, credentials: credentials, alias: alias, allowLiteral: allowLiteral)
        let fragment = SessionFragment(name: name, platform: source.platform, bundleIdentifier: source.bundleIdentifier, defaultAlias: prepared.alias,
                                       variables: prepared.variables, exitCheck: exitCheck, skipIfAlreadyDone: skipIfAlreadyDone, steps: prepared.steps)
        try FragmentStore.save(fragment, in: project, overwrite: overwrite)
        var warnings: [String] = []
        if kept.contains(where: { if case .tap = $0.action { return true }; return false }) {
            warnings.append("El fragmento usa toques por coordenadas: dependen del tamaño de pantalla; prefiere selectores por texto.")
        }
        if kept.count == 1 { warnings.append("El fragmento tiene un solo paso.") }
        return FragmentSaveResult(name: name, path: FragmentStore.relativePath(name: name, platform: source.platform), steps: kept.count, dropped: chosen.count - kept.count,
                                  credentialFields: Array(Set(prepared.variables.values)).sorted(), warnings: warnings)
    }

    private static func missingValue(_ step: RecordedStep, _ source: Source) -> ScoutError {
        ScoutError.invalidRequest("Falta el valor escrito en el paso \(step.index + 1): no está en fixtures/replay-values/\(source.name).json (se crea al exportar la grabación). Quita ese paso o vuelve a exportar la prueba.")
    }
}
