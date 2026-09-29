import AppKit
import CuyScoutCore
import SwiftUI

enum CuyScoutTheme {
    static let sidebar = Color(red: 0.115, green: 0.155, blue: 0.18)
    static let accent = Color(red: 0.035, green: 0.34, blue: 0.40)
    static let canvas = Color(red: 0.97, green: 0.978, blue: 0.982)
    static let border = Color(red: 0.86, green: 0.89, blue: 0.91)
    static let success = Color(red: 0.11, green: 0.65, blue: 0.34)
}

struct CuyScoutMark: View {
    let size: CGFloat

    var body: some View {
        Group {
            if let url = Bundle.main.url(forResource: "CuyScoutIcon-master", withExtension: "png", subdirectory: "Brand"),
               let icon = NSImage(contentsOf: url) {
                Image(nsImage: icon).resizable().scaledToFit()
            } else {
                Image(systemName: "viewfinder")
                    .resizable().scaledToFit()
                    .padding(size * 0.2)
                    .foregroundStyle(.white)
                    .background(CuyScoutTheme.accent, in: RoundedRectangle(cornerRadius: size * 0.22))
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Icono de CuyScout")
    }
}

private struct DashboardCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.system(size: 18, weight: .semibold))
            Divider()
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(CuyScoutTheme.border, lineWidth: 1))
    }
}

struct DashboardView: View {
    @ObservedObject var model: ScoutAppModel
    @Binding var selection: String?
    let onOpenProject: () -> Void
    let onNewProject: () -> Void
    @State private var showGatewaySettings = false
    @State private var editedURL = ""

    private var replayableCount: Int {
        model.projects.reduce(0) { $0 + WorkspaceFiles.scenarios(in: $1).filter(\.canReplay).count }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 21) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Centro de pruebas").font(.system(size: 32, weight: .bold, design: .rounded))
                        Text("Gestiona proyectos, reejecuta pruebas y explora resultados en un solo lugar.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 10)
                    Button { showGatewaySettings.toggle() } label: {
                        Label(model.connected ? "Gateway conectado" : "Gateway sin conexión",
                              systemImage: model.connected ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    }
                    .buttonStyle(.bordered)
                    .popover(isPresented: $showGatewaySettings) { gatewayPopover }
                    Button(action: onOpenProject) {
                        Label("Abrir proyecto", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                    Button(action: onNewProject) {
                        Label("Nuevo proyecto", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }

                if let notice = model.notice {
                    Label(notice, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                }

                HStack(spacing: 14) {
                    metric("Proyectos", value: model.projects.count, icon: "folder", destination: "projects")
                    metric("Pruebas listas", value: replayableCount, icon: "play.rectangle", destination: "projects")
                    metric("Artefactos", value: model.catalog.count, icon: "shippingbox", destination: "catalog")
                    metric("Dispositivos", value: model.devices.count, icon: "iphone", destination: "storage")
                }

                HStack(alignment: .top, spacing: 16) {
                    DashboardCard(title: "Proyectos recientes") {
                        if model.projects.isEmpty {
                            VStack(spacing: 12) {
                                empty("Abre un proyecto creado con cuyscout_init.sh para empezar.", icon: "folder.badge.plus")
                                Button("Abrir proyecto…", action: onOpenProject)
                                    .buttonStyle(.borderedProminent)
                            }
                        } else {
                            ForEach(model.projects.prefix(4)) { project in
                                Button { selection = "project:\(project.id.uuidString)" } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "folder.fill")
                                            .font(.title3)
                                            .foregroundStyle(CuyScoutTheme.accent)
                                            .frame(width: 38, height: 38)
                                            .background(CuyScoutTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(project.name).fontWeight(.semibold)
                                            Text("\(WorkspaceFiles.scenarios(in: project).filter(\.canReplay).count) pruebas listas")
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                if project.id != model.projects.prefix(4).last?.id { Divider() }
                            }
                        }
                    }
                    DashboardCard(title: "Últimas ejecuciones") {
                        if model.runs.isEmpty {
                            empty("Aún no hay ejecuciones. Abre un proyecto y pulsa Reejecutar.", icon: "play.rectangle")
                        } else {
                            ForEach(model.runs.prefix(4)) { run in
                                HStack(spacing: 11) {
                                    Image(systemName: run.success ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(run.success ? CuyScoutTheme.success : .orange)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(run.scenario).fontWeight(.medium).lineLimit(1)
                                        Text("\(run.executedSteps)/\(run.totalSteps) pasos · \(run.date.formatted(date: .abbreviated, time: .shortened))")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                if run.id != model.runs.prefix(4).last?.id { Divider() }
                            }
                        }
                    }
                }

                DashboardCard(title: "Dispositivos") {
                    if model.devices.isEmpty {
                        empty(model.connected ? "No hay dispositivos disponibles." : "Conecta el gateway para ver los dispositivos.", icon: "iphone")
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(model.devices.prefix(4), id: \.id) { device in
                                HStack(spacing: 12) {
                                    Image(systemName: "iphone.gen3")
                                        .font(.title2)
                                        .foregroundStyle(CuyScoutTheme.accent)
                                        .frame(width: 42, height: 42)
                                        .background(CuyScoutTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(device.name).fontWeight(.semibold).lineLimit(1)
                                        Text(device.runtime.components(separatedBy: ".").last ?? device.runtime)
                                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                    Circle().fill(device.state == "Booted" ? CuyScoutTheme.success : Color.gray)
                                        .frame(width: 8, height: 8)
                                    Text("\(device.kind == .physical ? "Físico" : "Simulador") · \(device.state)").font(.caption).foregroundStyle(.secondary)
                                }
                                .padding(12)
                                .background(CuyScoutTheme.canvas, in: RoundedRectangle(cornerRadius: 11))
                            }
                        }
                    }
                }
            }
            .padding(26)
            .frame(maxWidth: 1300, alignment: .leading)
        }
        .background(CuyScoutTheme.canvas)
    }

    private func metric(_ title: String, value: Int, icon: String, destination: String) -> some View {
        Button { selection = destination } label: {
            HStack(spacing: 13) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(CuyScoutTheme.accent)
                    .frame(width: 40, height: 40)
                    .background(CuyScoutTheme.accent.opacity(0.09), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.caption).foregroundStyle(.secondary)
                    Text(value.formatted()).font(.system(size: 25, weight: .semibold, design: .rounded))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(CuyScoutTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func empty(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 142)
    }

    private var gatewayPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Conexión del gateway").font(.headline)
            TextField("URL", text: $editedURL).textFieldStyle(.roundedBorder)
            SecureField("Token (opcional)", text: $model.token).textFieldStyle(.roundedBorder)
            HStack {
                if !model.connected {
                    Button(model.isStartingGateway ? "Iniciando…" : "Iniciar gateway") {
                        Task { await model.startGateway() }
                    }.disabled(model.isStartingGateway)
                }
                Spacer()
                Button("Conectar") {
                    model.setGatewayURL(editedURL)
                    Task { await model.refresh() }
                    showGatewaySettings = false
                }.buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .frame(width: 320)
        .onAppear { editedURL = model.gatewayURL }
    }
}

struct ProjectsLandingView: View {
    @ObservedObject var model: ScoutAppModel
    @Binding var selection: String?
    let onOpenProject: () -> Void
    let onNewProject: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Proyectos").font(.largeTitle.bold())
                        Text("Abre un proyecto para explorar o reejecutar sus pruebas.").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Abrir proyecto…", systemImage: "folder", action: onOpenProject)
                    Button("Nuevo proyecto", systemImage: "plus", action: onNewProject).buttonStyle(.borderedProminent)
                }
                if model.projects.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 36)).foregroundStyle(CuyScoutTheme.accent)
                        Text("Todavía no hay proyectos abiertos").font(.headline)
                        Text("Selecciona la carpeta creada con cuyscout_init.sh; CuyScout detectará tus pruebas en features/ y output/.")
                            .foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button("Abrir proyecto…", action: onOpenProject).buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, minHeight: 260)
                    .background(.white, in: RoundedRectangle(cornerRadius: 14))
                }
                ForEach(model.projects) { project in
                    Button { selection = "project:\(project.id.uuidString)" } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "folder.fill").font(.title2).foregroundStyle(CuyScoutTheme.accent)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(project.name).font(.headline)
                                Text(project.directory).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Text("\(WorkspaceFiles.scenarios(in: project).count) escenarios")
                                .font(.caption).foregroundStyle(.secondary)
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                        .padding(18)
                        .background(.white, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(CuyScoutTheme.border))
                    }.buttonStyle(.plain)
                }
            }.padding(26)
        }.background(CuyScoutTheme.canvas)
    }
}

struct ExploreLandingView: View {
    @ObservedObject var model: ScoutAppModel
    @State private var exploringProject: ScoutProject?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Explorar").font(.largeTitle.bold())
                Text("Selecciona un proyecto con instalador para iniciar una sesión visual.")
                    .foregroundStyle(.secondary)
                ForEach(model.projects) { project in
                    HStack {
                        Image(systemName: "iphone.gen3").foregroundStyle(CuyScoutTheme.accent)
                        VStack(alignment: .leading) {
                            Text(project.name).font(.headline)
                            Text(project.appPath.isEmpty ? "Instalador no configurado" : project.appPath)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Button("Explorar") { exploringProject = project }
                            .disabled(project.appPath.isEmpty)
                    }
                    .padding(18)
                    .background(.white, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(CuyScoutTheme.border))
                }
            }.padding(26)
        }
        .background(CuyScoutTheme.canvas)
        .sheet(item: $exploringProject) { project in ExplorationView(model: model, project: project) }
    }
}
