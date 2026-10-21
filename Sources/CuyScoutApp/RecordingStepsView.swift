import AppKit
import CuyScoutCore
import SwiftUI

/// Los pasos de una grabación guardada (`output/<escenario>.cuyscout.json`) y, de ellos, los que forman un fragmento
/// (p. ej. el login). No necesita sesión ni dispositivo: lee el artefacto y los valores locales del escenario.
struct RecordingStepsView: View {
    @Environment(\.dismiss) private var dismiss
    let project: ScoutProject
    let scenario: ProjectScenario
    var onSaved: () -> Void = {}

    @State private var source: RecordingFragments.Source?
    @State private var credentials: [String: [String: String]] = [:]
    @State private var selected: Set<Int> = []
    @State private var name = "login"
    @State private var exitText = ""
    @State private var alias: String?
    @State private var allowLiteral = false
    @State private var skipIfDone = true
    @State private var overwrite = false
    @State private var hideReadings = true
    @State private var result: FragmentSaveResult?
    @State private var error: String?

    /// El nombre del archivo solo admite minúsculas, números y guiones: «Login» o «Mi login» se guardan como
    /// «login» y «mi-login» en vez de dejar el botón desactivado sin decir por qué.
    private var fragmentName: String {
        name.trimmingCharacters(in: .whitespaces).lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "es"))
            .replacingOccurrences(of: "[ _.]+", with: "-", options: .regularExpression)
    }
    private var validName: Bool { (try? FragmentStore.validate(name: fragmentName)) != nil }
    private var canSave: Bool { missing == nil }
    /// Qué falta para poder guardar, dicho junto al botón.
    private var missing: String? {
        if selected.isEmpty { return "Marca al menos un paso." }
        if !validName { return "El nombre solo admite letras sin tilde, números y guiones (p. ej. login)." }
        if exitText.trimmingCharacters(in: .whitespaces).isEmpty { return "Escribe el texto que debe verse al terminar el tramo: así el replay sabe que terminó." }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Crear un fragmento desde «\(scenario.name)»").font(.title2.bold())
            Text("Marca los pasos que forman el tramo (por ejemplo el login). Con «Hasta aquí» se marcan todos los que actúan desde el principio hasta ese paso.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("No se pueden marcar: 👁 las lecturas de pantalla, ✗ los pasos que dieron error cuando el agente los ejecutó (el motivo aparece debajo) y las verificaciones del escenario.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            if let source {
                HStack {
                    Text("\(source.steps.count) pasos · \(source.platform == .android ? "Android" : "iOS")").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Toggle("Ocultar lecturas", isOn: $hideReadings).toggleStyle(.checkbox).font(.caption)
                    Button("Marcar los que actúan") { selected = Set(source.steps.filter { RecordingFragments.eligibility(of: $0) == .eligible }.map(\.index)) }.buttonStyle(.borderless)
                    Button("Ninguno") { selected = [] }.buttonStyle(.borderless)
                }
                List {
                    ForEach(source.steps.filter { !(hideReadings && RecordingFragments.eligibility(of: $0) == .reading) }, id: \.index) { step in row(step, source) }
                }
                .frame(minHeight: 240)
                form
            } else {
                Text(error ?? "Cargando la grabación…").foregroundStyle(error == nil ? Color.secondary : Color.red)
                Spacer()
            }

            if let result {
                Text(resultMessage(result)).font(.callout).foregroundStyle(.green).textSelection(.enabled)
            }
            if source != nil, let error { Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                if let missing { Text(missing).font(.callout).foregroundStyle(.secondary) }
                Spacer()
                Button("Cerrar") { dismiss() }
                Button("Guardar fragmento") { save() }.keyboardShortcut(.defaultAction).disabled(!canSave)
            }
        }
        .padding(24)
        .frame(minWidth: 760, minHeight: 640)
        .onAppear(perform: load)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Nombre (p. ej. login)", text: $name).textFieldStyle(.roundedBorder).frame(maxWidth: 220)
                TextField("Texto que debe verse al terminar (p. ej. Transferir)", text: $exitText).textFieldStyle(.roundedBorder)
            }
            HStack {
                Picker("Alias de credenciales", selection: $alias) {
                    Text("Automático (el que coincide)").tag(String?.none)
                    ForEach(credentials.keys.sorted(), id: \.self) { Text($0).tag(String?.some($0)) }
                }.frame(maxWidth: 360)
                Spacer()
            }
            Toggle("Omitir si ya se ve ese texto (por ejemplo, si ya hay sesión iniciada)", isOn: $skipIfDone)
            Toggle("Permitir textos escritos que no están en las credenciales (solo si no son datos sensibles)", isOn: $allowLiteral)
            Toggle("Reemplazar el fragmento si ya existe", isOn: $overwrite)
        }
    }

    private func row(_ step: RecordedStep, _ source: RecordingFragments.Source) -> some View {
        let kind = RecordingFragments.eligibility(of: step)
        return HStack(alignment: .top, spacing: 10) {
            if kind == .eligible {
                Toggle("", isOn: Binding(get: { selected.contains(step.index) }, set: { on in if on { selected.insert(step.index) } else { selected.remove(step.index) } }))
                    .labelsHidden().toggleStyle(.checkbox)
            } else {
                Image(systemName: icon(kind)).foregroundStyle(.secondary).frame(width: 18)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(step.index + 1). \(RecordingFragments.summary(of: step.action))").foregroundStyle(kind == .eligible ? Color.primary : Color.secondary)
                if let note = note(step, kind, source) { Text(note.text).font(.caption).foregroundStyle(note.warning ? Color.orange : Color.secondary) }
            }
            Spacer()
            if kind == .eligible {
                Button("Hasta aquí") {
                    selected = Set(source.steps.filter { $0.index <= step.index && RecordingFragments.eligibility(of: $0) == .eligible }.map(\.index))
                }.buttonStyle(.borderless).font(.caption)
            }
        }
        .padding(.vertical, 2)
    }

    private func resultMessage(_ result: FragmentSaveResult) -> String {
        var text = "Fragmento «\(result.name)» guardado en \(result.path): \(result.steps) pasos"
        if result.dropped > 0 { text += " (\(result.dropped) descartados)" }
        text += result.credentialFields.isEmpty ? "." : ", usa \(result.credentialFields.joined(separator: ", "))."
        if !result.warnings.isEmpty { text += " " + result.warnings.joined(separator: " ") }
        return text
    }

    private func icon(_ kind: RecordingFragments.Eligibility) -> String {
        switch kind {
        case .failed: "xmark.circle"
        case .reading: "eye"
        case .assertion: "checkmark.seal"
        case .nested: "bolt.horizontal.circle"
        case .eligible: "circle"
        }
    }

    private func note(_ step: RecordedStep, _ kind: RecordingFragments.Eligibility, _ source: RecordingFragments.Source) -> (text: String, warning: Bool)? {
        switch kind {
        case .failed, .reading, .assertion, .nested:
            return RecordingFragments.explanation(for: step).map { ($0, false) }
        case .eligible:
            switch step.action {
            case .typeElement, .type:
                if RecordingFragments.typedValue(of: step, in: source) == nil { return ("⚠ Falta el valor escrito en fixtures/replay-values: no se podrá guardar", true) }
                if let match = RecordingFragments.credentialMatch(for: step, in: source, credentials: credentials) { return ("Escribe el campo \(match) de las credenciales", false) }
                return ("⚠ Lo escrito no está en las credenciales de prueba: no se guardará (salvo que lo permitas y no sea sensible)", true)
            case .tap: return ("Toque por coordenadas: depende del tamaño de pantalla", true)
            default: return nil
            }
        }
    }

    private func load() {
        guard source == nil else { return }
        guard let artifact = scenario.artifactURL else { error = "Este escenario aún no tiene una grabación."; return }
        do {
            source = try RecordingFragments.load(name: scenario.name, artifact: artifact, replayValues: scenario.valuesURL)
            credentials = (try? FragmentStore.credentials(in: project.url)) ?? [:]
        } catch { self.error = error.localizedDescription }
    }

    private func save() {
        guard let source else { return }
        do {
            result = try RecordingFragments.save(source: source, selecting: selected, name: fragmentName,
                                                 exitCheck: SessionFragment.Check(selector: ScoutSelector(strategy: .label, value: exitText.trimmingCharacters(in: .whitespaces))),
                                                 in: project.url, alias: alias, allowLiteral: allowLiteral, skipIfAlreadyDone: skipIfDone, overwrite: overwrite)
            error = nil
            onSaved()
        } catch { result = nil; self.error = error.localizedDescription }
    }
}
