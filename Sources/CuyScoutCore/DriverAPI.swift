import Foundation

public struct DriverDescriptor: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let version: String
    public let platforms: [String]
    public let supportedCapabilities: [String]
    public let supportedSettings: [String]
    public init(id: String, name: String, version: String = "0.1.0", platforms: [String], supportedCapabilities: [String] = [], supportedSettings: [String] = []) { self.id = id; self.name = name; self.version = version; self.platforms = platforms; self.supportedCapabilities = supportedCapabilities; self.supportedSettings = supportedSettings }
}

public struct DriverHealth: Codable, Sendable, Equatable {
    public let healthy: Bool
    public let message: String
    public let checkedAt: Date
    public init(healthy: Bool, message: String, checkedAt: Date = Date()) { self.healthy = healthy; self.message = message; self.checkedAt = checkedAt }
}

public protocol CuyScoutDriver: AnyObject, Sendable {
    var descriptor: DriverDescriptor { get }
    func health() -> DriverHealth
    func execute(_ action: ScoutAction, on device: Device) throws -> Data?
}

public final class DriverRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var drivers: [String: any CuyScoutDriver] = [:]
    private var driverManifests: [String: DriverManifest] = [:]
    public init() {}
    public func register(_ driver: any CuyScoutDriver) { lock.lock(); drivers[driver.descriptor.id] = driver; lock.unlock() }
    public func unregister(id: String) { lock.lock(); drivers.removeValue(forKey: id); driverManifests.removeValue(forKey: id); lock.unlock() }
    public func descriptors() -> [DriverDescriptor] { lock.lock(); defer { lock.unlock() }; return drivers.values.map(\.descriptor).sorted { $0.id < $1.id } }
    public func health() -> [String: DriverHealth] { lock.lock(); let current = drivers; lock.unlock(); return current.mapValues { $0.health() } }
    public func driver(id: String) -> (any CuyScoutDriver)? { lock.lock(); defer { lock.unlock() }; return drivers[id] }
    public func registerManifest(_ manifest: DriverManifest) { lock.lock(); driverManifests[manifest.id] = manifest; lock.unlock() }
    public func manifests() -> [DriverManifest] { lock.lock(); defer { lock.unlock() }; return Array(driverManifests.values).sorted { $0.id < $1.id } }
    public func loadDriverFromManifest(_ manifest: DriverManifest) -> DriverLoadResult {
        let bundleURL = URL(fileURLWithPath: manifest.libraryPath)
        guard FileManager.default.fileExists(atPath: manifest.libraryPath) else { return DriverLoadResult(loaded: false, driverID: manifest.id, error: "Library not found: \(manifest.libraryPath)") }
        if let bundle = Bundle(url: bundleURL) {
            bundle.load()
            lock.lock(); driverManifests[manifest.id] = manifest; lock.unlock()
            return DriverLoadResult(loaded: true, driverID: manifest.id)
        }
        return DriverLoadResult(loaded: false, driverID: manifest.id, error: "Could not load bundle: \(manifest.libraryPath)")
    }
}

public final class SimulatorDriverAdapter: CuyScoutDriver, @unchecked Sendable {
    public let descriptor = DriverDescriptor(id: "ios-simulator", name: "CuyScout iOS Simulator Driver", platforms: ["iOS"], supportedCapabilities: ["appium:udid", "appium:deviceName", "appium:platformVersion", "appium:bundleId", "appium:driverId", "appium:noReset", "appium:automationName", "platformName"], supportedSettings: ["screenshotWaitTimeout", "mjpegServerScreenshotQuality", "mjpegServerFramerate"])
    private let controller: SimulatorController
    public init(controller: SimulatorController = SimulatorController()) { self.controller = controller }
    public func health() -> DriverHealth { let report = controller.doctor(); return DriverHealth(healthy: report.ready, message: report.ready ? "simctl listo" : report.recommendations.joined(separator: "; ")) }
    public func execute(_ action: ScoutAction, on device: Device) throws -> Data? { try controller.execute(action, on: device) }
}
