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

    static func saveInstallers(_ installers: Installers, in directory: URL) throws {
        let file = directory.appendingPathComponent(".cuyscout-project.json")
        try JSONEncoder().encode(installers).write(to: file, options: .atomic)
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
        let artifactNames = Set(((try? fm.contentsOfDirectory(atPath: output.path)) ?? [])
            .filter { $0.hasSuffix(".cuyscout.json") }
            .map { String($0.dropLast(".cuyscout.json".count)) })
        let featureNames = Set(((try? fm.contentsOfDirectory(atPath: features.path)) ?? [])
            .filter { $0.hasSuffix(".feature") }
            .map { String($0.dropLast(".feature".count)) })

        return artifactNames.union(featureNames).sorted().map { name in
            let artifact = output.appendingPathComponent("\(name).cuyscout.json")
            let feature = features.appendingPathComponent("\(name).feature")
            let validation = output.appendingPathComponent("\(name).validate.json")
            let values = project.url.appendingPathComponent("fixtures/replay-values/\(name).json")
            return ProjectScenario(name: name,
                artifactURL: fm.fileExists(atPath: artifact.path) ? artifact : nil,
                featureURL: fm.fileExists(atPath: feature.path) ? feature : nil,
                validationURL: fm.fileExists(atPath: validation.path) ? validation : nil,
                valuesURL: fm.fileExists(atPath: values.path) ? values : nil)
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
        let (data, response) = try await URLSession.shared.data(for: request)
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
    @Published var notice: String?
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
                       repo: URL? = nil, vscode: Bool = false) throws {
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
            cuyscoutRepoPath: repo?.path ?? "", port: client?.baseURL.port ?? 4723)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        for (relativePath, content) in ProjectScaffolder.files(for: options) {
            let file = directory.appendingPathComponent(relativePath)
            try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: file, atomically: true, encoding: .utf8)
            if ProjectScaffolder.executablePaths.contains(relativePath) {
                try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
            }
        }
        let credentials = directory.appendingPathComponent("fixtures/credentials.test.json")
        if !fm.fileExists(atPath: credentials.path) {
            try ProjectScaffolder.credentialsFixture().write(to: credentials, atomically: true, encoding: .utf8)
        }
        try fm.createDirectory(at: directory.appendingPathComponent("output"), withIntermediateDirectories: true)
        try fm.createDirectory(at: directory.appendingPathComponent("features"), withIntermediateDirectories: true)
        let agents = directory.appendingPathComponent("AGENTS.md")
        let existing = try? String(contentsOf: agents, encoding: .utf8)
        try ProjectScaffolder.mergedAgentsMarkdown(existingContent: existing, options: options)
            .write(to: agents, atomically: true, encoding: .utf8)
        if vscode { try VSCodeScaffolder.apply(to: directory) }
        try WorkspaceFiles.saveInstallers(.init(simulator: appPath, physical: "",
                                                physicalBundleId: bundleID.isEmpty ? nil : bundleID), in: directory)
        addProject(at: directory, appPath: appPath)
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

    func startGateway(physical: Bool = false) async {
        guard !isStartingGateway else { return }
        isStartingGateway = true
        defer { isStartingGateway = false }
        let usePhysical = physical
        if connected && !physical { return }
        if connected && physical {
            if let host = client?.baseURL.host, !["127.0.0.1", "localhost"].contains(host), !token.isEmpty { return }
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
            gatewayURL = "http://\(address):4723"
        } else if ProcessInfo.processInfo.environment["CUYSCOUT_GATEWAY_URL"] == nil {
            gatewayURL = "http://127.0.0.1:4723"
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
                environment["CUYSCOUT_DEVICE_GATEWAY_URL"] = gatewayURL
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
            for _ in 0..<30 {
                try await Task.sleep(nanoseconds: 500_000_000)
                if !process.isRunning { break }
                if let _: [Session] = try? await client?.request("sessions") {
                    connected = true
                    try LocalGatewayProfile(url: gatewayURL, token: token).save()
                    await refresh()
                    return
                }
            }
            notice = "El gateway no arrancó. Revisa \(logURL.path)"
        } catch {
            notice = error.localizedDescription
        }
    }

    private static func detectLocalIPv4() -> String? {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else { return nil }
        defer { freeifaddrs(first) }
        var candidates: [(String, String)] = []
        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let item = current {
            let value = item.pointee
            if let address = value.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
               value.ifa_flags & UInt32(IFF_UP) != 0 {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    let ip = String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
                    if !ip.hasPrefix("127.") && !ip.hasPrefix("169.254.") {
                        candidates.append((String(cString: value.ifa_name), ip))
                    }
                }
            }
            current = value.ifa_next
        }
        return candidates.sorted { lhs, rhs in
            func rank(_ name: String) -> Int { name == "en0" ? 0 : name == "en1" ? 1 : 2 }
            return rank(lhs.0) < rank(rhs.0)
        }.first?.1
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
