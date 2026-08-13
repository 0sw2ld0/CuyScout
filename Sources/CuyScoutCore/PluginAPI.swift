import Foundation

public struct PluginDescriptor: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let version: String
    public let capabilities: [String]
    public let signature: String?
    public init(id: String, name: String, version: String = "0.1.0", capabilities: [String] = [], signature: String? = nil) { self.id = id; self.name = name; self.version = version; self.capabilities = capabilities; self.signature = signature }
}

public struct PluginRouteHandlerResult: Codable, Sendable, Equatable {
    public let status: Int
    public let body: Data
    public let contentType: String
    public init(status: Int = 200, body: Data, contentType: String = "application/json") { self.status = status; self.body = body; self.contentType = contentType }
}

public protocol CuyScoutPlugin: AnyObject, Sendable {
    var descriptor: PluginDescriptor { get }
    func before(_ action: ScoutAction, sessionID: String) throws -> ScoutAction
    func after(_ action: ScoutAction, result: Data?, error: Error?, sessionID: String)
    func transformResult(_ action: ScoutAction, result: Data?, sessionID: String) -> Data?
    func routes() -> [PluginRoute]
    func handleRoute(method: String, path: String, body: String, sessionID: String?) throws -> PluginRouteHandlerResult
}

public extension CuyScoutPlugin {
    func transformResult(_ action: ScoutAction, result: Data?, sessionID: String) -> Data? { result }
    func routes() -> [PluginRoute] { [] }
    func handleRoute(method: String, path: String, body: String, sessionID: String?) throws -> PluginRouteHandlerResult { PluginRouteHandlerResult(status: 404, body: Data("{}".utf8)) }
}

public final class PluginRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var plugins: [String: any CuyScoutPlugin] = [:]
    private var allowlist: Set<String>?
    private var securityPolicy = PluginSecurityPolicy()
    public init() {}
    public func setAllowlist(_ ids: [String]) { lock.lock(); allowlist = Set(ids); lock.unlock() }
    public func setSecurityPolicy(_ policy: PluginSecurityPolicy) { lock.lock(); securityPolicy = policy; lock.unlock() }
    public func register(_ plugin: any CuyScoutPlugin) {
        lock.lock()
        if let allowlist, !allowlist.contains(plugin.descriptor.id) { lock.unlock(); return }
        if securityPolicy.requireSignature, plugin.descriptor.signature == nil { lock.unlock(); return }
        if !securityPolicy.allowedCapabilities.isEmpty { let caps = Set(plugin.descriptor.capabilities); if !caps.isSubset(of: Set(securityPolicy.allowedCapabilities)) { lock.unlock(); return } }
        plugins[plugin.descriptor.id] = plugin; lock.unlock()
    }
    public func unregister(id: String) { lock.lock(); plugins.removeValue(forKey: id); lock.unlock() }
    public func descriptors() -> [PluginDescriptor] { lock.lock(); defer { lock.unlock() }; return plugins.values.map(\.descriptor).sorted { $0.id < $1.id } }
    func transform(_ action: ScoutAction, sessionID: String) throws -> ScoutAction { lock.lock(); let current = Array(plugins.values); lock.unlock(); return try current.reduce(action) { try $1.before($0, sessionID: sessionID) } }
    func notify(_ action: ScoutAction, result: Data?, error: Error?, sessionID: String) { lock.lock(); let current = Array(plugins.values); lock.unlock(); current.forEach { $0.after(action, result: result, error: error, sessionID: sessionID) } }
    func transformResult(_ action: ScoutAction, result: Data?, sessionID: String) -> Data? { lock.lock(); let current = Array(plugins.values); lock.unlock(); return current.reduce(result) { $1.transformResult(action, result: $0, sessionID: sessionID) } }
    public func allRoutes() -> [PluginRoute] { lock.lock(); defer { lock.unlock() }; return plugins.values.flatMap { $0.routes() } }
    public func handlePluginRoute(method: String, path: String, body: String, sessionID: String?) throws -> PluginRouteHandlerResult? {
        lock.lock(); let current = Array(plugins.values); lock.unlock()
        for plugin in current { let routes = plugin.routes(); if routes.contains(where: { $0.method == method && $0.path == path }) { return try plugin.handleRoute(method: method, path: path, body: body, sessionID: sessionID) } }
        return nil
    }
}
