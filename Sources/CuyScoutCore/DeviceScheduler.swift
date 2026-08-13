import Foundation

public final class DeviceScheduler: @unchecked Sendable {
    private let lock = NSLock()
    private var leases: [String: String] = [:]
    private var ports: [String: Int] = [:]
    private var heartbeats: [String: Date] = [:]
    private let portStart: Int
    private let portCount: Int
    public init(portStart: Int? = nil, portCount: Int? = nil) { self.portStart = max(1024, portStart ?? Int(ProcessInfo.processInfo.environment["CUYSCOUT_PORT_START"] ?? "8200") ?? 8200); self.portCount = max(1, portCount ?? Int(ProcessInfo.processInfo.environment["CUYSCOUT_PORT_COUNT"] ?? "100") ?? 100) }
    private var ttl: TimeInterval { max(30, Double(ProcessInfo.processInfo.environment["CUYSCOUT_LEASE_TTL_SECONDS"] ?? "900") ?? 900) }
    public func acquire(deviceID: String, sessionID: String) -> Bool { lock.lock(); defer { lock.unlock() }; pruneExpiredLocked(); guard leases[deviceID] == nil else { return false }; guard let port = (portStart..<(portStart + portCount)).first(where: { !ports.values.contains($0) }) else { return false }; leases[deviceID] = sessionID; ports[sessionID] = port; heartbeats[sessionID] = Date(); return true }
    public func release(deviceID: String, sessionID: String) { lock.lock(); if leases[deviceID] == sessionID { leases.removeValue(forKey: deviceID); ports.removeValue(forKey: sessionID); heartbeats.removeValue(forKey: sessionID) }; lock.unlock() }
    public func heartbeat(sessionID: String) -> Bool { lock.lock(); defer { lock.unlock() }; pruneExpiredLocked(); guard ports[sessionID] != nil else { return false }; heartbeats[sessionID] = Date(); return true }
    public func isLeased(_ deviceID: String) -> Bool { lock.lock(); defer { lock.unlock() }; pruneExpiredLocked(); return leases[deviceID] != nil }
    public func snapshot() -> [String: String] { lock.lock(); defer { lock.unlock() }; pruneExpiredLocked(); return leases }
    public func leaseSnapshot() -> [SchedulerLease] { lock.lock(); defer { lock.unlock() }; pruneExpiredLocked(); return leases.compactMap { deviceID, sessionID in guard let port = ports[sessionID], let heartbeat = heartbeats[sessionID] else { return nil }; return SchedulerLease(deviceID: deviceID, sessionID: sessionID, port: port, lastHeartbeat: heartbeat, expiresAt: heartbeat.addingTimeInterval(ttl)) }.sorted { $0.deviceID < $1.deviceID } }
    public func port(sessionID: String) -> Int? { lock.lock(); defer { lock.unlock() }; pruneExpiredLocked(); return ports[sessionID] }
    public func portSnapshot() -> [String: Int] { lock.lock(); defer { lock.unlock() }; pruneExpiredLocked(); return ports }
    private func pruneExpiredLocked() { let cutoff = Date().addingTimeInterval(-ttl); let expired = heartbeats.filter { $0.value < cutoff }.map(\.key); for sessionID in expired { if let deviceID = leases.first(where: { $0.value == sessionID })?.key { leases.removeValue(forKey: deviceID) }; ports.removeValue(forKey: sessionID); heartbeats.removeValue(forKey: sessionID) } }
}
