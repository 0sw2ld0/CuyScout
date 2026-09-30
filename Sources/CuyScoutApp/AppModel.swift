import AppKit
import CuyScoutCore
import Darwin
import Foundation

struct ScoutProject: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var directory: String
    var appPath: String
    var physicalAppPath: String
    /// App ya instalada en el iPhone que se prueba sin instalador (alternativa a `physicalAppPath`).
    var physicalBundleID: String

    init(name: String, directory: String, appPath: String = "", physicalAppPath: String = "", physicalBundleID: String = "") {
        id = UUID()
        self.name = name
        self.directory = directory
        self.appPath = appPath
        self.physicalAppPath = physicalAppPath
        self.physicalBundleID = physicalBundleID
    }

    private enum CodingKeys: String, CodingKey { case id, name, directory, appPath, physicalAppPath, physicalBundleID }
    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        id = try fields.decode(UUID.self, forKey: .id)
        name = try fields.decode(String.self, forKey: .name)
        directory = try fields.decode(String.self, forKey: .directory)
        appPath = try fields.decode(String.self, forKey: .appPath)
        physicalAppPath = try fields.decodeIfPresent(String.self, forKey: .physicalAppPath) ?? ""
        physicalBundleID = try fields.decodeIfPresent(String.self, forKey: .physicalBundleID) ?? ""
    }

    var url: URL { URL(fileURLWithPath: directory, isDirectory: true) }
}

struct ProjectScenario: Identifiable {
    let name: String
    let artifactURL: URL?
    let featureURL: URL?
    let validationURL: URL?
    let valuesURL: URL?
    /// Última corrida del agente (`output/<escenario>.last-run.json`).
    var lastRun: LastRunReport? = nil

    var id: String { name }
    var canReplay: Bool { artifactURL != nil }
    var hasValues: Bool { valuesURL != nil }
}

struct ValidationSummary: Decodable {
    let valid: Bool
    let executable: Bool
    let errors: [String]
    let warnings: [String]
}

struct RunRecord: Codable, Identifiable {
    let id: UUID
    let projectID: UUID
    let scenario: String
    let date: Date
    let success: Bool
    let executedSteps: Int
    let totalSteps: Int
    let failedStep: Int?
    let error: String?
    let dismissedInterruptions: Int?

    init(projectID: UUID, scenario: String, result: ReplayResult) {
        id = UUID()
        self.projectID = projectID
        self.scenario = scenario
        date = Date()
        success = result.success
        executedSteps = result.executedSteps
        totalSteps = result.totalSteps
        failedStep = result.failedStep
        error = result.error
        dismissedInterruptions = result.dismissedInterruptions
    }
}

enum WorkspaceFiles {
    struct Installers: Codable {
        var simulator: String
        var physical: String
        /// App ya instalada en el iPhone (sin instalador); el agente crea la sesión con este bundle ID.
        var physicalBundleId: String? = nil
    }

    static func installers(in directory: URL) -> Installers? {
        let file = directory.appendingPathComponent(".cuyscout-project.json")
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(Installers.self, from: data)
    }

    /// Actualiza los instaladores conservando las demás claves del archivo (p. ej. `mcp`).
    static func saveInstallers(_ installers: Installers, in directory: URL, extra: [String: Any] = [:]) throws {
        let file = directory.appendingPathComponent(".cuyscout-project.json")
        var merged = (try? Data(contentsOf: file)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        merged["simulator"] = installers.simulator
        merged["physical"] = installers.physical
        merged["physicalBundleId"] = installers.physicalBundleId
        for (key, value) in extra { merged[key] = value }
        try JSONSerialization.data(withJSONObject: merged, options: [.sortedKeys]).write(to: file, options: .atomic)
    }

    static func configuredAppPath(in directory: URL) -> String? {
        let script = directory.appendingPathComponent("scripts/replay-cuyscout.sh")
        guard let source = try? String(contentsOf: script, encoding: .utf8) else { return nil }
        let prefix = "APP_PATH=\"${CUYSCOUT_REPLAY_APP_PATH:-"
        guard let line = source.split(separator: "\n").first(where: { $0.hasPrefix(prefix) && $0.hasSuffix("}\"") }) else { return nil }
        let value = String(line.dropFirst(prefix.count).dropLast(2))
        return FileManager.default.fileExists(atPath: value) ? value : nil
    }

    static func scenarios(in project: ScoutProject) -> [ProjectScenario] {
        let fm = FileManager.default
        let output = project.url.appendingPathComponent("output", isDirectory: true)
        let features = project.url.appendingPathComponent("features", isDirectory: true)
        let lastRunNames = Set(((try? fm.contentsOfDirectory(atPath: output.path)) ?? [])
            .filter { $0.hasSuffix(".last-run.json") }
            .map { String($0.dropLast(".last-run.json".count)) })
        let artifactNames = Set(((try? fm.contentsOfDirectory(atPath: output.path)) ?? [])
            .filter { $0.hasSuffix(".cuyscout.json") }
            .map { String($0.dropLast(".cuyscout.json".count)) })
        let featureNames = Set(((try? fm.contentsOfDirectory(atPath: features.path)) ?? [])
            .filter { $0.hasSuffix(".feature") }
            .map { String($0.dropLast(".feature".count)) })

        return artifactNames.union(featureNames).union(lastRunNames).sorted().map { name in
            let artifact = output.appendingPathComponent("\(name).cuyscout.json")
            let feature = features.appendingPathComponent("\(name).feature")
            let validation = output.appendingPathComponent("\(name).validate.json")
            let values = project.url.appendingPathComponent("fixtures/replay-values/\(name).json")
            return ProjectScenario(name: name,
                artifactURL: fm.fileExists(atPath: artifact.path) ? artifact : nil,
                featureURL: fm.fileExists(atPath: feature.path) ? feature : nil,
                validationURL: fm.fileExists(atPath: validation.path) ? validation : nil,
                valuesURL: fm.fileExists(atPath: values.path) ? values : nil,
                lastRun: LastRunReport.load(scenario: name, outputDirectory: output))
        }
    }

    static func validation(for scenario: ProjectScenario) -> ValidationSummary? {
        guard let url = scenario.validationURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ValidationSummary.self, from: data)
    }

    static func featureText(for scenario: ProjectScenario) -> String? {
        guard let url = scenario.featureURL else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}

enum AppIssue: LocalizedError {
    case message(String)
    var errorDescription: String? {
        if case .message(let message) = self { return message }
        return nil
    }
}

struct GatewayClient {
    let baseURL: URL
    let token: String?

    func request<T: Decodable>(_ path: String, method: String = "GET", body: Data? = nil) async throws -> T {
        let data = try await requestData(path, method: method, body: body)
        return try JSONDecoder().decode(T.self, from: data)
    }

    func requestData(_ path: String, method: String = "GET", body: Data? = nil) async throws -> Data {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        let route = path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        components?.path = "/" + route[0].trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components?.percentEncodedQuery = route.count == 2 ? String(route[1]) : nil
        guard let url = components?.url else { throw AppIssue.message("Ruta del gateway inválida") }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = path.contains("/replay") ? 600 : 20
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let token, !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await URLSession.direct.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw AppIssue.message("Respuesta HTTP inválida") }
        guard (200..<300).contains(response.statusCode) else {
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let value = object?["value"] as? [String: Any]
            let message = value?["message"] as? String ?? String(data: data, encoding: .utf8) ?? "Error HTTP \(response.statusCode)"
            throw AppIssue.message(message)
        }
        return data
    }
}

@MainActor
final class ScoutAppModel: ObservableObject {
    /// Un solo modelo para toda la app: todas las ventanas ven el mismo gateway y estado.
    static let shared = ScoutAppModel()

    @Published var projects: [ScoutProject] = []
    @Published var runs: [RunRecord] = []
    @Published var gatewayURL: String
    @Published var token: String
    @Published var connected = false
    @Published var devices: [Device] = []
    @Published var catalog: [ArtifactDescriptor] = []
    @Published var artifactStatus: ArtifactStoreStatus?
    @Published var simulatorStorage: [SimulatorStorageItem] = []
    @Published var busyScenario: String?
    @Published var lastResult: RunRecord?
    /// Todo aviso que ve la persona queda también en ~/Library/Logs/CuyScout/app.log.
    @Published var notice: String? { didSet { if let notice, notice != oldValue { ScoutLog.app.warning("aviso", notice) } } }
    @Published var isStartingGateway = false
    @Published var activeSessions: [Session] = []
    @Published var physicalTeamID: String
    /// Equipos de firma detectados en esta Mac (cuentas de Xcode y certificados del llavero).
    @Published var signingTeams: [SigningTeam] = []
    @Published var physicalHost: String
    /// Laya (decisión rápida) está desactivado por defecto; la preferencia se recuerda.
    @Published var layaEnabled: Bool
    @Published var layaURL: String
    @Published var layaStatus: LayaStatus?
    /// Simulador para apps que solo traen código Intel (x86_64).
    @Published var rosetta: RosettaSimulator.Status?

    private let defaults = UserDefaults.standard
    private let projectsKey = "cuyscout.projects.v1"
    private let gatewayKey = "cuyscout.gatewayURL.v1"
    private let runsKey = "cuyscout.runs.v1"
    private let physicalTeamKey = "cuyscout.physicalTeam.v1"
    private let layaEnabledKey = "cuyscout.layaEnabled.v1"
    private let layaURLKey = "cuyscout.layaURL.v1"
    private var gatewayProcess: Process?

    init() {
        let profile = LocalGatewayProfile.load()
        gatewayURL = ProcessInfo.processInfo.environment["CUYSCOUT_GATEWAY_URL"]
            ?? profile?.url
            ?? defaults.string(forKey: gatewayKey)
            ?? "http://127.0.0.1:4723"
        token = ProcessInfo.processInfo.environment["CUYSCOUT_TOKEN"] ?? profile?.token ?? ""
        physicalTeamID = ProcessInfo.processInfo.environment["CUYSCOUT_DEVELOPMENT_TEAM"]
            ?? defaults.string(forKey: physicalTeamKey) ?? ""
        physicalHost = Self.detectLocalIPv4() ?? ""
        layaEnabled = defaults.bool(forKey: layaEnabledKey)
        layaURL = defaults.string(forKey: layaURLKey) ?? LayaService.defaultURL.absoluteString
        if let data = defaults.data(forKey: projectsKey) { projects = (try? JSONDecoder().decode([ScoutProject].self, from: data)) ?? [] }
        if let data = defaults.data(forKey: runsKey) { runs = (try? JSONDecoder().decode([RunRecord].self, from: data)) ?? [] }
        // Sin esto, el gateway que arrancó la app quedaba vivo al cerrarla y la siguiente
        // apertura se conectaba a esa versión vieja en vez de a la recién compilada.
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopOwnedGateway() }
        }
        refreshSigningTeams()
    }

    /// Vuelve a leer los equipos de firma; si no hay uno elegido, o el guardado ya no existe
    /// en esta Mac, toma el preferido (el único, o el último elegido en Xcode).
    func refreshSigningTeams() {
        signingTeams = SigningTeams.detect()
        let current = physicalTeamID.trimmingCharacters(in: .whitespacesAndNewlines)
        let explicit = ProcessInfo.processInfo.environment["CUYSCOUT_DEVELOPMENT_TEAM"]?.isEmpty == false
        if !explicit, current.isEmpty || (!signingTeams.isEmpty && !signingTeams.contains { $0.id == current }) {
            physicalTeamID = SigningTeams.preferred(in: signingTeams)?.id ?? ""
        }
    }

    var client: GatewayClient? {
        guard let url = URL(string: gatewayURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { return nil }
        return GatewayClient(baseURL: url, token: token)
    }

    func setGatewayURL(_ value: String) {
        gatewayURL = value
        defaults.set(value, forKey: gatewayKey)
    }

    /// `.cuyscout-project.json` es la fuente de verdad (lo comparten la app, los scripts y el
    /// agente): si alguien lo cambió fuera de la app (p. ej. `cuyscout init --bundle-id`), la
    /// copia de la app se pone al día. Antes quedaba vieja y el botón Grabar no veía la app
    /// instalada ni la app sabía que el proyecto necesita un iPhone.
    func syncProjectsFromDisk() {
        var changed = false
        for index in projects.indices {
            guard let configured = WorkspaceFiles.installers(in: projects[index].url) else { continue }
            var project = projects[index]
            if !configured.simulator.isEmpty { project.appPath = configured.simulator }
            project.physicalAppPath = configured.physical
            project.physicalBundleID = configured.physicalBundleId ?? ""
            if project != projects[index] {
                ScoutLog.app.info("proyecto", "Configuración del proyecto actualizada desde disco", ["proyecto": project.directory, "bundleIPhone": project.physicalBundleID.isEmpty ? "-" : project.physicalBundleID])
                projects[index] = project
                changed = true
            }
        }
        if changed { saveProjects() }
    }

    func addProject(at url: URL, appPath: String = "") {
        let path = url.standardizedFileURL.path
        guard !projects.contains(where: { $0.directory == path }) else { return }
        let configured = WorkspaceFiles.installers(in: url)
        let installer = appPath.isEmpty ? configured?.simulator ?? WorkspaceFiles.configuredAppPath(in: url) ?? "" : appPath
        projects.append(ScoutProject(name: url.lastPathComponent, directory: path, appPath: installer,
                                     physicalAppPath: configured?.physical ?? "", physicalBundleID: configured?.physicalBundleId ?? ""))
        saveProjects()
    }

    @discardableResult
    func openProject(at selectedURL: URL) throws -> ScoutProject {
        let fm = FileManager.default
        let selected = selectedURL.standardizedFileURL.resolvingSymlinksInPath()
        let root = ["output", "features"].contains(selected.lastPathComponent)
            ? selected.deletingLastPathComponent() : selected
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw AppIssue.message("La carpeta seleccionada no existe o no es un directorio")
        }
        let scripts = root.appendingPathComponent("scripts", isDirectory: true)
        let hasInitScripts = fm.fileExists(atPath: scripts.appendingPathComponent("replay-cuyscout.sh").path)
            || fm.fileExists(atPath: scripts.appendingPathComponent("open-session.sh").path)
        guard hasInitScripts else {
            throw AppIssue.message("Selecciona la carpeta raíz creada con cuyscout_init.sh, no una carpeta cualquiera. Debe contener scripts/replay-cuyscout.sh u open-session.sh.")
        }
        if let existing = projects.first(where: { URL(fileURLWithPath: $0.directory).standardizedFileURL.resolvingSymlinksInPath() == root }) {
            return existing
        }
        let configured = WorkspaceFiles.installers(in: root)
        let project = ScoutProject(name: root.lastPathComponent, directory: root.path,
                                   appPath: configured?.simulator ?? WorkspaceFiles.configuredAppPath(in: root) ?? "",
                                   physicalAppPath: configured?.physical ?? "", physicalBundleID: configured?.physicalBundleId ?? "")
        projects.append(project)
        saveProjects()
        return project
    }

    func updateAppPath(projectID: UUID, path: String, physical: Bool = false) {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
        if physical { projects[index].physicalAppPath = path; projects[index].physicalBundleID = "" }
        else { projects[index].appPath = path }
        saveInstallers(at: index)
    }

    /// Probar en el iPhone la app tal como ya está instalada: sin instalador, sin reinstalar.
    func usePhysicalInstalledApp(projectID: UUID, bundleIdentifier: String) {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[index].physicalBundleID = bundleIdentifier
        projects[index].physicalAppPath = ""
        saveInstallers(at: index)
    }

    private func saveInstallers(at index: Int) {
        let project = projects[index]
        do {
            try WorkspaceFiles.saveInstallers(.init(simulator: project.appPath, physical: project.physicalAppPath,
                                                   physicalBundleId: project.physicalBundleID.isEmpty ? nil : project.physicalBundleID),
                                             in: project.url)
        } catch { notice = "No se pudo compartir el instalador con el agente: \(error.localizedDescription)" }
        saveProjects()
    }

    func installedApps(deviceID: String) async throws -> [InstalledApp] {
        guard let client else { throw AppIssue.message("Gateway no configurado") }
        if !connected { await startGateway() }
        guard let encoded = deviceID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return [] }
        return (try await client.request("devices/\(encoded)/apps") as ValueEnvelope<[InstalledApp]>).value
    }

    func forgetProject(_ id: UUID) {
        projects.removeAll { $0.id == id }
        saveProjects()
    }

    /// Crea el proyecto para un instalador (.app/.ipa) o, sin instalador, para una app ya
    /// instalada en un iPhone (`physicalBundleID`).
    func createProject(name: String, directory: URL, installer: URL?, physicalBundleID: String? = nil,
                       repo: URL? = nil, vscode: Bool = false, useMCP: Bool = false) throws {
        let fm = FileManager.default
        let bundleID = physicalBundleID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let installer {
            guard fm.fileExists(atPath: installer.path) else { throw AppIssue.message("No existe el instalador de la app") }
        } else if bundleID.isEmpty {
            throw AppIssue.message("Elige un instalador o una app ya instalada en el iPhone")
        }
        let appPath = installer?.path ?? ""
        if let repo, !fm.fileExists(atPath: repo.appendingPathComponent("Package.swift").path) {
            throw AppIssue.message("Selecciona el repositorio de CuyScout que contiene Package.swift")
        }
        let options = ProjectScaffolder.Options(appName: name, appPath: appPath,
            cuyscoutRepoPath: repo?.path ?? "", port: client?.baseURL.port ?? 4723, useMCP: useMCP)
        try ProjectUpdater.write(options: options, vscode: vscode, to: directory,
                                 simulatorApp: appPath, physicalBundleID: bundleID)
        addProject(at: directory, appPath: appPath)
    }

    // MARK: - Proyecto desactualizado

    private func keepScriptsKey(_ project: ScoutProject) -> String { "cuyscout.keepScripts.\(project.directory)" }

    /// Los archivos que genera CuyScout son de otra versión y la persona no eligió
    /// mantenerlos para esta versión.
    func projectNeedsUpdate(_ project: ScoutProject) -> Bool {
        ProjectUpdater.needsUpdate(project.url) && defaults.string(forKey: keepScriptsKey(project)) != ProjectUpdater.currentVersion
    }

    /// «Mantener»: no vuelve a preguntar hasta que CuyScout cambie otra vez sus plantillas.
    func keepProjectScripts(_ project: ScoutProject) {
        defaults.set(ProjectUpdater.currentVersion, forKey: keepScriptsKey(project))
        ScoutLog.app.info("proyecto", "Scripts desactualizados mantenidos", ["proyecto": project.directory, "version": ProjectUpdater.currentVersion])
    }

    func updateProjectScripts(_ project: ScoutProject) {
        do {
            let summary = try ProjectUpdater.update(project.url)
            defaults.removeObject(forKey: keepScriptsKey(project))
            notice = "Scripts de \(project.name) actualizados (\(summary.filter { $0.contains("regenerado") }.count) archivos). features/, fixtures/ y rules/ no se tocaron."
        } catch {
            notice = "No se pudieron actualizar los scripts de \(project.name): \(error.localizedDescription)"
        }
    }

    func refresh() async {
        guard let client else { connected = false; notice = "La URL del gateway no es válida"; return }
        do {
            let _: GatewayStatus = try await client.request("status")
            connected = true
            async let fetchedDevices: [Device] = client.request("devices")
            async let fetchedCatalog: [ArtifactDescriptor] = client.request("artifacts/catalog")
            devices = try await fetchedDevices
            activeSessions = (try? await client.request("sessions")) ?? []
            catalog = try await fetchedCatalog
            artifactStatus = try? await client.request("artifacts/status")
            simulatorStorage = (try? await client.request("storage/simulators")) ?? []
            layaStatus = (try? await client.request("decision/laya") as ValueEnvelope<LayaStatus>)?.value
            rosetta = (try? await client.request("devices/rosetta") as ValueEnvelope<RosettaSimulator.Status>)?.value
            // El gateway conectado manda (un agente o la API pudieron cambiarlo); la preferencia
            // guardada solo se aplica al arrancar el gateway desde la app o con el interruptor.
            if let status = layaStatus { layaEnabled = status.enabled; layaURL = status.url }
            notice = nil
        } catch {
            connected = false
            devices = []
            activeSessions = []
            catalog = []
            artifactStatus = nil
            simulatorStorage = []
            notice = error.localizedDescription
        }
    }

    func refreshActiveSessions() async {
        guard connected, let client else { return }
        activeSessions = (try? await client.request("sessions")) ?? []
    }

    func deleteSimulator(_ id: String) async throws {
        guard let client else { throw AppIssue.message("Gateway no configurado") }
        let _: Data = try await client.requestData("devices/\(id)", method: "DELETE")
    }

    func deleteArtifact(_ id: String) async throws {
        guard let client else { throw AppIssue.message("Gateway no configurado") }
        guard let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { throw AppIssue.message("ID de artefacto inválido") }
        let _: Data = try await client.requestData("artifacts/\(encoded)", method: "DELETE")
    }

    /// Al abrir la app: reutiliza un gateway local que ya responda con este token; si no hay
    /// ninguno, arranca el que viene dentro del `.app`. Un gateway remoto nunca se arranca.
    func connectOnLaunch() async {
        syncProjectsFromDisk()
        ScoutLog.app.info("app", "CuyScout.app abierta", ["gateway": gatewayURL, "proyectos": projects.count, "ipMac": physicalHost.isEmpty ? "-" : physicalHost, "equipoFirma": physicalTeamID.isEmpty ? "-" : physicalTeamID])
        await refresh()
        // El perfil puede apuntar a la IP de esta Mac (modo iPhone de una sesión anterior).
        let ownHosts = ["127.0.0.1", "localhost"] + LocalNetwork.ipv4Interfaces().map(\.address)
        guard !connected, let client, let host = client.baseURL.host, ownHosts.contains(host) else {
            ScoutLog.app.info("gateway", connected ? "Conectada a un gateway existente" : "No se arranca un gateway: la URL no es de esta Mac", ["url": gatewayURL])
            return
        }
        // Hay algo escuchando pero rechaza el token (lo arrancó otra sesión o la terminal):
        // no se levanta un segundo gateway en el mismo puerto.
        if (try? await client.request("status") as GatewayStatus) != nil {
            notice = "Hay un gateway en \(client.baseURL.absoluteString) que no acepta el token de la app. Ciérralo o conéctate con su token desde Resumen."
            return
        }
        let (physical, reason) = await physicalModeDecision()
        ScoutLog.app.info("gateway", "Arranque automático del gateway", ["modo": physical ? "iPhone físico" : "local", "motivo": reason])
        await startGateway(physical: physical)
    }

    /// El gateway arranca en modo iPhone (accesible desde la red local) si hay un iPhone
    /// conectado o algún proyecto prueba una app de iPhone, y hay IP y equipo de firma.
    /// Así no hace falta activarlo a mano antes de que un agente abra una sesión.
    func physicalModeDecision() async -> (Bool, String) {
        let projectNeedsIPhone = projects.contains { !$0.physicalBundleID.isEmpty || !$0.physicalAppPath.isEmpty }
        let iPhones = await Task.detached { SimulatorController().physicalDevices().filter(\.isAvailable).map(\.name) }.value
        guard projectNeedsIPhone || !iPhones.isEmpty else { return (false, "sin iPhone conectado ni proyectos de iPhone") }
        let cause = iPhones.isEmpty ? "proyecto con app de iPhone" : "iPhone conectado: \(iPhones.joined(separator: ", "))"
        if physicalHost.isEmpty { physicalHost = LocalNetwork.primaryIPv4() ?? "" }
        guard !physicalHost.isEmpty else { return (false, "\(cause), pero esta Mac no tiene IP de red local") }
        if physicalTeamID.isEmpty { refreshSigningTeams() }
        guard !physicalTeamID.isEmpty else { return (false, "\(cause), pero no hay equipo de Apple para firmar el runner (Xcode → Ajustes → Cuentas)") }
        return (true, cause)
    }

    /// Detiene el gateway solo si lo arrancó esta app; uno externo sigue corriendo.
    func stopOwnedGateway() {
        guard let process = gatewayProcess, process.isRunning else { return }
        process.terminate()
        process.waitUntilExit()
        gatewayProcess = nil
    }

    func startGateway(physical: Bool = false) async {
        guard !isStartingGateway else { return }
        isStartingGateway = true
        defer { isStartingGateway = false }
        let usePhysical = physical
        if connected && !physical { return }
        if connected && physical {
            if await gatewayIsInIPhoneMode() { return }
            guard let process = gatewayProcess, process.isRunning else {
                notice = "Hay un gateway externo activo. Inícialo con configuración física o detén ese proceso antes de usar el arranque automático."
                return
            }
            guard let client, let sessions: [Session] = try? await client.request("sessions"), sessions.isEmpty else {
                notice = "No se puede cambiar el gateway mientras hay sesiones activas o no se pudo comprobar su estado."
                return
            }
            process.terminate()
            for _ in 0..<20 where process.isRunning { try? await Task.sleep(nanoseconds: 100_000_000) }
            guard !process.isRunning else { notice = "El gateway anterior no terminó"; return }
            connected = false
            gatewayProcess = nil
        }
        let address = physicalHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let team = physicalTeamID.trimmingCharacters(in: .whitespacesAndNewlines)
        if usePhysical {
            guard !team.isEmpty else {
                notice = signingTeams.isEmpty
                    ? "Inicia sesión en Xcode (Ajustes → Cuentas) con tu Apple ID para firmar el runner del iPhone; una cuenta gratuita sirve"
                    : "Elige el equipo de Apple que firmará el runner del iPhone"
                return
            }
            guard !address.isEmpty, address != "127.0.0.1", address != "localhost" else {
                notice = "No se encontró una IP local de esta Mac; indica su dirección Wi-Fi"; return
            }
            defaults.set(team, forKey: physicalTeamKey)
        }
        guard let port = await prepareGatewayPort(addresses: ["127.0.0.1", address].filter { !$0.isEmpty }) else { return }
        // La app siempre habla con su gateway por loopback (en modo iPhone también escucha en
        // la IP de red, solo para el runner): así un proxy o firewall corporativo no la corta.
        let deviceGatewayURL = "http://\(address):\(port)"
        if usePhysical || ProcessInfo.processInfo.environment["CUYSCOUT_GATEWAY_URL"] == nil {
            gatewayURL = "http://127.0.0.1:\(port)"
        }
        token = UUID().uuidString.replacingOccurrences(of: "-", with: "") + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        guard let url = client?.baseURL, url.scheme == "http",
              usePhysical || ["127.0.0.1", "localhost"].contains(url.host ?? "") else {
            notice = "El arranque automático solo está disponible para un gateway local"
            return
        }
        let executable = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/cuyscout")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            notice = "El gateway no está incluido. Construye la app con Scripts/build_cuyscout_app.sh"
            return
        }
        do {
            let process = Process()
            process.executableURL = executable
            process.arguments = [String(url.port ?? 4723)]
            process.currentDirectoryURL = Bundle.main.bundleURL
            var environment = ProcessInfo.processInfo.environment
            environment["CUYSCOUT_TOKEN"] = token
            environment["CUYSCOUT_LAYA_ENABLED"] = layaEnabled ? "true" : "false"
            environment["CUYSCOUT_LAYA_URL"] = layaURL
            if usePhysical {
                environment["CUYSCOUT_BIND_ADDRESS"] = address
                environment["CUYSCOUT_DEVICE_GATEWAY_URL"] = deviceGatewayURL
                environment["CUYSCOUT_DEVELOPMENT_TEAM"] = team
            }
            process.environment = environment
            let logURL = FileManager.default.temporaryDirectory.appendingPathComponent("cuyscout-app-gateway.log")
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
            let log = try FileHandle(forWritingTo: logURL)
            process.standardOutput = log
            process.standardError = log
            try process.run()
            gatewayProcess = process
            ScoutLog.app.info("gateway", "Gateway lanzado por la app", ["pid": process.processIdentifier, "modo": usePhysical ? "iPhone físico" : "local", "url": gatewayURL, "urlIPhone": usePhysical ? deviceGatewayURL : "-", "salida": logURL.path])
            for _ in 0..<30 {
                try await Task.sleep(nanoseconds: 500_000_000)
                if !process.isRunning { break }
                if let _: [Session] = try? await client?.request("sessions") {
                    ScoutLog.app.info("gateway", "Gateway listo", ["url": gatewayURL])
                    connected = true
                    try LocalGatewayProfile(url: gatewayURL, token: token).save()
                    await refresh()
                    return
                }
            }
            // No se deja vivo un gateway que no respondió: el siguiente intento lanzaría otro
            // y quedarían procesos huérfanos ocupando puertos.
            if process.isRunning { process.terminate() }
            gatewayProcess = nil
            let output = (try? String(contentsOf: logURL, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            ScoutLog.app.error("gateway", "El gateway no respondió y se cerró", ["url": gatewayURL, "salida": String(output.suffix(400))])
            notice = "El gateway no arrancó. Revisa ~/Library/Logs/CuyScout/gateway.log y \(logURL.path)"
        } catch {
            notice = error.localizedDescription
        }
    }

    private static func detectLocalIPv4() -> String? { LocalNetwork.primaryIPv4() }

    /// Puerto para el gateway que va a arrancar la app. Si el 4723 está ocupado por un gateway
    /// de CuyScout sin sesiones (quedó de antes), se cierra y se reutiliza el puerto; si lo usa
    /// otro programa (p. ej. Appium, que usa 4723 por defecto) o un gateway con sesiones, se
    /// usa el siguiente libre: los scripts y el agente leen la URL del perfil de conexión.
    func prepareGatewayPort(preferred: Int = 4723, addresses: [String]) async -> Int? {
        guard let occupant = PortInspector.listener(on: preferred) else { return preferred }
        // Primero, con timeout corto, si responde; solo entonces se cuentan sesiones: un gateway
        // que acepta la conexión pero no contesta haría esperar el timeout completo.
        let reachable = occupant.isCuyScoutGateway ? await gatewayAnswersStatus(port: preferred, addresses: addresses) : true
        let sessions = occupant.isCuyScoutGateway && reachable ? await openSessionCount(port: preferred, addresses: addresses) : nil
        // Un gateway de CuyScout sin sesiones, o que ni siquiera responde desde esta Mac (quedó
        // de una versión anterior escuchando solo en la IP de red), no le sirve a nadie aquí.
        if occupant.isCuyScoutGateway, sessions == 0 || !reachable {
            ScoutLog.app.info("gateway", "Se cierra un gateway anterior que ocupaba el puerto", ["puerto": preferred, "proceso": occupant.label, "motivo": reachable ? "sin sesiones" : "no responde desde esta Mac"])
            kill(occupant.pid, SIGTERM)
            for _ in 0..<30 where PortInspector.listener(on: preferred) != nil { try? await Task.sleep(nanoseconds: 100_000_000) }
            if PortInspector.listener(on: preferred) == nil { return preferred }
        }
        guard let alternative = PortInspector.firstFreePort(in: (preferred + 1)...(preferred + 20)) else {
            notice = "El puerto \(preferred) lo usa \(occupant.label) y no hay otro puerto libre cerca; ciérralo y vuelve a intentar"
            return nil
        }
        ScoutLog.app.warning("gateway", "Puerto ocupado; se usa otro", ["puerto": preferred, "ocupadoPor": occupant.label, "nuevoPuerto": alternative])
        return alternative
    }

    private func gatewayAnswersStatus(port: Int, addresses: [String]) async -> Bool {
        for address in addresses {
            guard let url = URL(string: "http://\(address):\(port)/status") else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 3
            if let (_, response) = try? await URLSession.direct.data(for: request), (response as? HTTPURLResponse)?.statusCode == 200 { return true }
        }
        return false
    }

    /// El gateway conectado ya acepta iPhones (según su `/status`).
    private func gatewayIsInIPhoneMode() async -> Bool {
        guard let url = client?.baseURL.appendingPathComponent("status"),
              let (data, _) = try? await URLSession.direct.data(from: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let physical = (root["value"] as? [String: Any])?["physical"] as? [String: Any] else { return false }
        return physical["enabled"] as? Bool == true
    }

    /// Sesiones abiertas en un gateway de CuyScout en ese puerto, o nil si no se pudo saber
    /// (token distinto, no responde).
    private func openSessionCount(port: Int, addresses: [String]) async -> Int? {
        let tokens = [token, LocalGatewayProfile.load()?.token ?? ""].filter { !$0.isEmpty } + [""]
        for address in addresses {
            guard let url = URL(string: "http://\(address):\(port)/sessions") else { continue }
            for candidate in tokens {
                var request = URLRequest(url: url)
                request.timeoutInterval = 3
                if !candidate.isEmpty { request.setValue("Bearer \(candidate)", forHTTPHeaderField: "Authorization") }
                if let (data, response) = try? await URLSession.direct.data(for: request), (response as? HTTPURLResponse)?.statusCode == 200,
                   let sessions = try? JSONSerialization.jsonObject(with: data) as? [Any] { return sessions.count }
            }
        }
        return nil
    }

    private func replayInput(project: ScoutProject, scenario: ProjectScenario) throws -> (Data, [String: String], Device.Kind) {
        guard let artifactURL = scenario.artifactURL else { throw AppIssue.message("Este escenario todavía no tiene artefacto CuyScout") }
        let artifact = try Data(contentsOf: artifactURL)
        let bundle = try JSONDecoder().decode(SessionArtifactBundle.self, from: artifact)
        guard bundle.schemaVersion == "cuyscout.session-artifact.v1", bundle.recording?.steps.isEmpty == false else {
            throw AppIssue.message("El artefacto no contiene una prueba grabada")
        }
        let variables: [String: String]
        if let valuesURL = scenario.valuesURL { variables = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: valuesURL)) }
        else {
            variables = [:]
            if artifact.range(of: Data("<redacted>".utf8)) != nil {
                throw AppIssue.message("Falta fixtures/replay-values/\(scenario.name).json; vuelve a grabar el escenario o añade sus valores")
            }
        }
        return (artifact, variables, bundle.session.device.kind)
    }

    func preflightReplay(project: ScoutProject, scenario: ProjectScenario, deviceID: String?, preparation: ReplayPreparationMode) async throws -> ReplayPreflight {
        guard let client else { throw AppIssue.message("Configura una URL válida para el gateway") }
        if !connected { await startGateway() }
        guard connected else { throw AppIssue.message(notice ?? "Gateway desconectado") }
        let (artifact, variables, kind) = try replayInput(project: project, scenario: scenario)
        let imported: ArtifactDescriptor = try await client.request("artifacts/import?overwrite=true", method: "POST", body: artifact)
        let installer = kind == .physical ? project.physicalAppPath : project.appPath
        let body = ReplayRequest(variables: variables, appPath: installer.isEmpty ? nil : installer, deviceID: deviceID, preparation: preparation)
        return try await client.request("artifacts/\(imported.sessionID)/replay/preflight", method: "POST", body: JSONEncoder().encode(body))
    }

    func replay(project: ScoutProject, scenario: ProjectScenario, deviceID: String? = nil, preparation: ReplayPreparationMode = .restart) async {
        guard let client else { notice = "Configura una URL válida para el gateway"; return }
        busyScenario = "\(project.id.uuidString)/\(scenario.name)"
        lastResult = nil
        defer { busyScenario = nil }
        do {
            if !connected { await startGateway() }
            guard connected else { throw AppIssue.message(notice ?? "Gateway desconectado") }
            let (artifact, variables, kind) = try replayInput(project: project, scenario: scenario)
            let imported: ArtifactDescriptor = try await client.request("artifacts/import?overwrite=true", method: "POST", body: artifact)
            let installer = kind == .physical ? project.physicalAppPath : project.appPath
            let body = ReplayRequest(variables: variables, appPath: installer.isEmpty ? nil : installer, deviceID: deviceID, preparation: preparation)
            let response: ReplayResult = try await client.request("artifacts/\(imported.sessionID)/replay", method: "POST", body: JSONEncoder().encode(body))
            let record = RunRecord(projectID: project.id, scenario: scenario.name, result: response)
            runs.insert(record, at: 0)
            if runs.count > 100 { runs.removeLast(runs.count - 100) }
            defaults.set(try JSONEncoder().encode(runs), forKey: runsKey)
            lastResult = record
            if response.success {
                let count = response.dismissedInterruptions ?? 0
                notice = count > 0 ? "Prueba completada; \(count) aviso(s) de guardar contraseña descartado(s)" : "Prueba completada"
            } else {
                notice = "Falló en el paso \(response.failedStep ?? 0): \(response.error ?? "sin detalle")"
            }
            await refresh()
        } catch {
            notice = error.localizedDescription
        }
    }

    /// Guarda la preferencia y, si el gateway está conectado, la aplica en caliente.
    func applyLaya(enabled: Bool, url: String) async {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard LayaService.isValid(trimmed) else { notice = "La URL de Laya debe ser http(s), por ejemplo http://127.0.0.1:8791"; return }
        layaEnabled = enabled
        layaURL = trimmed
        defaults.set(enabled, forKey: layaEnabledKey)
        defaults.set(trimmed, forKey: layaURLKey)
        guard connected, let client else { return }
        do {
            let body = try JSONSerialization.data(withJSONObject: ["enabled": enabled, "url": trimmed])
            layaStatus = (try await client.request("decision/laya", method: "POST", body: body) as ValueEnvelope<LayaStatus>).value
        } catch {
            notice = "No se pudo cambiar Laya en el gateway: \(error.localizedDescription)"
        }
    }

    /// Descarga el runtime universal si falta (~10 GB), crea y arranca «CuyScout Rosetta».
    /// La preparación corre en el gateway; aquí solo se sigue su estado hasta que termina.
    func prepareRosetta() async {
        guard let client else { return }
        do {
            let body = try JSONSerialization.data(withJSONObject: ["download": true])
            rosetta = (try await client.request("devices/rosetta/prepare", method: "POST", body: body) as ValueEnvelope<RosettaSimulator.Status>).value
            while rosetta?.preparing == true {
                try await Task.sleep(nanoseconds: 5_000_000_000)
                rosetta = (try? await client.request("devices/rosetta") as ValueEnvelope<RosettaSimulator.Status>)?.value
            }
            if let error = rosetta?.lastError { notice = error } else { await refresh() }
        } catch {
            notice = "No se pudo preparar el simulador Rosetta: \(error.localizedDescription)"
        }
    }

    private func saveProjects() {
        defaults.set(try? JSONEncoder().encode(projects), forKey: projectsKey)
    }
}

private struct GatewayStatus: Decodable { let ready: Bool }

private struct ValueEnvelope<T: Decodable & Sendable>: Decodable, Sendable { let value: T }

struct LayaStatus: Decodable, Equatable, Sendable {
    let enabled: Bool
    let url: String
    let available: Bool?
    let loaded: [String]?
}

private struct ReplayRequest: Encodable {
    let resetApp = true
    let resilient = false
    let variables: [String: String]
    let appPath: String?
    let deviceID: String?
    let preparation: ReplayPreparationMode
}
