import CuyScoutCore
import SwiftUI

/// Elige una app ya instalada en un iPhone conectado para probarla sin su instalador.
struct InstalledAppPicker: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: ScoutAppModel
    let project: ScoutProject
    @State private var selected: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("App ya instalada en el iPhone").font(.title2.bold())
            Text("CuyScout la prueba tal como está, sin reinstalarla ni borrar sus datos. Debe ser una compilación de desarrollo.")
                .foregroundStyle(.secondary)
            InstalledAppList(model: model, selected: $selected)
            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }
                Button("Usar esta app") {
                    if let selected { model.usePhysicalInstalledApp(projectID: project.id, bundleIdentifier: selected) }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selected == nil)
            }
        }
        .padding(24)
        .frame(width: 560)
        .onAppear { selected = project.physicalBundleID.isEmpty ? nil : project.physicalBundleID }
    }
}

/// iPhones conectados y sus apps de usuario; `selected` es el bundle ID elegido.
struct InstalledAppList: View {
    @ObservedObject var model: ScoutAppModel
    @Binding var selected: String?
    var minHeight: CGFloat = 260
    @State private var deviceID = ""
    @State private var apps: [InstalledApp] = []
    @State private var loading = false
    @State private var error: String?

    private var iPhones: [Device] { model.devices.filter { $0.kind == .physical && $0.isAvailable } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if iPhones.isEmpty {
                Text("No hay un iPhone conectado y disponible. Conéctalo, desbloquéalo y pulsa actualizar.")
                    .foregroundStyle(.orange)
            } else {
                Picker("iPhone", selection: $deviceID) {
                    ForEach(iPhones, id: \.id) { Text($0.name).tag($0.id) }
                }
                List(apps, id: \.bundleIdentifier, selection: $selected) { app in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.name).fontWeight(.medium)
                            Text(app.bundleIdentifier).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                        Spacer()
                        if let version = app.version { Text(version).font(.caption).foregroundStyle(.secondary) }
                        if !app.developerBuild {
                            Text("No es de desarrollo").font(.caption2).foregroundStyle(.orange)
                                .help("XCUITest solo puede controlar compilaciones de desarrollo")
                        }
                    }
                    .tag(app.bundleIdentifier)
                }
                .frame(minHeight: minHeight)
                .overlay { if loading { ProgressView() } }
            }
            if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            Button("Actualizar", systemImage: "arrow.clockwise") {
                Task {
                    await model.refresh()
                    if !iPhones.contains(where: { $0.id == deviceID }) { deviceID = iPhones.first?.id ?? "" }
                    await load()
                }
            }
        }
        .task {
            if deviceID.isEmpty { deviceID = iPhones.first?.id ?? "" }
            await load()
        }
        .onChange(of: deviceID) { _ in Task { await load() } }
    }

    private func load() async {
        guard !deviceID.isEmpty else { return }
        loading = true
        defer { loading = false }
        do {
            apps = try await model.installedApps(deviceID: deviceID)
            error = nil
        } catch {
            apps = []
            self.error = "No se pudieron leer las apps del iPhone: \(error.localizedDescription)"
        }
    }
}
