import SwiftUI
import CuyScoutCore

/// Botón de la barra con el interruptor de Laya: desactivado por defecto; activo, los agentes
/// pueden pedir a CuyScout que elija el control de cada paso (`POST /session/:id/decide`).
struct LayaToolbarButton: View {
    @ObservedObject var model: ScoutAppModel
    @State private var showing = false
    @State private var editedURL = ""

    private var statusColor: Color {
        guard model.layaEnabled else { return .secondary }
        return model.layaStatus?.available == true ? .green : .orange
    }

    var body: some View {
        Button { showing.toggle() } label: {
            Label("Laya", systemImage: model.layaEnabled ? "bolt.fill" : "bolt.slash")
                .foregroundStyle(statusColor)
        }
        .help(model.layaEnabled ? "Laya activo: decisiones rápidas sin tokens" : "Laya desactivado")
        .popover(isPresented: $showing) { popover }
    }

    private var popover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Decisión rápida con Laya").font(.headline)
            Text("Activo, los agentes pueden pedir a CuyScout que elija el control de cada paso sin gastar tokens del LLM. Si Laya duda, el agente decide.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle("Usar Laya", isOn: Binding(
                get: { model.layaEnabled },
                set: { value in Task { await model.applyLaya(enabled: value, url: editedURL) } }
            ))
            .toggleStyle(.switch)
            TextField("URL del servicio", text: $editedURL)
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await model.applyLaya(enabled: model.layaEnabled, url: editedURL) } }
            Label(statusText, systemImage: "circle.fill")
                .font(.caption)
                .foregroundStyle(statusColor)
            if model.layaEnabled && model.layaStatus?.available != true {
                Text("Arráncalo con ~/Library/Application Support/Laya/laya-service.sh start")
                    .font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
        .padding(18)
        .frame(width: 340)
        .onAppear { editedURL = model.layaURL; Task { await model.refresh() } }
    }

    private var statusText: String {
        guard model.layaEnabled else { return "Desactivado" }
        guard model.connected else { return "Se aplicará al iniciar el gateway" }
        guard let status = model.layaStatus else { return "Estado desconocido" }
        if status.available == true {
            let loaded = status.loaded ?? []
            return "Disponible" + (loaded.isEmpty ? "" : " · \(loaded.joined(separator: ", "))")
        }
        return "No responde en \(status.url)"
    }
}
