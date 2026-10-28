import AppKit
import CuyScoutCore
import SwiftUI

/// Fragmentos del proyecto (p. ej. el login): tramos ya automatizados que el agente llama dentro de su sesión.
/// Se leen de `fragments/` sin necesitar el gateway; se crean desde «Grabar prueba» → «Guardar como fragmento».
struct FragmentsView: View {
    @Environment(\.dismiss) private var dismiss
    let project: ScoutProject
    var onChange: () -> Void = {}
    @State private var fragments: [SessionFragment] = []
    @State private var pendingDelete: SessionFragment?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Fragmentos de «\(project.name)»").font(.title2.bold())
            Text("Un fragmento es un tramo que se repite en muchas pruebas, como iniciar sesión. El agente lo ejecuta con una sola llamada y las claves las resuelve CuyScout por alias: el agente no las ve.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            if fragments.isEmpty {
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Todavía no hay fragmentos").fontWeight(.medium)
                        Text("Abre «Grabar prueba», haz el login una vez y pulsa «Guardar como fragmento». Pon el texto que debe verse al terminar (por ejemplo «Transferir»).")
                            .font(.callout).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
            } else {
                List {
                    ForEach(fragments, id: \.name) { fragment in row(fragment) }
                }
                .frame(minHeight: 180)
            }

            if let error { Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                Button("Abrir carpeta fragments", systemImage: "folder") {
                    let folder = project.url.appendingPathComponent("fragments", isDirectory: true)
                    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(folder)
                }
                Spacer()
                Button("Cerrar") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 560, minHeight: 360)
        .onAppear(perform: load)
        .confirmationDialog("¿Borrar el fragmento «\(pendingDelete?.name ?? "")»?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
            Button("Borrar", role: .destructive) { delete() }
            Button("Cancelar", role: .cancel) { pendingDelete = nil }
        } message: { Text("Los escenarios que lo usan tendrán que hacer ese tramo a mano hasta que lo vuelvas a guardar.") }
    }

    private func row(_ fragment: SessionFragment) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(fragment.name).fontWeight(.semibold)
                    Text(fragment.platform == .android ? "Android" : "iOS").font(.caption2.bold())
                        .padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(Color.accentColor.opacity(0.15)))
                }
                Text("\(fragment.steps.count) pasos · " + (fragment.exitCheck.map { "termina cuando se ve «\($0.selector.value)»" } ?? fragment.exitDescription))
                    .font(.caption).foregroundStyle(.secondary)
                Text(detail(fragment)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Borrar", systemImage: "trash", role: .destructive) { pendingDelete = fragment }
                .buttonStyle(.borderless).help("Borra el archivo del fragmento; los escenarios que lo usan harán el login a mano hasta que lo vuelvas a grabar")
        }
        .padding(.vertical, 4)
    }

    private func detail(_ fragment: SessionFragment) -> String {
        var parts: [String] = []
        if let alias = fragment.defaultAlias { parts.append("alias «\(alias)»") }
        if !fragment.variables.isEmpty { parts.append("usa \(Set(fragment.variables.values).sorted().joined(separator: ", "))") }
        parts.append(fragment.skipIfAlreadyDone ? "se omite si ya se cumple" : "siempre se ejecuta")
        return parts.joined(separator: " · ")
    }

    private func load() { fragments = FragmentStore.list(in: project.url) }

    private func delete() {
        guard let fragment = pendingDelete else { return }
        pendingDelete = nil
        do { try FragmentStore.delete(name: fragment.name, platform: fragment.platform, in: project.url); error = nil; load(); onChange() }
        catch { self.error = error.localizedDescription }
    }
}
