import AppKit
import CuyScoutCore
import SwiftUI
import UniformTypeIdentifiers

extension ScoutProject {
    var canRecord: Bool {
        platform == .android ? android?.applicationId.isEmpty == false
            : !appPath.isEmpty || !physicalAppPath.isEmpty || !physicalBundleID.isEmpty
    }

    var initialDeviceSelection: String {
        if platform == .android {
            return android?.deviceId ?? android?.avd ?? (android?.driverId == "android-device" ? "physical:auto" : "")
        }
        return ""
    }

    /// A platform/package edit does not convert existing recordings to another app.
    /// Native replay and Appium must reject incompatible artifacts before side effects.
    func validateReplayArtifact(_ artifact: SessionArtifactBundle) throws {
        guard artifact.schemaVersion == "cuyscout.session-artifact.v1", artifact.recording?.steps.isEmpty == false else {
            throw AppIssue.message("El artefacto no contiene una prueba grabada")
        }
        guard artifact.session.device.platform == platform else {
            throw AppIssue.message("La plataforma de la grabación es \(artifact.session.device.platform.platformName) y la del proyecto es \(platform.platformName). Cambia la plataforma del proyecto o vuelve a grabar el escenario.")
        }
        if platform == .android {
            guard let android else { throw AppIssue.message("Configura primero la app Android del proyecto") }
            try android.validate()
            guard artifact.session.bundleIdentifier == android.applicationId else {
                throw AppIssue.message("El package de la grabación (\(artifact.session.bundleIdentifier ?? "desconocido")) no coincide con el configurado (\(android.applicationId)). Selecciona el package original o vuelve a grabar el escenario.")
            }
        }
    }

    func replayDestinations(devices: [Device], checkedDevices: [Device]?) -> [Device] {
        // A preflight contains only the requested kind, not a full device inventory.
        // Prefer its fresh entries without hiding other kinds or cold AVDs.
        var seen = Set<String>()
        return ((checkedDevices ?? []) + devices).filter {
            $0.platform == platform && ($0.isAvailable || (platform == .android && $0.state == "Shutdown"))
                && seen.insert($0.id).inserted
        }
    }

    func replayDeviceID(override: String?, devices: [Device]) -> String? {
        if let override { return override }
        guard platform == .android, let android else { return nil }
        if let serial = android.deviceId { return serial }
        guard let avd = android.avd else { return nil }
        return devices.first { $0.platform == .android && $0.kind == .simulator && $0.name == avd }?.id ?? avd
    }

    /// Shared by the recording UI and its contract tests. Android never asks for Apple signing.
    func recordingCapabilities(selection: String, devices: [Device]) throws -> [String: Any] {
        let selected = devices.first { $0.id == selection }
            ?? devices.first { $0.platform == platform && platform == .android && $0.kind == .simulator && $0.name == selection }
        if let selected, selected.platform != platform {
            throw AppIssue.message("El dispositivo no corresponde a la plataforma del proyecto")
        }
        var args: [String: Any] = ["platformName": platform == .android ? "Android" : "iOS", "projectDir": directory]
        if platform == .android {
            guard let android else { throw AppIssue.message("Configura primero la app Android") }
            try android.validate()
            let physical = selection == "physical:auto" || selected?.kind == .physical
                || (selected == nil && !selection.isEmpty && android.driverId == "android-device")
            args["driverId"] = physical ? "android-device" : "android-emulator"
            args["bundleIdentifier"] = android.applicationId
            if !android.apk.isEmpty { args["appPath"] = android.apk }
            if let activity = android.activity { args["appActivity"] = activity }
            if !selection.isEmpty && selection != "physical:auto" {
                if !physical, let selected {
                    if selection == selected.id && selected.state != "Shutdown" { args["deviceId"] = selected.id }
                    else { args["avd"] = selected.name }
                }
                else if !physical, selection == android.avd { args["avd"] = selection }
                else { args["deviceId"] = selection }
            }
        } else {
            let physical = selection == "physical:auto" || selected?.kind == .physical
            args["driverId"] = physical ? "ios-device" : "ios-simulator"
            let installer = physical ? physicalAppPath : appPath
            if physical && installer.isEmpty { args["bundleIdentifier"] = physicalBundleID }
            else {
                guard !installer.isEmpty else { throw AppIssue.message("Elige un instalador para este destino iOS") }
                args["appPath"] = installer
            }
            if let selected { args["deviceId"] = selected.id }
        }
        return try AgentSessionCapabilities.make(args)
    }
}

extension AndroidProjectConfiguration {
    func normalizedForUI() -> Self {
        func optional(_ text: String?) -> String? {
            let value = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return value.isEmpty ? nil : value
        }
        return .init(apk: (apk.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath,
                     applicationId: applicationId.trimmingCharacters(in: .whitespacesAndNewlines),
                     activity: optional(activity), driverId: driverId ?? "android-emulator", deviceId: optional(deviceId),
                     avd: driverId == "android-device" ? nil : optional(avd))
    }
}

struct AndroidConfigurationFields: View {
    @ObservedObject var model: ScoutAppModel
    @Binding var configuration: AndroidProjectConfiguration

    private var physical: Bool { configuration.driverId == "android-device" }
    private var destinations: [Device] {
        model.devices.filter { $0.platform == .android && $0.kind == (physical ? .physical : .simulator) }
    }
    private var destination: Binding<String> {
        Binding(get: { configuration.deviceId ?? configuration.avd ?? "" }, set: { value in
            configuration.deviceId = nil
            configuration.avd = nil
            if !value.isEmpty {
                if physical { configuration.deviceId = value }
                else { configuration.avd = value }
            }
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("APK (opcional si la app ya está instalada)").font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField("APK (opcional si la app ya está instalada)", text: $configuration.apk)
                Button("Elegir APK…") {
                    let panel = NSOpenPanel()
                    panel.title = "Selecciona la APK Android"
                    panel.canChooseDirectories = false
                    panel.allowsMultipleSelection = false
                    panel.allowedContentTypes = [UTType(filenameExtension: "apk") ?? .data]
                    if panel.runModal() == .OK, let url = panel.url { configuration.apk = url.path }
                }
            }
            Text("Package / applicationId").font(.caption).foregroundStyle(.secondary)
            TextField("Package / applicationId, p. ej. com.empresa.app", text: $configuration.applicationId)
            Text("Actividad inicial (opcional)").font(.caption).foregroundStyle(.secondary)
            TextField("Actividad inicial (opcional), p. ej. .MainActivity", text: Binding(
                get: { configuration.activity ?? "" }, set: { configuration.activity = $0 }))
            Picker("Destino Android", selection: Binding(get: { configuration.driverId ?? "android-emulator" }, set: {
                configuration.driverId = $0
                configuration.deviceId = nil
                configuration.avd = nil
            })) {
                Text("Emulador AVD").tag("android-emulator")
                Text("Dispositivo físico").tag("android-device")
            }.pickerStyle(.segmented)
            HStack {
                Picker(physical ? "Dispositivo" : "AVD", selection: destination) {
                    Text(physical ? "Automático (Android autorizado)" : "Automático (AVD disponible)").tag("")
                    let selected = destination.wrappedValue
                    let choices = destinations.map { physical ? $0.id : $0.name }
                    if !selected.isEmpty && !choices.contains(selected) { Text("\(selected) · configurado").tag(selected) }
                    ForEach(destinations, id: \.id) { device in
                        Text("\(device.name) · \(device.state)").tag(physical ? device.id : device.name)
                    }
                }
                Button("Actualizar", systemImage: "arrow.clockwise") { Task { await model.refreshAndroidDestinations() } }
            }
            Text(physical ? "Conecta el Android por USB, desbloquéalo y autoriza la depuración USB."
                 : "Puedes elegir un AVD apagado: CuyScout lo iniciará al abrir la sesión.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Requiere Android SDK y adb en esta Mac. La APK, el package y el destino se comparten con el agente en .cuyscout-project.json.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .textFieldStyle(.roundedBorder)
        .task { await model.refreshAndroidDestinations() }
    }
}

struct ProjectConfigurationSheet: View {
    @ObservedObject var model: ScoutAppModel
    let project: ScoutProject
    @Environment(\.dismiss) private var dismiss
    @State private var platform: Device.Platform
    @State private var android: AndroidProjectConfiguration
    @State private var error: String?

    init(model: ScoutAppModel, project: ScoutProject) {
        self.model = model
        self.project = project
        _platform = State(initialValue: project.platform)
        _android = State(initialValue: project.android ?? .init(applicationId: "", driverId: "android-emulator"))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Configurar app y destino").font(.title2.bold())
            Picker("Plataforma", selection: $platform) {
                Text("iOS").tag(Device.Platform.ios)
                Text("Android").tag(Device.Platform.android)
            }.pickerStyle(.segmented)
            if platform == .android {
                AndroidConfigurationFields(model: model, configuration: $android)
            } else {
                Text("Los instaladores de simulador y de iPhone se eligen en el menú del proyecto. Se conservan al cambiar de plataforma.")
                    .foregroundStyle(.secondary)
            }
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Button("Cancelar") { dismiss() }
                Spacer()
                Button("Guardar") {
                    do {
                        try model.configureProject(project, platform: platform, android: android.normalizedForUI())
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }.buttonStyle(.borderedProminent)
            }
        }
        .padding(24).frame(width: 640)
    }
}
