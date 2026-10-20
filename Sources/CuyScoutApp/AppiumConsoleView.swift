import AppKit
import CuyScoutCore
import SwiftUI

/// Consola integrada: ejecuta un comando de shell en la carpeta del proyecto y muestra su
/// salida en vivo. Detener corta el comando y todo lo que lanzó (p. ej. Appium).
@MainActor
final class ConsoleRunner: ObservableObject {
    @Published var output = ""
    @Published private(set) var running = false
    @Published private(set) var lastStatus: Int32?
    private var process: Process?

    func run(_ command: String, in directory: URL, environment extra: [String: String] = [:], onExit: (@MainActor @Sendable (Int32) -> Void)? = nil) {
        guard !running else { return }
        output += "$ \(command)\n"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.currentDirectoryURL = directory
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = (environment["PATH"] ?? "/usr/bin:/bin") + ":/opt/homebrew/bin:/usr/local/bin:\(NSHomeDirectory())/.local/bin"
        environment.merge(extra) { _, new in new }
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = String(decoding: data, as: UTF8.self)
            Task { @MainActor in self?.output += text }
        }
        process.terminationHandler = { [weak self] finished in
            pipe.fileHandleForReading.readabilityHandler = nil
            let status = finished.terminationStatus
            Task { @MainActor in
                guard let self else { return }
                self.running = false
                self.lastStatus = status
                self.output += status == 0 ? "\n✓ Terminado\n\n" : "\n✗ Terminó con código \(status)\n\n"
                onExit?(status)
            }
        }
        do {
            try process.run()
            self.process = process
            running = true
            lastStatus = nil
        } catch {
            output += "No se pudo ejecutar: \(error.localizedDescription)\n"
        }
    }

    func stop() {
        guard let process, process.isRunning else { return }
        // Primero los hijos (Appium, node), luego el comando: si no, quedan corriendo.
        Self.terminateTree(process.processIdentifier)
        output += "\n■ Detenido por el usuario\n"
    }

    private static func terminateTree(_ pid: Int32) {
        let finder = Process()
        finder.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        finder.arguments = ["-P", String(pid)]
        let pipe = Pipe()
        finder.standardOutput = pipe
        try? finder.run()
        finder.waitUntilExit()
        let children = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .split(separator: "\n").compactMap { Int32($0) }
        for child in children { terminateTree(child) }
        kill(pid, SIGTERM)
    }
}

/// Requisito que reporta `scripts/replay-appium.sh --check`.
struct AppiumRequirement: Identifiable, Equatable {
    let name: String
    let ok: Bool
    let installCommand: String
    var id: String { name }

    static func parse(_ output: String) -> [AppiumRequirement] {
        output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 3, parts[0] == "OK" || parts[0] == "FALTA" else { return nil }
            return AppiumRequirement(name: parts[1], ok: parts[0] == "OK", installCommand: parts[2])
        }
    }
}

/// El comando que corre una prueba con Appium. Siempre lleva la plataforma: un proyecto con iOS y Android elige la de la
/// ejecución con `CUYSCOUT_PLATFORM`, y sin ella el script usaría la principal del proyecto.
enum AppiumCommand {
    static func run(scenario: String, platform: Device.Platform, deviceID: String) -> String {
        var parts = ["CUYSCOUT_PLATFORM=\(platform.rawValue)"]
        if !deviceID.isEmpty { parts.append("CUYSCOUT_APPIUM_UDID=\(shellQuote(deviceID))") }
        parts.append("scripts/replay-appium.sh \(shellQuote(scenario))")
        return parts.joined(separator: " ")
    }
    static func shellQuote(_ value: String) -> String {
        value.range(of: #"^[A-Za-z0-9._/-]+$"#, options: .regularExpression) != nil ? value : "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// Panel «Reejecutar con Appium»: requisitos con su comando de instalación y el comando que
/// corre la prueba exportada, cada uno con su botón Ejecutar, sobre la consola integrada.
struct AppiumConsoleView: View {
    @ObservedObject var model: ScoutAppModel
    let project: ScoutProject
    let scenario: ProjectScenario
    @Environment(\.dismiss) private var dismiss
    @StateObject private var console = ConsoleRunner()
    @State private var requirements: [AppiumRequirement] = []
    @State private var checking = false
    @State private var prepareError: String?
    @State private var deviceID = ""

    private var script: URL { project.url.appendingPathComponent("scripts/replay-appium.sh") }
    /// Con un dispositivo elegido el comando copiado lleva su UDID: es el mismo que se ejecuta.
    private var runCommand: String { AppiumCommand.run(scenario: scenario.name, platform: project.platform, deviceID: deviceID) }
    private var ready: Bool { !requirements.isEmpty && requirements.allSatisfy(\.ok) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reejecutar con Appium").font(.title2.bold())
            Text("Corre la prueba exportada con Appium, fuera de CuyScout, para validar que funciona antes de llevarla a CI. Cierra antes las sesiones de CuyScout en ese dispositivo.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !FileManager.default.isExecutableFile(atPath: script.path) {
                Text("El proyecto no tiene scripts/replay-appium.sh: actualiza los scripts de CuyScout (menú ⋯ → Actualizar scripts de CuyScout).")
                    .foregroundStyle(.orange)
            }
            GroupBox("Requisitos") {
                VStack(alignment: .leading, spacing: 8) {
                    if checking { ProgressView().controlSize(.small) }
                    ForEach(requirements) { requirement in
                        HStack(alignment: .firstTextBaseline) {
                            Image(systemName: requirement.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(requirement.ok ? .green : .red)
                            Text(requirement.name)
                            Spacer()
                        }
                        if !requirement.ok {
                            CommandRow(command: requirement.installCommand, disabled: console.running) {
                                console.run(requirement.installCommand, in: project.url) { _ in Task { await check() } }
                            }
                        }
                    }
                    Button("Volver a revisar", systemImage: "arrow.clockwise") { Task { await check() } }
                        .disabled(checking || console.running)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }
            GroupBox("Ejecutar la prueba") {
                VStack(alignment: .leading, spacing: 6) {
                    Picker("Dispositivo", selection: $deviceID) {
                        Text(project.platform == .android ? "Destino Android configurado" : "Automático (primer iPhone encendido)").tag("")
                        ForEach(model.devices.filter { $0.platform == project.platform && $0.isAvailable }, id: \.id) { device in
                            Text("\(device.name) · \(device.kind == .physical ? "Físico" : "Emulador / simulador") · \(device.runtime)\(device.state == "Booted" ? " · encendido" : "")").tag(device.id)
                        }
                    }
                    .disabled(console.running)
                    CommandRow(command: runCommand, disabled: !ready || console.running) { runTest() }
                    if let prepareError { Text(prepareError).foregroundStyle(.red) }
                }
                .padding(4)
            }
            ConsoleOutput(text: console.output)
            HStack {
                Button("Limpiar consola") { console.output = "" }.disabled(console.running)
                Spacer()
                if console.running { Button("Detener", role: .destructive) { console.stop() } }
                Button("Cerrar") { console.stop(); dismiss() }
            }
        }
        .padding(20)
        .frame(minWidth: 760, minHeight: 620)
        .task { await check() }
    }

    private func check() async {
        guard FileManager.default.isExecutableFile(atPath: script.path) else { return }
        checking = true
        defer { checking = false }
        let path = script.path, platform = project.platform
        let output = await Task.detached { () -> String in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = ["--check"]
            // Sin la plataforma, el script revisa los requisitos de la principal del proyecto (p. ej. XCUITest para un escenario Android).
            var environment = ProcessInfo.processInfo.environment
            environment["CUYSCOUT_PLATFORM"] = platform.rawValue
            process.environment = environment
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return "" }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(decoding: data, as: UTF8.self)
        }.value
        requirements = AppiumRequirement.parse(output)
    }

    /// Regenera el TypeScript desde la grabación (siempre la versión actual del exportador)
    /// y lo pasa al script junto con el equipo de firma para un iPhone físico.
    private func runTest() {
        prepareError = nil
        guard let artifactURL = scenario.artifactURL else { prepareError = "Este escenario no tiene grabación"; return }
        let destination = project.url.appendingPathComponent("output/\(scenario.name).appium.ts")
        do {
            let artifact = try Data(contentsOf: artifactURL)
            try project.validateReplayArtifact(JSONDecoder().decode(SessionArtifactBundle.self, from: artifact))
            let source = try AppiumExportFormat.typescript.source(fromArtifactData: artifact)
            try source.write(to: destination, atomically: true, encoding: .utf8)
        } catch {
            prepareError = error.localizedDescription
            return
        }
        var environment = ["CUYSCOUT_APPIUM_SCRIPT": destination.path, "CUYSCOUT_PLATFORM": project.platform.rawValue]
        let team = model.physicalTeamID.trimmingCharacters(in: .whitespaces)
        if !team.isEmpty && project.platform == .ios { environment["CUYSCOUT_DEVELOPMENT_TEAM"] = team }
        if !deviceID.isEmpty { environment["CUYSCOUT_APPIUM_UDID"] = deviceID }
        console.run(runCommand, in: project.url, environment: environment)
    }

}

private struct CommandRow: View {
    let command: String
    let disabled: Bool
    let action: () -> Void
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(command)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            Button("Copiar") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
            }
            Button("Ejecutar", systemImage: "play.fill", action: action)
                .buttonStyle(.borderedProminent)
                .disabled(disabled)
        }
    }
}

private struct ConsoleOutput: View {
    let text: String
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(text.isEmpty ? "La salida de los comandos aparece aquí." : text)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(text.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .id("end")
            }
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .frame(minHeight: 220)
            .onChange(of: text) { _ in proxy.scrollTo("end", anchor: .bottom) }
        }
    }
}
