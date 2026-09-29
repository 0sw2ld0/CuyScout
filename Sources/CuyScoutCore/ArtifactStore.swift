import Foundation

public final class ArtifactStore: @unchecked Sendable {
    private let lock = NSLock()
    public let directory: URL
    public let retentionLimit: Int

    public convenience init(directory: URL? = nil) { self.init(directory: directory, retentionLimit: nil) }

    public init(directory: URL?, retentionLimit: Int?) {
        let configured = ProcessInfo.processInfo.environment["CUYSCOUT_ARTIFACT_DIR"].flatMap { URL(fileURLWithPath: $0) }
        // Bajo XCTest el almacén por defecto es temporal: un test que crea `ScoutEngine()` sin
        // almacén explícito llenaba el catálogo real del usuario con sesiones vacías.
        let persistent = Self.isRunningTests
            ? FileManager.default.temporaryDirectory.appendingPathComponent("cuyscout-test-artifacts-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
            : FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("CuyScout/artifacts", isDirectory: true)
        self.directory = directory ?? configured ?? persistent ?? FileManager.default.temporaryDirectory.appendingPathComponent("cuyscout-artifacts", isDirectory: true)
        self.retentionLimit = max(0, retentionLimit ?? Int(ProcessInfo.processInfo.environment["CUYSCOUT_ARTIFACT_RETENTION"] ?? "0") ?? 0)
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    static var isRunningTests: Bool { NSClassFromString("XCTestCase") != nil }

    public func save(_ artifact: SessionArtifactBundle) throws {
        let data = try JSONEncoder().encode(artifact)
        lock.lock(); defer { lock.unlock() }
        try data.write(to: fileURL(for: artifact.session.id), options: .atomic)
        pruneIfNeeded()
    }

    public func load(sessionID: String) throws -> Data {
        lock.lock(); defer { lock.unlock() }
        return try Data(contentsOf: fileURL(for: sessionID))
    }

    public func delete(sessionID: String) throws {
        guard !sessionID.isEmpty, sessionID.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil,
              sessionID != ".", sessionID != ".." else {
            throw ScoutError.invalidRequest("Invalid artifact ID")
        }
        lock.lock(); defer { lock.unlock() }
        let file = fileURL(for: sessionID)
        guard FileManager.default.fileExists(atPath: file.path) else { throw ScoutError.invalidRequest("Artifact not found") }
        try FileManager.default.removeItem(at: file)
    }

    public func list() -> [String] {
        lock.lock(); defer { lock.unlock() }
        return (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))?.filter { $0.pathExtension == "json" }.map { $0.deletingPathExtension().lastPathComponent }.sorted() ?? []
    }
    public func catalog() -> [ArtifactDescriptor] {
        lock.lock(); let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]))?.filter { $0.pathExtension == "json" } ?? []; lock.unlock()
        return files.compactMap { file in
            guard let data = try? Data(contentsOf: file), let artifact = try? JSONDecoder().decode(SessionArtifactBundle.self, from: data) else { return nil }
            let savedAt = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? nil
            return ArtifactDescriptor(sessionID: artifact.session.id, deviceID: artifact.session.device.id, deviceName: artifact.session.device.name, driverID: artifact.session.driverID, bundleIdentifier: artifact.session.bundleIdentifier, eventCount: artifact.events.count, recordedStepCount: artifact.recording?.steps.count ?? artifact.testPlan?.steps.count ?? 0, currentURL: artifact.currentURL, savedAt: savedAt)
        }.sorted { ($0.savedAt ?? .distantPast) > ($1.savedAt ?? .distantPast) }
    }

    public func storageSummary() -> (latestSavedAt: Date?, totalBytes: Int) {
        lock.lock(); defer { lock.unlock() }
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])) ?? []
        var latest: Date?; var total = 0
        for file in files where file.pathExtension == "json" {
            if let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) {
                if let date = values.contentModificationDate, latest == nil || date > latest! { latest = date }
                total += values.fileSize ?? 0
            }
        }
        return (latest, total)
    }

    private func pruneIfNeeded() {
        guard retentionLimit > 0 else { return }
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]))?.filter { $0.pathExtension == "json" } ?? []
        guard files.count > retentionLimit else { return }
        let ordered = files.sorted { lhs, rhs in
            let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? nil
            let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? nil
            return (left ?? .distantPast) < (right ?? .distantPast)
        }
        for file in ordered.prefix(files.count - retentionLimit) { try? FileManager.default.removeItem(at: file) }
    }

    private func fileURL(for sessionID: String) -> URL {
        let safeID = sessionID.replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "_", options: .regularExpression)
        return directory.appendingPathComponent(safeID).appendingPathExtension("json")
    }
}
