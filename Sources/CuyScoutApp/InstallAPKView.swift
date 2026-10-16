import AppKit
import CuyScoutCore
import SwiftUI
import UniformTypeIdentifiers

/// Utilidad independiente de los proyectos: instala una APK en emuladores y teléfonos Android.
/// Si la app ya estaba instalada se actualiza y conserva sus datos (`adb install -r`).
struct InstallAPKView: View {
    @ObservedObject var model: ScoutAppModel
    @State private var apkPath = ""
    @State private var selected: Set<String> = []
    @State private var installing = false

    private var androidDevices: [Device] { model.devices.filter { $0.platform == .android } }
    private var usable: [Device] { androidDevices.filter(AndroidController.isUsable) }
    private var targets: [Device] { usable.filter { selected.contains($0.id) } }

    private var apkProblem: String? {
        let path = (apkPath as NSString).expandingTildeInPath
        if path.isEmpty { return nil }
        if !path.lowercased().hasSuffix(".apk") { return "El archivo debe terminar en .apk" }
        if !FileManager.default.fileExists(atPath: path) { return "No existe ese archivo" }
        return nil
    }
    private var apkSize: String? {
        let path = (apkPath as NSString).expandingTildeInPath
        guard apkProblem == nil, !path.isEmpty, let bytes = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int64 else { return nil }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
    private var canInstall: Bool { !apkPath.isEmpty && apkProblem == nil && !targets.isEmpty && !installing }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Instalar APK").font(.largeTitle.bold())
                Text("Instala una APK en emuladores y teléfonos Android, sin abrir un proyecto. Si la app ya estaba instalada se actualiza y conserva sus datos.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                apkCard
                devicesCard
                HStack {
                    Button(action: install) {
                        Label(targets.count > 1 ? "Instalar en \(targets.count) dispositivos" : "Instalar", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent).disabled(!canInstall)
                    if installing { ProgressView().controlSize(.small) }
                    Spacer()
                }
                Text("Requiere Android SDK (adb) en esta Mac. Si el gateway está conectado, instala el gateway y la ruta de la APK es la de su Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(28)
            .frame(maxWidth: 820, alignment: .leading)
        }
        .task { await model.refreshAndroidDestinations(); preselectIfSingle() }
        .onChange(of: model.devices) { _ in selected = selected.filter { id in usable.contains { $0.id == id } }; preselectIfSingle() }
    }

    private var apkCard: some View {
        GroupBox("APK") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField("Ruta de la APK, o arrástrala aquí", text: $apkPath).textFieldStyle(.roundedBorder)
                    Button("Elegir APK…") {
                        let panel = NSOpenPanel()
                        panel.title = "Selecciona la APK Android"
                        panel.canChooseDirectories = false
                        panel.allowsMultipleSelection = false
                        panel.allowedContentTypes = [UTType(filenameExtension: "apk") ?? .data]
                        if panel.runModal() == .OK, let url = panel.url { apkPath = url.path }
                    }
                }
                if let problem = apkProblem {
                    Label(problem, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                } else if let size = apkSize {
                    Text(((apkPath as NSString).expandingTildeInPath as NSString).lastPathComponent + " · " + size).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(8)
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let apk = urls.first(where: { $0.pathExtension.lowercased() == "apk" }) else { return false }
            apkPath = apk.path; return true
        }
    }

    private var devicesCard: some View {
        GroupBox("Dispositivos") {
            VStack(alignment: .leading, spacing: 0) {
                if androidDevices.isEmpty {
                    Text("No hay Android conectado ni AVD. Conecta un teléfono con la depuración USB autorizada o crea un AVD en Android Studio, y pulsa Actualizar.")
                        .foregroundStyle(.secondary).padding(8).fixedSize(horizontal: false, vertical: true)
                }
                ForEach(androidDevices, id: \.id) { device in
                    deviceRow(device)
                    if device.id != androidDevices.last?.id { Divider() }
                }
                HStack {
                    Button("Actualizar", systemImage: "arrow.clockwise") { Task { await model.refreshAndroidDestinations() } }
                        .disabled(installing)
                    Spacer()
                }.padding(8)
            }
        }
    }

    private func deviceRow(_ device: Device) -> some View {
        let isUsable = AndroidController.isUsable(device)
        let stopped = device.state == "Shutdown" && device.kind == .simulator
        return HStack(alignment: .top, spacing: 10) {
            Toggle("", isOn: Binding(get: { selected.contains(device.id) }, set: { on in
                if on { selected.insert(device.id) } else { selected.remove(device.id) }
            })).labelsHidden().disabled(!isUsable || installing)
            Image(systemName: device.kind == .physical ? "iphone" : "display").frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name).fontWeight(.medium)
                Text("\(device.kind == .physical ? "Teléfono" : "Emulador") · \(device.id) · \(device.runtime)").font(.caption).foregroundStyle(.secondary)
                if !isUsable && !stopped {
                    Text(device.state == "unauthorized" ? "Autoriza la depuración USB en el teléfono" : "No disponible (\(device.state))").font(.caption).foregroundStyle(.orange)
                }
                resultLine(device)
            }
            Spacer()
            if stopped {
                if model.bootingDeviceID == device.id {
                    HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Encendiendo…").font(.caption) }
                } else {
                    Button("Encender", systemImage: "power") { Task { await model.bootAndroidAVD(device) } }
                        .disabled(model.bootingDeviceID != nil || installing)
                }
            }
        }
        .padding(8)
    }

    @ViewBuilder private func resultLine(_ device: Device) -> some View {
        switch model.apkInstalls[device.id] {
        case .installing?: HStack(spacing: 6) { ProgressView().controlSize(.mini); Text("Instalando…").font(.caption) }
        case .installed(let seconds)?: Label(String(format: "Instalada en %.1f s", seconds), systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
        case .failed(let message)?: Label(message, systemImage: "xmark.octagon.fill").font(.caption).foregroundStyle(.red).textSelection(.enabled)
        case nil: EmptyView()
        }
    }

    private func preselectIfSingle() { if selected.isEmpty, usable.count == 1, let only = usable.first { selected = [only.id] } }

    private func install() {
        let path = (apkPath as NSString).expandingTildeInPath, chosen = targets
        for device in chosen { model.apkInstalls[device.id] = nil }
        installing = true
        Task { await model.installAPK(at: path, on: chosen); installing = false }
    }
}
