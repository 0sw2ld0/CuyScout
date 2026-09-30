import AppKit
import CuyScoutCore
import Foundation
import SwiftUI

struct ExplorationView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: ScoutAppModel
    let project: ScoutProject

    @State private var sessionID: String?
    @State private var selectedDeviceID = ""
    @State private var attachedExternally = false
    @State private var observation: AgentObservation?
    @State private var screenshot: NSImage?
    @State private var selectedAction = 0
    @State private var inputText = ""
    @State private var scenarioName = ""
    @State private var working = false
    @State private var message: String?
    @State private var showRiskConfirmation = false
    @State private var showCloseConfirmation = false

    private var selectedSuggestion: ActionSuggestion? {
        guard let observation, observation.actions.indices.contains(selectedAction) else { return nil }
        return observation.actions[selectedAction]
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Explorar \(project.name)").font(.title2.bold())
                    Text(sessionID.map { "Sesión \($0)" } ?? "Usa la app y guarda una prueba grabada")
                        .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Spacer()
                if sessionID != nil {
                    Button("Actualizar pantalla", systemImage: "arrow.clockwise") { Task { await observe() } }
                    Button("Capturar", systemImage: "camera") { Task { await capture() } }
                }
                Button("Cerrar") {
                    if sessionID != nil { showCloseConfirmation = true } else { dismiss() }
                }
            }
            .padding(18)
            Divider()

            if sessionID == nil {
                VStack(spacing: 15) {
                    Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                        .font(.system(size: 50)).foregroundStyle(.tint)
                    Text("Grabar prueba con CuyScout").font(.title3.bold())
                    Text("CuyScout reservará un dispositivo, abrirá el runner XCTest y grabará las acciones del agente. Puedes observar la sesión desde aquí.")
                        .multilineTextAlignment(.center).foregroundStyle(.secondary)
                        .frame(maxWidth: 440)
                    Text(installedBundleID.map { "App ya instalada en el iPhone: \($0)" }
                         ?? (effectiveAppPath.isEmpty ? "Sin instalador ni app instalada para este tipo de dispositivo; elígelo en el menú del proyecto" : effectiveAppPath))
                        .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    Picker("Dispositivo", selection: $selectedDeviceID) {
                        Text("Automático (simulador)").tag("")
                        Text("Automático (iPhone físico)").tag("physical:auto")
                        ForEach(model.devices.filter(\.isAvailable), id: \.id) { device in
                            Text("\(device.name) · \(device.kind == .physical ? "iPhone físico" : "Simulador") · \(device.runtime)").tag(device.id)
                        }
                    }
                    .frame(maxWidth: 440)
                    if wantsPhysical {
                        SigningTeamField(model: model)
                            .frame(maxWidth: 440)
                        TextField("IP local de esta Mac", text: $model.physicalHost)
                            .frame(maxWidth: 440)
                        Text("Conserva el iPhone desbloqueado al iniciar. El token y la conexión MCP se configuran automáticamente en esta Mac.")
                            .font(.caption).foregroundStyle(.secondary)
                            .frame(maxWidth: 440)
                    }
                    Button(working ? "Preparando dispositivo…" : "Grabar prueba") {
                        Task { await start() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(working || (effectiveAppPath.isEmpty && installedBundleID == nil))
                    if !model.activeSessions.isEmpty {
                        Divider().frame(maxWidth: 440)
                        Text("Sesiones del agente en este gateway").font(.headline)
                        ForEach(model.activeSessions, id: \.id) { active in
                            Button("Ver \(active.device.name) · \(active.bundleIdentifier ?? active.id)\(active.leaseExpired == true ? " · caducada" : "")") {
                                sessionID = active.id
                                attachedExternally = true
                                Task { await observe(); await capture() }
                            }
                            .disabled(active.leaseExpired == true)
                            .help(active.leaseExpired == true ? "Caducó por inactividad y ya no acepta comandos; el agente debe cerrarla y abrir otra" : "")
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 15) {
                            if let screenshot {
                                Image(nsImage: screenshot)
                                    .resizable().scaledToFit()
                                    .frame(maxWidth: 430)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
                            } else {
                                Label("Pulsa Capturar para ver la pantalla del dispositivo", systemImage: "camera")
                                    .frame(maxWidth: .infinity, minHeight: 220)
                                    .foregroundStyle(.secondary)
                                    .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
                            }
                            if let observation {
                                Text(observation.title.isEmpty ? observation.context : observation.title)
                                    .font(.headline)
                                Text("Estado: \(observation.stateId)")
                                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                                GroupBox("Textos visibles") {
                                    VStack(alignment: .leading, spacing: 6) {
                                        if observation.texts.isEmpty { Text("No hay textos visibles").foregroundStyle(.secondary) }
                                        ForEach(observation.texts, id: \.self) { Text($0).textSelection(.enabled) }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                                }
                            }
                        }
                        .padding(18)
                    }
                    .frame(minWidth: 430, maxWidth: .infinity)
                    Divider()
                    VStack(alignment: .leading, spacing: 13) {
                        Text("Acciones disponibles").font(.headline)
                        if let observation, !observation.actions.isEmpty {
                            List(selection: $selectedAction) {
                                ForEach(observation.actions.indices, id: \.self) { index in
                                    let suggestion = observation.actions[index]
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(actionTitle(suggestion.action)).fontWeight(.medium)
                                        Text(suggestion.reason).font(.caption).foregroundStyle(.secondary)
                                    }
                                    .tag(index)
                                }
                            }
                            if needsInput(selectedSuggestion?.action) {
                                if isPassword(selectedSuggestion?.action) {
                                    SecureField("Texto para el campo", text: $inputText)
                                } else {
                                    TextField("Texto para el campo", text: $inputText)
                                }
                            }
                            Button(working ? "Ejecutando…" : "Ejecutar acción") { prepareAction() }
                                .buttonStyle(.borderedProminent)
                                .disabled(attachedExternally || working || (needsInput(selectedSuggestion?.action) && inputText.isEmpty))
                        } else {
                            Text("La observación aún no ofrece controles interactivos.")
                                .foregroundStyle(.secondary)
                        }
                        Divider()
                        if attachedExternally {
                            Text("Sesión controlada por el agente").font(.headline)
                            Text("Esta vista es de solo lectura. El agente conserva la sesión y exporta la prueba al terminar.")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("Guardar la prueba").font(.headline)
                            TextField("Nombre del escenario", text: $scenarioName)
                            Button("Exportar a output/ y cerrar sesión") { Task { await saveRecording() } }
                                .disabled(working || !validScenarioName)
                            Text("Se guardarán el artefacto redactado, el script TypeScript, la validación y los valores locales protegidos.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(18)
                    .frame(minWidth: 330, idealWidth: 365, maxWidth: 430)
                }
            }

            if let message {
                Divider()
                Text(message).font(.callout).foregroundStyle(.secondary)
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(12)
            }
        }
        .frame(minWidth: 950, minHeight: 620)
        .confirmationDialog("Esta acción puede cambiar datos en la app. ¿Ejecutarla?", isPresented: $showRiskConfirmation) {
            Button("Ejecutar acción") { Task { await executeSelectedAction() } }
            Button("Cancelar", role: .cancel) { }
        }
        .confirmationDialog(attachedExternally ? "¿Salir del monitor?" : "¿Qué hacer con la sesión sin exportar?", isPresented: $showCloseConfirmation) {
            Button("Salir y mantener sesión") { dismiss() }
            if !attachedExternally { Button("Terminar sin exportar", role: .destructive) { Task { await closeSession() } } }
            Button("Seguir observando", role: .cancel) { }
        }
        .onDisappear {
            // Closing the visual panel must not delete a session an agent is driving.
        }
        .task {
            if model.connected { await model.refresh() }
            if model.devices.contains(where: { $0.kind == .physical && $0.isAvailable }) {
                selectedDeviceID = "physical:auto"
            }
            while !Task.isCancelled {
                await model.refreshActiveSessions()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    private var validScenarioName: Bool {
        !scenarioName.isEmpty && scenarioName.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]*$", options: .regularExpression) != nil
    }

    private var wantsPhysical: Bool {
        selectedDeviceID == "physical:auto" || model.devices.first(where: { $0.id == selectedDeviceID })?.kind == .physical
    }

    private var effectiveAppPath: String { wantsPhysical ? project.physicalAppPath : project.appPath }
    /// En iPhone, sin instalador se usa la app ya instalada que eligió el proyecto.
    private var installedBundleID: String? { wantsPhysical && project.physicalAppPath.isEmpty && !project.physicalBundleID.isEmpty ? project.physicalBundleID : nil }

    private func start() async {
        guard !effectiveAppPath.isEmpty || installedBundleID != nil else { message = "Elige primero un instalador .app o .ipa, o una app ya instalada en el iPhone"; return }
        working = true
        defer { working = false }
        do {
            await model.startGateway(physical: wantsPhysical)
            guard let client = model.client, model.connected else { throw AppIssue.message(model.notice ?? "Gateway desconectado") }
            let selected = model.devices.first { $0.id == selectedDeviceID }
            var requested: [String: Any] = ["platformName": "iOS", "appium:automationName": "XCUITest",
                                             "appium:driverId": wantsPhysical ? "ios-device" : "ios-simulator"]
            if let installedBundleID { requested["appium:bundleId"] = installedBundleID } else { requested["appium:app"] = effectiveAppPath }
            if let selected { requested["appium:udid"] = selected.id }
            let capabilities: [String: Any] = ["capabilities": ["alwaysMatch": requested]]
            let response: SessionCreationEnvelope = try await client.request("session", method: "POST",
                body: JSONSerialization.data(withJSONObject: capabilities))
            sessionID = response.value.sessionId
            attachedExternally = false
            message = "Esperando al runner XCTest…"
            for _ in 0..<120 {
                let readiness: ValueEnvelope<SessionReadiness> = try await client.request("session/\(response.value.sessionId)/readiness")
                if readiness.value.interactionReady {
                    await observe()
                    await capture()
                    message = nil
                    return
                }
                try await Task.sleep(nanoseconds: 1_000_000_000)
            }
            throw AppIssue.message("El runner no estuvo listo en 120 segundos")
        } catch { message = error.localizedDescription }
    }

    private func observe() async {
        guard let sessionID, let client = model.client else { return }
        do {
            let response: ValueEnvelope<AgentObservation> = try await client.request("session/\(sessionID)/observe?maxActions=30")
            observation = response.value
            selectedAction = 0
            inputText = ""
            message = nil
        } catch { message = error.localizedDescription }
    }

    private func capture() async {
        guard let sessionID, let client = model.client else { return }
        do {
            screenshot = NSImage(data: try await client.requestData("session/\(sessionID)/screenshot/raw"))
        } catch { message = error.localizedDescription }
    }

    private func prepareAction() {
        guard let suggestion = selectedSuggestion else { return }
        if suggestion.risk == "high" { showRiskConfirmation = true }
        else { Task { await executeSelectedAction() } }
    }

    private func executeSelectedAction() async {
        guard let sessionID, let suggestion = selectedSuggestion, let client = model.client else { return }
        working = true
        defer { working = false }
        do {
            let action: ScoutAction
            switch suggestion.action {
            case .typeElement(let selector, _): action = .typeElement(selector, text: inputText)
            case .type: action = .type(inputText)
            default: action = suggestion.action
            }
            let _ = try await client.requestData("session/\(sessionID)/actions", method: "POST", body: JSONEncoder().encode(action))
            await observe()
            await capture()
        } catch { message = error.localizedDescription }
    }

    private func saveRecording() async {
        guard validScenarioName, let sessionID, let client = model.client else { return }
        working = true
        defer { working = false }
        do {
            let validation = try await client.requestData("session/\(sessionID)/recording/plan/validate")
            let typescript = try await client.requestData("session/\(sessionID)/recording/appium/typescript")
            let artifact = try await client.requestData("session/\(sessionID)/artifacts")
            let values = try await client.requestData("session/\(sessionID)/recording/replay-values", method: "POST")
            let output = project.url.appendingPathComponent("output", isDirectory: true)
            let secrets = project.url.appendingPathComponent("fixtures/replay-values", isDirectory: true)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: secrets, withIntermediateDirectories: true)
            let ignore = secrets.appendingPathComponent(".gitignore")
            if !FileManager.default.fileExists(atPath: ignore.path) {
                try "*\n!.gitignore\n".write(to: ignore, atomically: true, encoding: .utf8)
            }
            try validation.write(to: output.appendingPathComponent("\(scenarioName).validate.json"), options: .atomic)
            try typescript.write(to: output.appendingPathComponent("\(scenarioName).ts"), options: .atomic)
            try artifact.write(to: output.appendingPathComponent("\(scenarioName).cuyscout.json"), options: .atomic)
            try writePrivate(values, to: secrets.appendingPathComponent("\(scenarioName).json"))
            let _ = try await client.requestData("session/\(sessionID)", method: "DELETE")
            self.sessionID = nil
            await model.refresh()
            dismiss()
        } catch { message = error.localizedDescription }
    }

    private func writePrivate(_ data: Data, to url: URL) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            guard fm.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                throw AppIssue.message("No se pudo crear el fixture privado")
            }
        }
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: data)
    }

    private func closeSession() async {
        if let sessionID, let client = model.client {
            let _ = try? await client.requestData("session/\(sessionID)", method: "DELETE")
        }
        sessionID = nil
        dismiss()
    }

    private func needsInput(_ action: ScoutAction?) -> Bool {
        guard let action else { return false }
        switch action { case .typeElement, .type: return true; default: return false }
    }

    private func isPassword(_ action: ScoutAction?) -> Bool {
        guard case .typeElement(let selector, _) = action else { return false }
        return selector.value.lowercased().contains("password") || selector.value.lowercased().contains("contraseña")
    }

    private func actionTitle(_ action: ScoutAction) -> String {
        switch action {
        case .tapElement(let selector): return "Tocar · \(selector.value)"
        case .typeElement(let selector, _): return "Escribir · \(selector.value)"
        case .waitFor(let selector, _): return "Esperar · \(selector.value)"
        case .assertVisible(let selector): return "Verificar visible · \(selector.value)"
        default: return String(describing: action)
        }
    }
}

private struct ValueEnvelope<T: Decodable & Sendable>: Decodable, Sendable { let value: T }
private struct SessionCreationEnvelope: Decodable {
    struct Value: Decodable { let sessionId: String }
    let value: Value
}

/// Equipo de Apple que firma el runner: se detecta en esta Mac y solo se pregunta si hay varios.
struct SigningTeamField: View {
    @ObservedObject var model: ScoutAppModel

    var body: some View {
        HStack {
            if model.signingTeams.isEmpty {
                TextField("Team ID de Xcode", text: $model.physicalTeamID)
                    .help("No hay cuentas de Apple en Xcode. Inicia sesión en Xcode → Ajustes → Cuentas (una cuenta gratuita sirve) o escribe el Team ID.")
            } else {
                Picker("Firmar con", selection: $model.physicalTeamID) {
                    if !model.signingTeams.contains(where: { $0.id == model.physicalTeamID }) {
                        Text(model.physicalTeamID.isEmpty ? "Elige un equipo" : model.physicalTeamID).tag(model.physicalTeamID)
                    }
                    ForEach(model.signingTeams, id: \.id) { team in
                        Text(team.label).tag(team.id)
                    }
                }
            }
            Button {
                model.refreshSigningTeams()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Volver a buscar equipos en Xcode y el llavero")
        }
    }
}
