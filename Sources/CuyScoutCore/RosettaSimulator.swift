import Darwin
import Foundation

/// Apps que solo traen código Intel (`x86_64`): en Apple Silicon el simulador normal (`arm64`)
/// se niega a instalarlas («Failed to find matching arch»). Se ejecutan en un simulador
/// arrancado bajo Rosetta, lo que exige un runtime de iOS en variante *universal*.
///
/// CuyScout lo prepara solo: detecta la arquitectura del instalador, crea (una vez) el simulador
/// «CuyScout Rosetta» con un runtime que soporte `x86_64` y lo arranca con `--arch=x86_64`.
/// Descargar el runtime (~10 GB) nunca ocurre sin que alguien lo pida explícitamente.
public final class RosettaSimulator: @unchecked Sendable {
    public static let deviceName = "CuyScout Rosetta"
    public static let shared = RosettaSimulator()

    public enum Architecture { case native, rosettaOnly, unknown }

    public struct Status: Codable, Sendable, Equatable {
        public let rosettaInstalled: Bool
        /// Runtime instalado que soporta `x86_64`, si hay alguno.
        public let runtime: String?
        public let device: Device?
        public let preparing: Bool
        public let stage: String?
        public let lastError: String?
    }

    struct Runtime: Equatable {
        let identifier: String
        let name: String
        let version: String
        let architectures: [String]
        let deviceTypes: [(identifier: String, name: String, family: String)]
        static func == (lhs: Runtime, rhs: Runtime) -> Bool { lhs.identifier == rhs.identifier }
    }

    private let lock = NSLock()
    private var preparing = false
    private var stage: String?
    private var lastError: String?

    // MARK: - Arquitectura del instalador

    /// Arquitecturas del ejecutable de un `.app` (y de su `.debug.dylib`, que en builds de
    /// depuración contiene el código real). Solo las que están en ambos cuentan.
    public static func architectures(ofApp path: String) -> Set<String> {
        let app = URL(fileURLWithPath: path)
        let info = NSDictionary(contentsOf: app.appendingPathComponent("Info.plist"))
        guard let executable = info?["CFBundleExecutable"] as? String else { return [] }
        let binaries = [executable, executable + ".debug.dylib"].map { app.appendingPathComponent($0).path }
            .filter { FileManager.default.fileExists(atPath: $0) }
        let sets = binaries.compactMap { binary -> Set<String>? in
            guard let (status, output, _) = try? SimulatorController.execute("/usr/bin/lipo", ["-archs", binary]), status == 0 else { return nil }
            return Set((String(data: output, encoding: .utf8) ?? "").split(whereSeparator: \.isWhitespace).map(String.init))
        }
        guard let first = sets.first else { return [] }
        return sets.dropFirst().reduce(first) { $0.intersection($1) }
    }

    public static func classify(_ architectures: Set<String>) -> Architecture {
        if architectures.isEmpty { return .unknown }
        // arm64e (y cualquier variante arm64) también corre nativo en Apple Silicon.
        if architectures.contains(where: { $0.hasPrefix("arm64") }) { return .native }
        return architectures.contains("x86_64") ? .rosettaOnly : .unknown
    }

    public static func needsRosetta(appPath: String) -> Bool { classify(architectures(ofApp: appPath)) == .rosettaOnly }

    public static func isRosettaDevice(_ device: Device) -> Bool { device.kind == .simulator && device.name == deviceName }

    public static var isRosettaInstalled: Bool {
        (try? SimulatorController.execute("/usr/bin/arch", ["-x86_64", "/usr/bin/true"]).0) == 0
    }

    // MARK: - Runtimes

    static func runtimes(from data: Data) -> [Runtime] {
        let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        return (root?["runtimes"] as? [[String: Any]] ?? []).compactMap { item in
            guard item["isAvailable"] as? Bool != false, let identifier = item["identifier"] as? String,
                  (item["platform"] as? String ?? "iOS") == "iOS" || identifier.contains(".iOS-") else { return nil }
            let types = (item["supportedDeviceTypes"] as? [[String: Any]] ?? []).compactMap { type -> (String, String, String)? in
                guard let id = type["identifier"] as? String, let name = type["name"] as? String else { return nil }
                return (id, name, type["productFamily"] as? String ?? "")
            }
            return Runtime(identifier: identifier, name: item["name"] as? String ?? identifier, version: item["version"] as? String ?? "",
                           architectures: item["supportedArchitectures"] as? [String] ?? [], deviceTypes: types.map { (identifier: $0.0, name: $0.1, family: $0.2) })
        }
    }

    /// El runtime compatible con `x86_64` más nuevo instalado.
    func rosettaRuntime() -> Runtime? {
        guard let (status, data, _) = try? SimulatorController.execute("/usr/bin/xcrun", ["simctl", "list", "runtimes", "--json"]), status == 0 else { return nil }
        return Self.runtimes(from: data).filter { $0.architectures.contains("x86_64") }
            .max { $0.version.compare($1.version, options: .numeric) == .orderedAscending }
    }

    /// iPhone preferido para el simulador: el Pro más reciente que ofrezca el runtime.
    static func preferredDeviceType(in runtime: Runtime) -> (identifier: String, name: String)? {
        let phones = runtime.deviceTypes.filter { $0.family == "iPhone" || $0.name.hasPrefix("iPhone") }
        let pick = phones.last { $0.name.hasSuffix("Pro") } ?? phones.last
        return pick.map { ($0.identifier, $0.name) }
    }

    // MARK: - Estado y preparación

    public func status(controller: SimulatorController) -> Status {
        lock.lock(); let busy = preparing; let currentStage = stage; let error = lastError; lock.unlock()
        let device = try? controller.devices().first(where: Self.isRosettaDevice)
        return Status(rosettaInstalled: Self.isRosettaInstalled, runtime: rosettaRuntime()?.name, device: device, preparing: busy, stage: currentStage, lastError: error)
    }

    /// Devuelve el simulador «CuyScout Rosetta» arrancado bajo Rosetta, creándolo si falta.
    /// No descarga nada: sin runtime compatible, falla con una instrucción clara.
    public func prepareDevice(controller: SimulatorController) throws -> Device {
        guard Self.isRosettaInstalled else {
            throw ScoutError.invalidRequest("rosetta_not_installed: la app solo trae código Intel (x86_64) y esta Mac no tiene Rosetta. Instálalo con: softwareupdate --install-rosetta --agree-to-license")
        }
        guard let runtime = rosettaRuntime() else {
            throw ScoutError.invalidRequest("rosetta_runtime_missing: la app solo trae código Intel (x86_64) y no hay un runtime de iOS universal instalado. Prepáralo desde CuyScout.app (Almacenamiento › Simulador Rosetta) o con POST /devices/rosetta/prepare {\"download\": true}; descarga ~10 GB una sola vez.")
        }
        var device = try controller.devices().first { Self.isRosettaDevice($0) && $0.runtime == runtime.identifier }
        if device == nil {
            guard let type = Self.preferredDeviceType(in: runtime) else { throw ScoutError.commandFailed("El runtime \(runtime.name) no ofrece modelos de iPhone") }
            let created = try controller.create(name: Self.deviceName, deviceType: type.identifier, runtime: runtime.identifier)
            device = Device(id: created.id, name: Self.deviceName, runtime: runtime.identifier, state: "Shutdown")
        }
        guard var ready = device else { throw ScoutError.commandFailed("No se pudo crear el simulador \(Self.deviceName)") }
        // Arrancado en arm64 (p. ej. desde Simulator.app) no instala apps Intel: se reinicia.
        if ready.state.lowercased() == "booted" && !Self.isBootedUnderRosetta(deviceID: ready.id) {
            try? controller.shutdown(deviceID: ready.id)
            ready = Device(id: ready.id, name: ready.name, runtime: ready.runtime, state: "Shutdown")
        }
        if ready.state.lowercased() != "booted" {
            try controller.boot(deviceID: ready.id, architecture: "x86_64")
            _ = try? SimulatorController.execute("/usr/bin/xcrun", ["simctl", "bootstatus", ready.id])
        }
        return (try controller.devices().first { $0.id == ready.id }) ?? ready
    }

    /// Prepara en segundo plano; con `download` descarga antes el runtime universal si falta.
    @discardableResult
    public func startPreparation(controller: SimulatorController, download: Bool) -> Bool {
        lock.lock()
        guard !preparing else { lock.unlock(); return false }
        preparing = true; lastError = nil; stage = "Comprobando runtime"
        lock.unlock()
        DispatchQueue.global().async {
            do {
                if self.rosettaRuntime() == nil {
                    guard download else { throw ScoutError.invalidRequest("rosetta_runtime_missing: pide la preparación con download=true para descargar el runtime universal (~10 GB)") }
                    try self.downloadUniversalRuntime()
                }
                self.setStage("Creando y arrancando el simulador")
                _ = try self.prepareDevice(controller: controller)
                self.finish(error: nil)
            } catch {
                self.finish(error: error.localizedDescription)
            }
        }
        return true
    }

    /// Apple no publica la variante universal de todas las versiones (p. ej. 26.5 no la tiene):
    /// se prueba de la versión del SDK hacia atrás hasta encontrar una disponible.
    func downloadUniversalRuntime() throws {
        let sdk = (try? SimulatorController.execute("/usr/bin/xcrun", ["--sdk", "iphonesimulator", "--show-sdk-version"]))
            .flatMap { String(data: $0.1, encoding: .utf8) }?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let parts = sdk.split(separator: ".").compactMap { Int($0) }
        guard let major = parts.first else { throw ScoutError.commandFailed("No se pudo leer la versión del SDK de simulador de Xcode") }
        let candidates = stride(from: parts.count > 1 ? parts[1] : 0, through: 0, by: -1).map { "\(major).\($0)" }
        var tried: [String] = []
        for version in candidates {
            setStage("Descargando iOS \(version) universal (~10 GB)")
            let (status, output, errors) = try SimulatorController.execute("/usr/bin/xcodebuild", ["-downloadPlatform", "iOS", "-buildVersion", version, "-architectureVariant", "universal"])
            let text = (String(data: output, encoding: .utf8) ?? "") + (String(data: errors, encoding: .utf8) ?? "")
            if rosettaRuntime() != nil { return }
            tried.append(version)
            if status != 0 && !text.contains("not available") && !text.contains("No needed downloadables") {
                throw ScoutError.commandFailed("Falló la descarga de iOS \(version) universal: \(text.suffix(300))")
            }
        }
        throw ScoutError.commandFailed("Apple no ofrece un runtime de iOS universal para esta versión de Xcode (probadas: \(tried.joined(separator: ", ")))")
    }

    private func setStage(_ value: String) { lock.lock(); stage = value; lock.unlock() }
    private func finish(error: String?) { lock.lock(); preparing = false; stage = nil; lastError = error; lock.unlock() }

    // MARK: - ¿Arrancado bajo Rosetta?

    /// `launchd_sim` es nativo incluso bajo Rosetta; los procesos del simulador (sus hijos:
    /// SpringBoard, backboardd…) son los que corren traducidos cuando arrancó con x86_64.
    static func isBootedUnderRosetta(deviceID: String) -> Bool {
        guard let (status, output, _) = try? SimulatorController.execute("/bin/ps", ["-axo", "pid=,ppid=,command="]), status == 0 else { return false }
        let rows = (String(data: output, encoding: .utf8) ?? "").split(separator: "\n").map { $0.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true) }
        guard let launchd = rows.first(where: { $0.count == 3 && $0[2].contains("launchd_sim") && $0[2].contains(deviceID) }).flatMap({ Int32($0[0]) }) else { return false }
        let children = rows.compactMap { $0.count >= 2 && Int32($0[1]) == launchd ? Int32($0[0]) : nil }
        return children.prefix(5).contains(where: isTranslated)
    }

    static func isTranslated(pid: pid_t) -> Bool {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0 else { return false }
        return info.kp_proc.p_flag & P_TRANSLATED != 0
    }
}
