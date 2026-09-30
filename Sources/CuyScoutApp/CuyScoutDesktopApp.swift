import AppKit
import CuyScoutCore
import SwiftUI

@main
struct CuyScoutDesktopApp: App {
    var body: some Scene {
        WindowGroup("CuyScout") {
            RootView()
                .frame(minWidth: 1080, minHeight: 680)
                .tint(CuyScoutTheme.accent)
                .preferredColorScheme(.light)
        }
        .windowStyle(.titleBar)
        .commands { SidebarCommands() }
    }
}

private struct HideSystemSidebarToggle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) { content.toolbar(removing: .sidebarToggle) } else { content }
    }
}


private struct RootView: View {
    @StateObject private var model = ScoutAppModel()
    @State private var selection: String? = "overview"
    @State private var showingNewProject = false
    @State private var openProjectError: String?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            VStack(spacing: 0) {
                HStack(spacing: 11) {
                    CuyScoutMark(size: 41)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CuyScout").font(.system(size: 19, weight: .bold)).lineLimit(1).fixedSize()
                        Text("Pruebas iOS, más lejos").font(.caption).foregroundStyle(.white.opacity(0.58)).lineLimit(1).fixedSize()
                    }
                    Spacer()
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.top, 26)
                .padding(.bottom, 23)

                ScrollView {
                    VStack(alignment: .leading, spacing: 5) {
                        sidebarRow("Resumen", icon: "square.grid.2x2.fill", id: "overview")
                        sidebarRow("Proyectos", icon: "folder.fill", id: "projects")
                        sidebarRow("Explorar", icon: "safari.fill", id: "explore")
                        sidebarRow("Artefactos", icon: "shippingbox.fill", id: "catalog")
                        sidebarRow("Almacenamiento", icon: "externaldrive.fill", id: "storage")
                        Text("TUS PROYECTOS")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(1.2)
                            .foregroundStyle(.white.opacity(0.48))
                            .padding(.horizontal, 12)
                            .padding(.top, 24)
                            .padding(.bottom, 6)
                        ForEach(model.projects) { project in
                            sidebarRow(project.name, icon: "folder", id: "project:\(project.id.uuidString)")
                        }
                    }
                    .padding(.horizontal, 10)
                }

                HStack(spacing: 8) {
                    Circle().fill(model.connected ? CuyScoutTheme.success : .orange)
                        .frame(width: 8, height: 8)
                    Text(model.connected ? "Gateway conectado" : "Gateway desconectado")
                        .font(.caption)
                    Spacer()
                }
                .foregroundStyle(.white.opacity(0.75))
                .padding(18)
                .overlay(alignment: .top) { Divider().overlay(.white.opacity(0.15)) }
            }
            .background(CuyScoutTheme.sidebar)
            .frame(minWidth: 225)
            // La ventana es clara y AppKit pinta los ítems de la barra en oscuro, invisibles sobre
            // el sidebar oscuro. Estos dos botones son propios y planos para dibujarlos en blanco;
            // el de sidebar reemplaza al del sistema, que no admite otro color.
            .modifier(HideSystemSidebarToggle())
            .toolbar {
                ToolbarItemGroup {
                    Menu {
                        Button("Abrir proyecto existente…", systemImage: "folder.badge.plus") { openExistingProject() }
                        Button("Crear proyecto de pruebas…", systemImage: "plus.app") { showingNewProject = true }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "plus").font(.system(size: 15, weight: .medium))
                            Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                        }
                        .foregroundStyle(.white.opacity(0.9))
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Agregar o crear proyecto")
                    Button {
                        withAnimation { columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly }
                    } label: {
                        Image(systemName: "sidebar.left").font(.system(size: 15, weight: .regular))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .buttonStyle(.plain)
                    .help("Mostrar u ocultar la barra lateral")
                }
            }
        } detail: {
            Group {
                if selection == "catalog" {
                    CatalogView(model: model)
                } else if selection == "storage" {
                    StorageView(model: model)
                } else if selection == "projects" {
                    ProjectsLandingView(model: model, selection: $selection,
                                        onOpenProject: openExistingProject,
                                        onNewProject: { showingNewProject = true })
                } else if selection == "explore" {
                    ExploreLandingView(model: model)
                } else if let project = selectedProject {
                    ProjectView(model: model, project: project, selection: $selection)
                } else {
                    DashboardView(model: model, selection: $selection,
                                  onOpenProject: openExistingProject,
                                  onNewProject: { showingNewProject = true })
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    if columnVisibility == .detailOnly {
                        Button { withAnimation { columnVisibility = .all } } label: { Image(systemName: "sidebar.left") }
                            .help("Mostrar la barra lateral")
                    }
                }
                ToolbarItemGroup {
                    LayaToolbarButton(model: model)
                    Circle()
                        .fill(model.connected ? Color.green : Color.orange)
                        .frame(width: 9, height: 9)
                    Text(model.connected ? "Gateway conectado" : "Gateway desconectado")
                        .foregroundStyle(.secondary)
                    Button {
                        Task { await model.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Actualizar")
                }
            }
        }
        .task { await model.connectOnLaunch() }
        .sheet(isPresented: $showingNewProject) {
            NewProjectSheet(model: model) { projectID in
                selection = "project:\(projectID.uuidString)"
            }
        }
        .alert("No se pudo abrir el proyecto", isPresented: Binding(
            get: { openProjectError != nil },
            set: { if !$0 { openProjectError = nil } }
        )) {
            Button("Aceptar", role: .cancel) { openProjectError = nil }
        } message: {
            Text(openProjectError ?? "")
        }
    }

    private var selectedProject: ScoutProject? {
        guard let selection, selection.hasPrefix("project:"),
              let id = UUID(uuidString: String(selection.dropFirst("project:".count))) else { return nil }
        return model.projects.first { $0.id == id }
    }

    private func sidebarRow(_ title: String, icon: String, id: String) -> some View {
        Button { selection = id } label: {
            HStack(spacing: 13) {
                Image(systemName: icon).frame(width: 19)
                Text(title).lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.system(size: 14, weight: selection == id ? .semibold : .medium))
            .foregroundStyle(.white.opacity(selection == id ? 1 : 0.82))
            .padding(.horizontal, 13)
            .frame(height: 38)
            .contentShape(RoundedRectangle(cornerRadius: 9))
            .background(.white.opacity(selection == id ? 0.16 : 0), in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == id ? .isSelected : [])
    }

    private func openExistingProject() {
        guard let url = FilePicker.folder(title: "Selecciona la carpeta raíz del proyecto CuyScout") else { return }
        do {
            let project = try model.openProject(at: url)
            selection = "project:\(project.id.uuidString)"
        } catch {
            openProjectError = error.localizedDescription
        }
    }
}

private struct ProjectView: View {
    @ObservedObject var model: ScoutAppModel
    let project: ScoutProject
    @Binding var selection: String?
    @State private var selectedScenario: String?
    @State private var showForgetConfirmation = false
    @State private var showingExploration = false
    @State private var showingInstalledApps = false

    private var scenarios: [ProjectScenario] { WorkspaceFiles.scenarios(in: project) }
    private var current: ProjectScenario? {
        scenarios.first { $0.name == selectedScenario } ?? scenarios.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(project.name).font(.largeTitle.bold())
                    Text(project.directory).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Spacer()
                Button("Grabar prueba", systemImage: "record.circle") { showingExploration = true }
                    .disabled(project.appPath.isEmpty && project.physicalAppPath.isEmpty && project.physicalBundleID.isEmpty && model.activeSessions.isEmpty)
                    .help(project.appPath.isEmpty && project.physicalAppPath.isEmpty && project.physicalBundleID.isEmpty ? "Elige el instalador o una app ya instalada en el menú del proyecto" : "Preparar una grabación que el agente puede continuar")
                Button("Abrir carpeta", systemImage: "folder") { NSWorkspace.shared.open(project.url) }
                Menu {
                    Button("Instalador para simulador…") { chooseInstaller(physical: false) }
                    Button("Instalador firmado para iPhone…") { chooseInstaller(physical: true) }
                    Button("App ya instalada en el iPhone…") { showingInstalledApps = true }
                    Button("Quitar de CuyScout…", role: .destructive) { showForgetConfirmation = true }
                } label: { Image(systemName: "ellipsis.circle") }
                .help("Opciones del proyecto")
            }
            .padding(24)

            HStack(spacing: 0) {
                List(selection: $selectedScenario) {
                    ForEach(scenarios) { scenario in
                        HStack(spacing: 10) {
                            Image(systemName: scenario.canReplay ? "play.rectangle" : "text.book.closed")
                                .foregroundStyle(scenario.canReplay ? Color.accentColor : Color.secondary)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(scenario.name).fontWeight(.medium)
                                Text(scenario.canReplay ? "Lista para replay" : "Solo escenario .feature")
                                    .font(.caption).foregroundStyle(.secondary)
                                if let lastRun = scenario.lastRun, lastRun.status != .recorded {
                                    LastRunBadge(report: lastRun)
                                }
                            }
                            Spacer()
                            if scenario.hasValues { Image(systemName: "key.fill").foregroundStyle(.secondary) }
                        }
                        .tag(scenario.name)
                    }
                }
                .frame(minWidth: 260, idealWidth: 280, maxWidth: 320)
                Divider()
                if let current {
                    ScenarioDetail(model: model, project: project, scenario: current)
                        .id(current.id)
                } else {
                    EmptyState(title: "Sin escenarios", icon: "square.stack",
                               detail: "Coloca archivos .feature en features/ o artefactos .cuyscout.json en output/.")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .confirmationDialog("¿Quitar este proyecto de la lista?", isPresented: $showForgetConfirmation) {
            Button("Quitar de la lista", role: .destructive) {
                model.forgetProject(project.id)
                selection = "overview"
            }
        } message: {
            Text("Los archivos del proyecto permanecerán en su carpeta.")
        }
        .sheet(isPresented: $showingExploration) {
            ExplorationView(model: model, project: project)
        }
        .sheet(isPresented: $showingInstalledApps) {
            InstalledAppPicker(model: model, project: project)
        }
    }

    private func chooseInstaller(physical: Bool) {
        guard let url = FilePicker.installer(title: physical ? "Selecciona .app o .ipa firmado para iPhone" : "Selecciona el instalador de simulador") else { return }
        model.updateAppPath(projectID: project.id, path: url.path, physical: physical)
    }
}

private struct ScenarioDetail: View {
    @ObservedObject var model: ScoutAppModel
    let project: ScoutProject
    let scenario: ProjectScenario
    @State private var exportMessage: String?
    @State private var exportError: String?
    @State private var showingReplaySetup = false

    private var validation: ValidationSummary? { WorkspaceFiles.validation(for: scenario) }
    private var run: RunRecord? {
        model.runs.first { $0.projectID == project.id && $0.scenario == scenario.name }
    }
    private var isRunning: Bool { model.busyScenario == "\(project.id.uuidString)/\(scenario.name)" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(scenario.name).font(.title.bold())
                        Text(scenario.canReplay ? "Artefacto CuyScout disponible" : "Aún no se ha generado una prueba")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if scenario.canReplay {
                        Menu {
                            Button("TypeScript (.ts)") { exportAppium(.typescript) }
                            Button("Python (.py)") { exportAppium(.python) }
                        } label: {
                            Label("Exportar para Appium…", systemImage: "square.and.arrow.up")
                        }
                        .help("Exportar la grabación de esta prueba para ejecutarla con Appium")
                        Button {
                            showingReplaySetup = true
                        } label: {
                            Label(isRunning ? "Ejecutando…" : "Reejecutar prueba", systemImage: "play.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.busyScenario != nil)
                    }
                }
                if isRunning { ProgressView("Preparando simulador y ejecutando pasos…") }
                if let lastRun = scenario.lastRun {
                    GroupBox("Última corrida del agente") {
                        VStack(alignment: .leading, spacing: 6) {
                            LastRunBadge(report: lastRun)
                            if let step = lastRun.step { Text("Paso: \(step)").font(.callout) }
                            if lastRun.status == .blockedEnvironment {
                                Text("El entorno no dejó probar el escenario (no es un fallo de la app). Vuelve a ejecutarlo cuando el servicio esté disponible.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if let texts = lastRun.screenTexts, !texts.isEmpty {
                                Text("Pantalla: " + texts.prefix(4).joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if let exportMessage {
                    Label(exportMessage, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .textSelection(.enabled)
                }
                if let notice = model.notice { Text(notice).foregroundStyle(.secondary).textSelection(.enabled) }

                HStack(spacing: 12) {
                    statePill("Plan", validation.map { $0.valid ? "Válido" : "Con errores" } ?? "Sin validación",
                              validation?.valid == true ? .green : .secondary)
                    statePill("Datos", scenario.hasValues ? "Fixture local" : "Sin fixture",
                              scenario.hasValues ? .green : .secondary)
                    statePill("Último replay", run.map { $0.success ? "Pasó" : "Falló" } ?? "Sin ejecutar",
                              run.map { $0.success ? .green : .red } ?? .secondary)
                }

                if let run {
                    GroupBox("Última ejecución") {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(run.success ? "Prueba completada" : "Prueba fallida")
                                .font(.headline)
                                .foregroundStyle(run.success ? Color.green : Color.red)
                            Text("\(run.executedSteps) de \(run.totalSteps) pasos · \(run.date.formatted(date: .abbreviated, time: .shortened))")
                            if let failedStep = run.failedStep { Text("Paso fallido: \(failedStep)") }
                            if let error = run.error { Text(error).textSelection(.enabled) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                    }
                }

                if let validation, !validation.errors.isEmpty || !validation.warnings.isEmpty {
                    GroupBox("Validación del plan") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(validation.errors, id: \.self) { Text("• \($0)").foregroundStyle(.red) }
                            ForEach(validation.warnings, id: \.self) { Text("• \($0)").foregroundStyle(.orange) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                    }
                }

                if let feature = WorkspaceFiles.featureText(for: scenario) {
                    GroupBox("Escenario de negocio") {
                        Text(feature)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                }

                if let artifactURL = scenario.artifactURL {
                    Button("Mostrar artefacto en Finder", systemImage: "doc") {
                        NSWorkspace.shared.activateFileViewerSelecting([artifactURL])
                    }
                }
                if !project.appPath.isEmpty {
                    Text("Instalador: \(project.appPath)")
                        .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            .padding(24)
            .frame(maxWidth: 980, alignment: .leading)
        }
        .sheet(isPresented: $showingReplaySetup) {
            ReplaySetupView(model: model, project: project, scenario: scenario)
        }
        .alert("No se pudo exportar para Appium", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("Aceptar", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
    }

    private func exportAppium(_ format: AppiumExportFormat) {
        guard let artifactURL = scenario.artifactURL else { return }
        do {
            let source = try format.source(fromArtifactData: Data(contentsOf: artifactURL))
            let panel = NSSavePanel()
            panel.title = "Exportar prueba Appium en \(format.displayName)"
            panel.prompt = "Exportar"
            panel.canCreateDirectories = true
            panel.nameFieldStringValue = "\(scenario.name).appium.\(format.fileExtension)"
            let output = project.url.appendingPathComponent("output", isDirectory: true)
            panel.directoryURL = FileManager.default.fileExists(atPath: output.path) ? output : project.url
            panel.message = format == .typescript
                ? "Script para Appium y WebdriverIO. Revisa datos redactados y pasos antes de ejecutarlo."
                : "Script para Appium Python Client. Revisa datos redactados y pasos antes de ejecutarlo."
            guard panel.runModal() == .OK, let destination = panel.url else { return }
            try source.write(to: destination, atomically: true, encoding: .utf8)
            exportMessage = "Exportado \(format.displayName): \(destination.lastPathComponent)"
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func statePill(_ title: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).fontWeight(.medium).foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct ReplaySetupView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: ScoutAppModel
    let project: ScoutProject
    let scenario: ProjectScenario
    @State private var deviceID = ""
    @State private var preparation: ReplayPreparationMode = .restart
    @State private var report: ReplayPreflight?
    @State private var error: String?
    @State private var checking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Preparar replay").font(.title2.bold())
            Text("La prueba original no se modifica. Comprueba el dispositivo, la app, los valores y el runner antes de ejecutarla.")
                .foregroundStyle(.secondary)
            Picker("Dispositivo", selection: $deviceID) {
                Text("Automático (preferir el original)").tag("")
                ForEach((report?.availableDevices ?? model.devices).filter(\.isAvailable), id: \.id) { device in
                    Text("\(device.name) · \(device.kind == .physical ? "iPhone físico" : "Simulador") · \(device.runtime)").tag(device.id)
                }
            }
            .onChange(of: deviceID) { _ in report = nil }
            Picker("Preparación", selection: $preparation) {
                Text("Conservar estado y datos").tag(ReplayPreparationMode.preserve)
                Text("Reiniciar app, conservar datos").tag(ReplayPreparationMode.restart)
                Text("Reinstalar app, limpiar sus datos").tag(ReplayPreparationMode.reinstall)
            }
            .onChange(of: preparation) { _ in report = nil }
            if preparation == .reinstall && project.appPath.isEmpty {
                Label("Selecciona primero un instalador en el proyecto.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            if checking { ProgressView("Comprobando…") }
            if let report {
                GroupBox(report.ready ? "Listo para ejecutar" : "No se puede ejecutar todavía") {
                    VStack(alignment: .leading, spacing: 7) {
                        if let selected = report.selectedDevice {
                            Text("Destino: \(selected.name) (\(selected.state))")
                        }
                        Text(report.runnerReady ? "Runner XCTest: listo" : report.runnerCanBuild ? "Runner XCTest: se compilará al iniciar" : "Runner XCTest: no disponible")
                        ForEach(report.errors, id: \.self) { Label($0, systemImage: "xmark.circle").foregroundStyle(.red) }
                        ForEach(report.warnings, id: \.self) { Label($0, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                Button("Cancelar") { dismiss() }
                Spacer()
                Button("Comprobar") { Task { await check() } }.disabled(checking)
                Button("Ejecutar") {
                    let target = deviceID.isEmpty ? nil : deviceID
                    let mode = preparation
                    dismiss()
                    Task { await model.replay(project: project, scenario: scenario, deviceID: target, preparation: mode) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(report?.ready != true || checking || model.busyScenario != nil)
            }
        }
        .padding(24)
        .frame(width: 580)
        .task { await check() }
    }

    private func check() async {
        checking = true
        defer { checking = false }
        report = nil
        error = nil
        do {
            report = try await model.preflightReplay(project: project, scenario: scenario,
                deviceID: deviceID.isEmpty ? nil : deviceID, preparation: preparation)
        } catch { self.error = error.localizedDescription }
    }
}

private struct CatalogView: View {
    @ObservedObject var model: ScoutAppModel
    @State private var confirmingCleanup = false
    @State private var cleaning = false

    /// Artefactos grabados en un simulador que ya no existe (p. ej. borrado por una limpieza).
    /// Siguen siendo reproducibles en otro simulador, así que se marcan en vez de ocultarse.
    /// Un iPhone físico desconectado no cuenta: no se puede saber si dejó de existir.
    private var orphaned: [ArtifactDescriptor] {
        guard model.connected, !model.devices.isEmpty else { return [] }
        let alive = Set(model.devices.map(\.id))
        return model.catalog.filter { $0.driverID != "ios-device" && !alive.contains($0.deviceID) }
    }

    var body: some View {
        let orphanedIDs = Set(orphaned.map(\.sessionID))
        VStack(alignment: .leading, spacing: 15) {
            Text("Artefactos del gateway").font(.largeTitle.bold())
            Text("Pruebas persistidas en el servidor compartido. Para reejecutar con sus datos locales, abre el proyecto correspondiente.")
                .foregroundStyle(.secondary)
            if !orphaned.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text("\(orphaned.count) artefacto(s) se grabaron en simuladores que ya no existen. Se pueden reproducir en otro simulador, pero si no los necesitas puedes limpiarlos.")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button(cleaning ? "Limpiando…" : "Eliminar \(orphaned.count)…") { confirmingCleanup = true }
                        .disabled(cleaning)
                }
                .padding(12)
                .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
            }
            if model.catalog.isEmpty {
                EmptyState(title: model.connected ? "No hay artefactos" : "Gateway desconectado", icon: "archivebox")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.catalog, id: \.sessionID) { artifact in
                    HStack {
                        Image(systemName: "doc.zipper").foregroundStyle(.tint)
                        VStack(alignment: .leading) {
                            Text(artifact.sessionID).fontWeight(.medium).textSelection(.enabled)
                            HStack(spacing: 6) {
                                Text("\(artifact.deviceName) · \(artifact.recordedStepCount) pasos · \(artifact.bundleIdentifier ?? "sin bundle")")
                                    .font(.caption).foregroundStyle(.secondary)
                                if orphanedIDs.contains(artifact.sessionID) {
                                    Text("Simulador eliminado")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.orange)
                                        .padding(.horizontal, 6).padding(.vertical, 1)
                                        .background(Color.orange.opacity(0.12), in: Capsule())
                                }
                            }
                        }
                        Spacer()
                        if let date = artifact.savedAt {
                            Text(date, style: .date).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(24)
        .confirmationDialog("¿Eliminar \(orphaned.count) artefacto(s) de simuladores que ya no existen?", isPresented: $confirmingCleanup) {
            Button("Eliminar", role: .destructive) { Task { await cleanOrphaned() } }
        } message: {
            Text("No se puede deshacer. Las pruebas exportadas en tus proyectos (output/) no se tocan.")
        }
    }

    private func cleanOrphaned() async {
        cleaning = true
        defer { cleaning = false }
        var failed = 0
        for artifact in orphaned {
            do { try await model.deleteArtifact(artifact.sessionID) } catch { failed += 1 }
        }
        await model.refresh()
        if failed > 0 { model.notice = "No se pudieron eliminar \(failed) artefacto(s)" }
    }
}

private struct NewProjectSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: ScoutAppModel
    let created: (UUID) -> Void
    @State private var name = ""
    @State private var directory = ""
    @State private var installer = ""
    @State private var source: AppSource = .installer
    @State private var installedBundleID: String?
    @State private var repo = ""
    @AppStorage("cuyscout.newProject.vscode") private var vscode = true
    @AppStorage("cuyscout.newProject.mcp") private var mcp = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Crear proyecto de pruebas").font(.title2.bold())
            Text("Se generarán scripts, fixtures y AGENTS.md. Los escenarios .feature existentes se conservan.")
                .foregroundStyle(.secondary)
            TextField("Nombre de la app probada", text: $name)
            pathField("Carpeta del proyecto", value: $directory) {
                if let url = FilePicker.folder(title: "Carpeta del nuevo proyecto") { directory = url.path }
            }
            Picker("App probada", selection: $source) {
                Text("Instalador .app o .ipa").tag(AppSource.installer)
                Text("Ya instalada en el iPhone").tag(AppSource.installedOnDevice)
            }
            .pickerStyle(.segmented)
            if source == .installer {
                pathField("Instalador .app o .ipa", value: $installer) {
                    if let url = FilePicker.installer(title: "Instalador de la app probada") { installer = url.path }
                }
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Se prueba tal como está en el iPhone, sin reinstalarla ni borrar sus datos. Debe ser una compilación de desarrollo.")
                        .font(.caption).foregroundStyle(.secondary)
                    InstalledAppList(model: model, selected: $installedBundleID, minHeight: 170)
                }
            }
            pathField("Repositorio CuyScout (opcional)", value: $repo) {
                if let url = FilePicker.folder(title: "Repositorio CuyScout") { repo = url.path }
            }
            VStack(alignment: .leading, spacing: 3) {
                Toggle("Configurar para Visual Studio Code", isOn: $vscode)
                Text("Agrega los prompts /nuevo-escenario y /ejecutar-escenario de Copilot, la extensión Cucumber y el formato de .feature. No pisa tu .vscode/ existente.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 20)
            }
            VStack(alignment: .leading, spacing: 3) {
                Toggle("Usar MCP", isOn: $mcp)
                Text("Agrega a AGENTS.md las herramientas cuyscout_* de MCP. Déjalo apagado si el cliente del agente no tiene MCP configurado: usará solo HTTP/curl.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 20)
            }
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }
                Button("Crear proyecto") { create() }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.isEmpty || directory.isEmpty || !hasApp)
            }
        }
        .padding(25)
        .frame(width: 620)
        .onAppear {
            let candidate = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("Package.swift").path) {
                repo = candidate.path
            }
        }
    }

    private enum AppSource { case installer, installedOnDevice }

    private var hasApp: Bool {
        source == .installer ? !installer.isEmpty : installedBundleID != nil
    }

    private func pathField(_ title: String, value: Binding<String>, choose: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField(title, text: value).textFieldStyle(.roundedBorder)
                Button("Elegir…", action: choose)
            }
        }
    }

    private func create() {
        do {
            let folder = URL(fileURLWithPath: directory, isDirectory: true)
            try model.createProject(name: name, directory: folder,
                                    installer: source == .installer ? URL(fileURLWithPath: installer) : nil,
                                    physicalBundleID: source == .installedOnDevice ? installedBundleID : nil,
                                    repo: repo.isEmpty ? nil : URL(fileURLWithPath: repo, isDirectory: true),
                                    vscode: vscode, useMCP: mcp)
            if let project = model.projects.first(where: { $0.directory == folder.standardizedFileURL.path }) {
                created(project.id)
            }
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct EmptyState: View {
    let title: String
    let icon: String
    var detail: String = ""

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 34)).foregroundStyle(.secondary)
            Text(title).font(.headline)
            if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center) }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
    }
}

@MainActor
private enum FilePicker {
    static func folder(title: String) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func installer(title: String) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }
}

/// Estado de la última corrida del agente: "bloqueado por entorno" no es un fallo de la app.
struct LastRunBadge: View {
    let report: LastRunReport

    private var color: Color {
        switch report.status {
        case .recorded: .green
        case .blockedEnvironment: .orange
        case .failed: .red
        case .discarded: .secondary
        }
    }

    private var icon: String {
        switch report.status {
        case .recorded: "checkmark.circle.fill"
        case .blockedEnvironment: "exclamationmark.triangle.fill"
        case .failed: "xmark.octagon.fill"
        case .discarded: "minus.circle"
        }
    }

    var body: some View {
        Label {
            Text([report.title, report.reasonText, report.finishedDate?.formatted(date: .abbreviated, time: .shortened)]
                .compactMap { $0 }.joined(separator: " · "))
        } icon: { Image(systemName: icon) }
        .font(.caption)
        .foregroundStyle(color)
        .help(([report.step.map { "Paso: \($0)" }] + (report.screenTexts ?? []).prefix(4).map { Optional($0) })
            .compactMap { $0 }.joined(separator: "\n"))
    }
}
