import AppKit
import CuyScoutCore
import SwiftUI

/// Crea o edita un escenario `features/<nombre>.feature`. El inicio de sesión se elige entre los fragmentos del proyecto
/// y queda como una etiqueta `@fragment:<nombre>` sobre `Feature:`, visible también en cualquier otro editor.
struct FeatureEditorView: View {
    enum Mode: Equatable { case new, edit(name: String) }

    @Environment(\.dismiss) private var dismiss
    let project: ScoutProject
    let mode: Mode
    var onSaved: () -> Void = {}

    @State private var name = ""
    @State private var featureTitle = ""
    @State private var scenarioTitle = ""
    @State private var fragment: String?
    @State private var text = ""
    @State private var error: String?
    @State private var loaded = false

    private var fragmentNames: [String] { Array(Set(FragmentStore.list(in: project.url).map(\.name))).sorted() }
    private var isNew: Bool { mode == .new }
    private var nameProblem: String? {
        guard isNew, !name.isEmpty else { return nil }
        do { try FeatureFile.validate(name: name) } catch { return error.localizedDescription }
        return FileManager.default.fileExists(atPath: FeatureFile.url(name: name, in: project.url).path) ? "Ya existe un escenario con ese nombre." : nil
    }
    private var problems: [String] { FeatureFile.problems(in: text) }
    private var canSave: Bool { !text.isEmpty && (isNew ? (!name.isEmpty && nameProblem == nil) : true) && !problems.contains { $0.hasPrefix("Falta") } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isNew ? "Nuevo escenario" : "Editar «\(editName)»").font(.title2.bold())

            if isNew {
                TextField("Nombre del archivo (p. ej. transferencia-propia)", text: $name).textFieldStyle(.roundedBorder)
                if let nameProblem { Text(nameProblem).font(.caption).foregroundStyle(.red) }
                HStack {
                    TextField("Título del feature", text: $featureTitle).textFieldStyle(.roundedBorder)
                    TextField("Título del escenario", text: $scenarioTitle).textFieldStyle(.roundedBorder)
                }
            }

            HStack {
                Picker("Inicio de sesión", selection: $fragment) {
                    Text("Ninguno (el agente lo resuelve)").tag(String?.none)
                    ForEach(fragmentNames, id: \.self) { Text("Fragmento «\($0)»").tag(String?.some($0)) }
                }
                .frame(maxWidth: 380)
                if isNew { Button("Usar plantilla") { applyTemplate() }.help("Reemplaza el texto por una plantilla con ese inicio de sesión") }
                Spacer()
                if !isNew { Button("Abrir en otro editor", systemImage: "arrow.up.forward.app") { NSWorkspace.shared.open(FeatureFile.url(name: editName, in: project.url)) } }
            }
            if fragmentNames.isEmpty {
                Text("Aún no hay fragmentos: guarda uno desde «Grabar prueba» para poder elegirlo aquí.").font(.caption).foregroundStyle(.secondary)
            } else if fragment != nil {
                Text("El agente ejecutará ese fragmento para el «Background» en lugar de repetir el login.").font(.caption).foregroundStyle(.secondary)
            }

            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 260)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))

            ForEach(problems, id: \.self) { Text("• \($0)").font(.caption).foregroundStyle(.orange) }
            if let error { Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }
                Button("Guardar") { save() }.keyboardShortcut(.defaultAction).disabled(!canSave)
            }
        }
        .padding(24)
        .frame(minWidth: 680, minHeight: 560)
        .onAppear(perform: load)
        .onChange(of: fragment) { new in if loaded { text = FeatureFile.settingFragment(new, in: text) } }
    }

    private var editName: String { if case .edit(let name) = mode { name } else { "" } }

    private func load() {
        guard !loaded else { return }
        if case .edit(let existing) = mode {
            text = (try? String(contentsOf: FeatureFile.url(name: existing, in: project.url), encoding: .utf8)) ?? ""
            fragment = FeatureFile.fragment(in: text)
        } else {
            applyTemplate()
        }
        loaded = true
    }

    private func applyTemplate() {
        text = FeatureFile.template(featureTitle: featureTitle.isEmpty ? "Nombre del feature" : featureTitle,
                                    scenarioTitle: scenarioTitle.isEmpty ? "Nombre del escenario" : scenarioTitle, fragment: fragment)
    }

    private func save() {
        do {
            try FeatureFile.save(text.hasSuffix("\n") ? text : text + "\n", name: isNew ? name : editName, in: project.url, overwrite: !isNew)
            error = nil
            onSaved()
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
