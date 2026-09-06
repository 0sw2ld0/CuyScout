import Foundation
import CoreGraphics
import ImageIO
import Vision

public final class ScoutEngine: @unchecked Sendable {
    private let controller: SimulatorController
    private let driverRegistry: DriverRegistry
    private let pluginRegistry: PluginRegistry
    private let scheduler: DeviceScheduler
    private let artifactStore: ArtifactStore
    private let lessonStore: LessonStore
    private var securityPolicies: [String: SecurityPolicy] = [:]
    private var events: [String: [ScoutEvent]] = [:]
    private var eventSequence = 0
    private var commandCounts: [String: Int] = [:]
    private var auditEntries: [String: [SecurityAuditEntry]] = [:]
    private var repairEntries: [String: [RepairAuditEntry]] = [:]
    private var accessibilityAudits: [String: AccessibilityAudit] = [:]
    private var auditSequence = 0
    private var repairSequence = 0
    private var sessions: [String: Session] = [:]
    private var bridges: [String: BridgeState] = [:]
    private var runnerProcesses: [String: Process] = [:]
    /// URL base del gateway que el runner XCTest usa para registrarse y recibir comandos.
    public var gatewayBaseURL = ProcessInfo.processInfo.environment["CUYSCOUT_URL"] ?? "http://127.0.0.1:4799"
    private var webViews: [String: WebViewState] = [:]
    private var accessibilitySnapshots: [String: [String: String]] = [:]
    private var recordings: [String: RecordingState] = [:]
    private var completedRecordings: [String: RecordedSession] = [:]
    private var explorations: [String: ExplorationState] = [:]
    private var elementReferences: [String: [String: ScoutSelector]] = [:]
    private var timeouts: [String: [String: Double]] = [:]
    private var currentURLs: [String: String] = [:]
    private var settings: [String: [String: Any]] = [:]
    private var orientations: [String: DeviceOrientation] = [:]
    private var observationStates: [String: String] = [:]
    private var navigationGraphs: [String: NavigationGraphState] = [:]
    private var checkpoints: [String: [ExplorationCheckpoint]] = [:]
    private var batchResults: [String: [String: BatchExecutionResult]] = [:]
    private var lastBatchResults: [String: BatchExecutionResult] = [:]
    private var cancelledBatches: [String: Set<String>] = [:]
    private var visualBaselines: [String: Data] = [:]
    private var sessionQueue: [QueueEntry] = []
    private var consoleLogs: [String: [ConsoleLogEntry]] = [:]
    private var consoleLogSequence = 0
    private var reactiveRules: [String: [ReactiveRule]] = [:]
    private var appCache: [String: AppCacheEntry] = [:]
    private var farmWorkers: [String: FarmWorker] = [:]
    private var semanticFingerprints: [String: [String: SemanticFingerprint]] = [:]
    private var networkRequests: [String: [NetworkRequestEntry]] = [:]
    private var networkRequestSequence = 0
    private var shardConfigs: [String: ShardConfig] = [:]
    private var otelSpans: [String: [OtelSpan]] = [:]
    private var appearanceStates: [String: String] = [:]
    private var contentSizeStates: [String: String] = [:]
    private let lock = NSLock()

    public init(controller: SimulatorController = SimulatorController(), artifactStore: ArtifactStore = ArtifactStore(), lessonStore: LessonStore = LessonStore()) { self.controller = controller; self.driverRegistry = DriverRegistry(); self.driverRegistry.register(SimulatorDriverAdapter(controller: controller)); self.pluginRegistry = PluginRegistry(); self.scheduler = DeviceScheduler(); self.artifactStore = artifactStore; self.lessonStore = lessonStore }
    public func drivers() -> [DriverDescriptor] { driverRegistry.descriptors() }
    public func driverHealth() -> [String: DriverHealth] { driverRegistry.health() }
    public func registerDriver(_ driver: any CuyScoutDriver) { driverRegistry.register(driver) }
    public func unregisterDriver(id: String) { driverRegistry.unregister(id: id) }
    public func plugins() -> [PluginDescriptor] { pluginRegistry.descriptors() }
    public func registerPlugin(_ plugin: any CuyScoutPlugin) { pluginRegistry.register(plugin) }
    public func unregisterPlugin(id: String) { pluginRegistry.unregister(id: id) }
    public func schedulerStatus() -> [String: String] { scheduler.snapshot() }
    public func schedulerLeases() -> [SchedulerLease] { scheduler.leaseSnapshot() }
    public func heartbeat(sessionID: String) throws -> SchedulerLease { try requireSession(sessionID); guard scheduler.heartbeat(sessionID: sessionID), let lease = scheduler.leaseSnapshot().first(where: { $0.sessionID == sessionID }) else { throw ScoutError.invalidRequest("session_lease_expired") }; return lease }
    public func schedulerPortStatus() -> [String: Int] { scheduler.portSnapshot() }
    public func events(sessionID: String, after: Int = 0, kind: String? = nil) throws -> [ScoutEvent] { try requireSession(sessionID); lock.lock(); let raw = (events[sessionID] ?? []).filter { $0.id > after && (kind == nil || $0.kind == kind) }; lock.unlock(); guard shouldRedactSensitiveData() else { return raw }; return raw.map { ScoutEvent(id: $0.id, timestamp: $0.timestamp, kind: $0.kind, action: $0.action.redactedSensitiveData(), success: $0.success, durationMilliseconds: $0.durationMilliseconds, error: $0.error) } }
    public func waitForEvents(sessionID: String, after: Int = 0, timeoutSeconds: Double = 10, kind: String? = nil) throws -> [ScoutEvent] {
        let deadline = Date().addingTimeInterval(min(max(0, timeoutSeconds), 30))
        repeat {
            let result = try events(sessionID: sessionID, after: after, kind: kind)
            if !result.isEmpty || Date() >= deadline { return result }
            Thread.sleep(forTimeInterval: 0.05)
        } while true
    }
    public func metrics(sessionID: String) throws -> SessionMetrics {
        try requireSession(sessionID)
        lock.lock(); let values = events[sessionID] ?? []; lock.unlock()
        let total = values.count
        let successful = values.filter(\.success).count
        let failed = total - successful
        let durations = values.map(\.durationMilliseconds).sorted()
        let average = total == 0 ? 0 : Double(durations.reduce(0, +)) / Double(total)
        let p95Index = durations.isEmpty ? 0 : min(durations.count - 1, Int(ceil(Double(durations.count) * 0.95)) - 1)
        var counts: [String: Int] = [:]
        for event in values { counts[actionName(event.action), default: 0] += 1 }
        return SessionMetrics(totalCommands: total, successfulCommands: successful, failedCommands: failed, failureRate: total == 0 ? 0 : Double(failed) / Double(total), averageDurationMilliseconds: average, p95DurationMilliseconds: durations.isEmpty ? 0 : durations[p95Index], commandCounts: counts)
    }
    public func fleetMetrics() -> FleetMetrics {
        lock.lock(); let allEvents = events.values.flatMap { $0 }; let active = sessions.count; lock.unlock()
        let total = allEvents.count; let failed = allEvents.filter { !$0.success }.count; let average = total == 0 ? 0 : Double(allEvents.reduce(0) { $0 + $1.durationMilliseconds }) / Double(total)
        return FleetMetrics(activeSessions: active, retainedEvents: total, failedCommands: failed, failureRate: total == 0 ? 0 : Double(failed) / Double(total), averageDurationMilliseconds: average)
    }
    public func fleetMetricsPrometheus() -> String {
        let metrics = fleetMetrics()
        return "# HELP cuyscout_active_sessions Active CuyScout sessions\n# TYPE cuyscout_active_sessions gauge\ncuyscout_active_sessions \(metrics.activeSessions)\n# HELP cuyscout_retained_events Retained command events\n# TYPE cuyscout_retained_events gauge\ncuyscout_retained_events \(metrics.retainedEvents)\n# HELP cuyscout_failed_commands Failed commands\n# TYPE cuyscout_failed_commands counter\ncuyscout_failed_commands \(metrics.failedCommands)\n# HELP cuyscout_failure_rate Command failure rate\n# TYPE cuyscout_failure_rate gauge\ncuyscout_failure_rate \(metrics.failureRate)\n# HELP cuyscout_average_duration_ms Average command duration in milliseconds\n# TYPE cuyscout_average_duration_ms gauge\ncuyscout_average_duration_ms \(metrics.averageDurationMilliseconds)\n"
    }
    public func conformanceSnapshot() -> ConformanceSnapshot { ConformanceSnapshot(protocolName: "W3C WebDriver / Appium", protocolVersion: "2024-11", implemented: ["sessions", "capabilities", "findElement", "findElements", "findElementFromElement", "findElementsFromElement", "actions", "source", "timeouts", "pageLoad", "windowRect", "elementSelected", "elementName", "elementProperty", "activeElement", "scroll", "cookies", "alertText", "submit", "permissions", "biometry", "geolocation", "visualDiff", "timeline", "sessionQueue", "fleetDashboard", "appCache", "consoleLogs", "reactiveRules", "semanticFingerprints", "behaviorComparison", "pluginRoutes", "pluginSignature", "driverManifests", "networkCapture", "sharding", "openTelemetry", "appearance", "statusBar", "videoRecording", "listApps", "keychain", "deepLink", "pushNotification", "contentSize", "addMedia", "spawnProcess", "icloudSync", "elementLocation", "elementSize", "shake", "getAppearance", "getContentSize", "enumerateFiles", "doubleTap", "longPress", "pinch", "deviceLifecycle", "pbsync", "fileTransfer", "appContainer", "simulatorConfig", "testVerification", "failureClassification", "accessibilityOverlay", "visualRegionCompare", "pluginSecurityPolicy", "semanticCycleDetection", "ocr", "runnerBuild", "events", "batch", "artifacts", "security-policy", "websocketBiDi", "farmWorkers", "MCP"], partial: ["XCUITest bridge", "WEBVIEW", "element screenshot", "alerts", "clipboard", "distributed device farm execution"], pendingIntegrations: ["official Appium client suite", "WebKit Inspector real"], automatedTests: 28) }
    public func sessionArtifactBundle(sessionID: String) throws -> SessionArtifactBundle {
        let session = try self.session(sessionID)
        let eventValues = try events(sessionID: sessionID)
        let checkpointValues = try listCheckpoints(sessionID: sessionID)
        let plan = try? testPlan(sessionID: sessionID)
        lock.lock(); let completed = completedRecordings[sessionID]; let totalCommands = commandCounts[sessionID] ?? eventValues.count; let policy = securityPolicies[sessionID] ?? SecurityPolicy(); let audit = auditEntries[sessionID] ?? []; let repairs = repairEntries[sessionID] ?? []; let accessibility = accessibilityAudits[sessionID]; lock.unlock(); let artifact = SessionArtifactBundle(session: session, events: eventValues, metrics: try metrics(sessionID: sessionID), checkpoints: checkpointValues, testPlan: plan, recording: (try? recording(sessionID: sessionID)) ?? completed, currentURL: try currentURL(sessionID: sessionID), navigation: try navigationGraph(sessionID: sessionID), redactSensitiveData: shouldRedactSensitiveData(), totalCommandCount: totalCommands, securityPolicy: policy, auditEntries: audit, repairEntries: repairs, accessibilityAudit: accessibility); try artifactStore.save(artifact); return artifact
    }
    public func persistedArtifacts() -> [String] { artifactStore.list() }
    public func artifactCatalog() -> [ArtifactDescriptor] { artifactStore.catalog() }
    public func artifactStoreStatus() -> ArtifactStoreStatus { let interval = max(0, Int(ProcessInfo.processInfo.environment["CUYSCOUT_AUTOSAVE_INTERVAL"] ?? "10") ?? 10); let summary = artifactStore.storageSummary(); return ArtifactStoreStatus(available: FileManager.default.isWritableFile(atPath: artifactStore.directory.path), persistedCount: artifactStore.list().count, autosaveInterval: interval, totalBytes: summary.totalBytes, latestSavedAt: summary.latestSavedAt, artifactRetention: artifactStore.retentionLimit) }
    public func restorePersistedArtifact(sessionID: String) throws -> Session { try restoreSessionArtifact(artifactStore.load(sessionID: sessionID)) }
    public func preflightRestore(_ data: Data) -> ArtifactRestorePreflight {
        guard let artifact = try? JSONDecoder().decode(SessionArtifactBundle.self, from: data) else { return ArtifactRestorePreflight(valid: false, errors: ["artifact_json_invalid"]) }
        var errors: [String] = []; var warnings: [String] = []
        if artifact.schemaVersion != "cuyscout.session-artifact.v1" { errors.append("unsupported_schema") }
        if driverRegistry.driver(id: artifact.session.driverID) == nil { errors.append("driver_not_registered") }
        if (try? listDevices().first(where: { $0.id == artifact.session.device.id && $0.isAvailable })) == nil { errors.append("device_unavailable") }
        if scheduler.isLeased(artifact.session.device.id) { errors.append("device_already_leased") }
        lock.lock(); let duplicate = sessions[artifact.session.id] != nil; lock.unlock(); if duplicate { errors.append("session_id_already_exists") }
        if artifact.recording == nil && artifact.events.isEmpty { warnings.append("artifact_has_no_recording_or_events") }
        return ArtifactRestorePreflight(valid: errors.isEmpty, sessionID: artifact.session.id, deviceID: artifact.session.device.id, driverID: artifact.session.driverID, errors: errors, warnings: warnings)
    }
    public func restoreSessionArtifact(_ data: Data) throws -> Session {
        let preflight = preflightRestore(data); guard preflight.valid else { throw ScoutError.invalidRequest("Artifact restore preflight failed: \(preflight.errors.joined(separator: ","))") }
        let artifact = try JSONDecoder().decode(SessionArtifactBundle.self, from: data)
        guard artifact.schemaVersion == "cuyscout.session-artifact.v1" else { throw ScoutError.invalidRequest("Unsupported session artifact schema") }
        let available = try listDevices().first { $0.id == artifact.session.device.id }
        guard let device = available, device.isAvailable else { throw ScoutError.invalidRequest("The artifact device is not available") }
        guard let artifactDriver = driverRegistry.driver(id: artifact.session.driverID) else { throw ScoutError.invalidRequest("The artifact driver is not registered: \(artifact.session.driverID)") }
        guard artifactDriver.descriptor.platforms.contains(where: { $0.caseInsensitiveCompare("iOS") == .orderedSame || $0.caseInsensitiveCompare("any") == .orderedSame }) else { throw ScoutError.invalidRequest("The artifact driver does not support iOS") }
        guard !scheduler.isLeased(device.id) else { throw ScoutError.invalidRequest("The artifact device is already leased") }
        lock.lock(); defer { lock.unlock() }
        guard sessions[artifact.session.id] == nil else { throw ScoutError.invalidRequest("A session with this artifact ID already exists") }
        guard scheduler.acquire(deviceID: device.id, sessionID: artifact.session.id) else { throw ScoutError.invalidRequest("The artifact device could not be leased") }
        let session = Session(id: artifact.session.id, device: device, bundleIdentifier: artifact.session.bundleIdentifier, createdAt: artifact.session.createdAt, driverID: artifact.session.driverID, automationPort: scheduler.port(sessionID: artifact.session.id))
        sessions[session.id] = session
        events[session.id] = artifact.events
        commandCounts[session.id] = artifact.totalCommandCount ?? artifact.events.count
        if let entries = artifact.auditEntries { auditEntries[session.id] = entries; auditSequence = max(auditSequence, entries.map(\.id).max() ?? 0) }
        if let entries = artifact.repairEntries { repairEntries[session.id] = entries; repairSequence = max(repairSequence, entries.map(\.id).max() ?? 0) }
        if let accessibility = artifact.accessibilityAudit { accessibilityAudits[session.id] = accessibility }
        if let policy = artifact.securityPolicy { securityPolicies[session.id] = policy }
        eventSequence = max(eventSequence, artifact.events.map(\.id).max() ?? 0)
        checkpoints[session.id] = artifact.checkpoints
        if let url = artifact.currentURL { currentURLs[session.id] = url }
        if let navigation = artifact.navigation { let graph = NavigationGraphState(); graph.restore(navigation); navigationGraphs[session.id] = graph }
        if let recording = artifact.recording {
            let state = RecordingState(startedAt: recording.startedAt)
            recording.steps.forEach { state.append($0) }
            recordings[session.id] = state
            completedRecordings[session.id] = recording
        }
        return session
    }
    public func securityPolicy(sessionID: String) throws -> SecurityPolicy { try requireSession(sessionID); lock.lock(); let policy = securityPolicies[sessionID] ?? SecurityPolicy(); lock.unlock(); return policy }
    public func setSecurityPolicy(sessionID: String, policy: SecurityPolicy) throws { try requireSession(sessionID); lock.lock(); securityPolicies[sessionID] = policy; lock.unlock() }
    public func doctor() -> DoctorReport { controller.doctor() }
    public func listDevices() throws -> [Device] { try controller.devices() }
    public func installApp(sessionID: String, path: String) throws { let session = try self.session(sessionID); if let cached = cachedApp(bundleIdentifier: session.bundleIdentifier ?? path), FileManager.default.fileExists(atPath: cached.path) { try controller.installApp(cached.path, on: session.device) } else { try controller.installApp(path, on: session.device) } }
    public func uninstallApp(sessionID: String, bundleIdentifier: String) throws { let session = try self.session(sessionID); try controller.uninstallApp(bundleIdentifier, on: session.device) }
    public func resetApp(sessionID: String, bundleIdentifier: String) throws { let session = try self.session(sessionID); try controller.resetApp(bundleIdentifier, on: session.device) }
    public func activateApp(sessionID: String, bundleIdentifier: String? = nil) throws { let session = try self.session(sessionID); guard let bundle = bundleIdentifier ?? session.bundleIdentifier else { throw ScoutError.invalidRequest("No bundle identifier configured for this session") }; _ = try perform(.launch(bundleIdentifier: bundle), sessionID: sessionID) }
    public func terminateApp(sessionID: String, bundleIdentifier: String? = nil) throws { let session = try self.session(sessionID); guard let bundle = bundleIdentifier ?? session.bundleIdentifier else { throw ScoutError.invalidRequest("No bundle identifier configured for this session") }; _ = try perform(.terminate(bundleIdentifier: bundle), sessionID: sessionID) }
    public func backgroundApp(sessionID: String, duration: Double = 0) throws { _ = try perform(.backgroundApp(duration: max(0, duration)), sessionID: sessionID) }
    public func session(_ id: String) throws -> Session { lock.lock(); defer { lock.unlock() }; guard let session = sessions[id] else { throw ScoutError.sessionNotFound }; return session }
    public func recordLesson(scope: LessonScope, sessionID: String? = nil, title: String, observation: String, recommendation: String, evidence: String? = nil, tags: [String] = [], confidence: Double = 0.8) throws -> LearnedLesson { let session = try sessionID.map { try self.session($0) }; guard scope == .global || session != nil else { throw ScoutError.invalidRequest("project/session lessons require sessionId") }; let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines); let cleanObservation = observation.trimmingCharacters(in: .whitespacesAndNewlines); let cleanRecommendation = recommendation.trimmingCharacters(in: .whitespacesAndNewlines); guard !cleanTitle.isEmpty, cleanTitle.count <= 120, !cleanObservation.isEmpty, cleanObservation.count <= 1_000, !cleanRecommendation.isEmpty, cleanRecommendation.count <= 1_000 else { throw ScoutError.invalidRequest("lesson text is empty or exceeds title=120/observation=1000/recommendation=1000 characters") }; guard tags.count <= 10, tags.allSatisfy({ !$0.isEmpty && $0.count <= 40 }), (evidence?.count ?? 0) <= 1_000 else { throw ScoutError.invalidRequest("lesson exceeds evidence=1000, tags=10 or tagLength=40 limits") }; let projectKey = scope == .project ? session?.bundleIdentifier : nil; return try lessonStore.record(LearnedLesson(scope: scope, projectKey: projectKey, sessionID: scope == .session ? sessionID : nil, title: cleanTitle, observation: cleanObservation, recommendation: cleanRecommendation, evidence: evidence, tags: tags, confidence: confidence)) }
    public func allLessons(query: String? = nil, tags: [String] = [], scope: LessonScope? = nil, limit: Int = 50) -> [LearnedLesson] { Array(lessonStore.search(query: query, tags: tags, scope: scope).prefix(min(max(0, limit), 200))) }
    public func lessons(sessionID: String, query: String? = nil, tags: [String] = [], limit: Int = 10) throws -> [LearnedLesson] { let session = try self.session(sessionID); let project = session.bundleIdentifier; return Array(lessonStore.search(query: query, tags: tags).filter { $0.scope == .global || ($0.scope == .project && $0.projectKey == project) || ($0.scope == .session && $0.sessionID == sessionID) }.prefix(min(max(0, limit), 50))) }
    public func contextualLessons(sessionID: String, limit: Int = 5) throws -> [LearnedLesson] {
        let recent = try events(sessionID: sessionID, after: 0).suffix(10)
        var tags = Set<String>()
        if recent.contains(where: { isTypingAction($0.action) }) { tags.formUnion(["keyboard", "form", "scroll"]) }
        if recent.contains(where: { !$0.success && (($0.error ?? "").lowercased().contains("element") || ($0.error ?? "").lowercased().contains("selector")) }) { tags.insert("selector") }
        if recent.contains(where: { !$0.success && $0.durationMilliseconds >= 2_000 }) { tags.formUnion(["timing", "wait", "stability"]) }
        lock.lock(); let exploration = explorations[sessionID]?.report(); lock.unlock()
        if exploration?.status == .loopDetected { tags.formUnion(["exploration", "loop", "checkpoint"]) }
        let candidates = try lessons(sessionID: sessionID, limit: 50)
        return Array(candidates.sorted { lhs, rhs in
            let left = LessonRelevance.score(lhs, contextTags: tags); let right = LessonRelevance.score(rhs, contextTags: tags)
            if left != right { return left > right }
            return lhs.updatedAt > rhs.updatedAt
        }.prefix(min(max(0, limit), 20)))
    }
    public func learnFromSession(sessionID: String, scope: LessonScope = .project, persist: Bool = true) throws -> LessonLearningReport { try learnFromSession(sessionID: sessionID, scope: scope, persist: persist, exploration: nil) }
    private func learnFromSession(sessionID: String, scope: LessonScope, persist: Bool, exploration: ExplorationReport?) throws -> LessonLearningReport { let session = try self.session(sessionID); guard scope != .global else { throw ScoutError.invalidRequest("automatic learning may only persist project or session lessons") }; guard scope != .project || session.bundleIdentifier != nil else { throw ScoutError.invalidRequest("project learning requires a bundle identifier") }; let recording = try self.recording(sessionID: sessionID); let candidates = LessonInference.infer(steps: recording.steps, exploration: exploration, scope: scope, projectKey: session.bundleIdentifier, sessionID: sessionID); let saved = persist ? try candidates.map { try lessonStore.record($0) } : []; return LessonLearningReport(candidates: candidates, persisted: saved) }
    public func sessionCapabilities(sessionID: String) throws -> [String: Any] { let session = try self.session(sessionID); var capabilities: [String: Any] = ["platformName": "iOS", "automationName": "XCUITest", "appium:automationName": "XCUITest", "appium:driverId": session.driverID, "appium:udid": session.device.id, "appium:deviceName": session.device.name, "appium:platformVersion": session.device.runtime]; if let bundle = session.bundleIdentifier { capabilities["appium:bundleId"] = bundle }; if let port = session.automationPort { capabilities["cuyscout:automationPort"] = port }; return capabilities }
    public func deviceInfo(sessionID: String) throws -> [String: Any] { let session = try self.session(sessionID); var info: [String: Any] = ["udid": session.device.id, "name": session.device.name, "deviceName": session.device.name, "runtime": session.device.runtime, "platformVersion": session.device.runtime, "state": session.device.state, "available": session.device.isAvailable, "platformName": "iOS", "automationName": "XCUITest", "manufacturer": "Apple", "driverId": session.driverID, "automationPort": session.automationPort as Any]; if let bundle = session.bundleIdentifier { info["bundleIdentifier"] = bundle }; return info }
    public func deviceTime(sessionID: String) throws -> String { let session = try self.session(sessionID); if let result = try? controller.execute(.spawnProcess(bundleIdentifier: "/bin/date", args: []), on: session.device), let time = String(data: result, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !time.isEmpty { return time }; return ISO8601DateFormatter().string(from: Date()) }
    public func createSession(deviceID: String?, bundleIdentifier: String?, deviceName: String? = nil, runtime: String? = nil, driverID: String = "ios-simulator", waitSeconds: Double = 0) throws -> Session {
        guard let selectedDriver = driverRegistry.driver(id: driverID) else { throw ScoutError.invalidRequest("Driver is not registered: \(driverID)") }
        let sessionID = UUID().uuidString
        let deadline = Date().addingTimeInterval(min(max(0, waitSeconds), 60)); var device: Device?
        repeat {
            if let candidate = try listDevices().first(where: { (deviceID == nil || $0.id == deviceID) && (deviceName == nil || $0.name == deviceName) && (runtime == nil || $0.runtime.contains(runtime!)) && $0.isAvailable && !scheduler.isLeased($0.id) }), scheduler.acquire(deviceID: candidate.id, sessionID: sessionID) { device = candidate; break }
            if Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
        } while Date() < deadline
        guard let device else { throw ScoutError.invalidRequest("No se encontró un simulador disponible") }
        guard selectedDriver.descriptor.platforms.contains(where: { $0.caseInsensitiveCompare("iOS") == .orderedSame || $0.caseInsensitiveCompare("any") == .orderedSame }) else { scheduler.release(deviceID: device.id, sessionID: sessionID); throw ScoutError.invalidRequest("Driver \(driverID) no soporta la plataforma iOS") }
        let session = Session(id: sessionID, device: device, bundleIdentifier: bundleIdentifier, createdAt: Date(), driverID: driverID, automationPort: scheduler.port(sessionID: sessionID))
        lock.lock(); sessions[session.id] = session; lock.unlock(); return session
    }
    public func deleteSession(_ id: String) throws { terminateRunner(sessionID: id); lock.lock(); defer { lock.unlock() }; guard let session = sessions.removeValue(forKey: id) else { throw ScoutError.sessionNotFound }; scheduler.release(deviceID: session.device.id, sessionID: id); events.removeValue(forKey: id); commandCounts.removeValue(forKey: id); securityPolicies.removeValue(forKey: id); auditEntries.removeValue(forKey: id); repairEntries.removeValue(forKey: id); accessibilityAudits.removeValue(forKey: id); bridges.removeValue(forKey: id); webViews.removeValue(forKey: id); observationStates.removeValue(forKey: id); navigationGraphs.removeValue(forKey: id); checkpoints.removeValue(forKey: id); batchResults.removeValue(forKey: id); lastBatchResults.removeValue(forKey: id); cancelledBatches.removeValue(forKey: id); accessibilitySnapshots.removeValue(forKey: id); recordings.removeValue(forKey: id); completedRecordings.removeValue(forKey: id); explorations.removeValue(forKey: id); elementReferences.removeValue(forKey: id); timeouts.removeValue(forKey: id); currentURLs.removeValue(forKey: id); settings.removeValue(forKey: id); orientations.removeValue(forKey: id); visualBaselines.removeValue(forKey: id); consoleLogs.removeValue(forKey: id); reactiveRules.removeValue(forKey: id); semanticFingerprints.removeValue(forKey: id); networkRequests.removeValue(forKey: id); shardConfigs.removeValue(forKey: id); otelSpans.removeValue(forKey: id); appearanceStates.removeValue(forKey: id); contentSizeStates.removeValue(forKey: id) }
    public func perform(_ action: ScoutAction, sessionID: String) throws -> Data? {
        try requireSession(sessionID)
        guard scheduler.heartbeat(sessionID: sessionID) else { throw ScoutError.invalidRequest("session_lease_expired") }
        let action = try pluginRegistry.transform(action, sessionID: sessionID)
        do { try enforcePolicy(action, sessionID: sessionID); try enforceCommandBudget(sessionID: sessionID); recordAudit(action: action, sessionID: sessionID, allowed: true, reason: nil) }
        catch { recordAudit(action: action, sessionID: sessionID, allowed: false, reason: error.localizedDescription); throw error }
        let started = Date()
        do {
            try explorationBefore(action, sessionID: sessionID)
            let rawResult = try performUnrecorded(action, sessionID: sessionID)
            let result = pluginRegistry.transformResult(action, result: rawResult, sessionID: sessionID)
            explorationAfter(action, result, sessionID: sessionID)
            record(action, sessionID: sessionID, startedAt: started, success: true, error: nil)
            pluginRegistry.notify(action, result: result, error: nil, sessionID: sessionID)
            publishEvent(sessionID: sessionID, action: action, success: true, startedAt: started, error: nil)
            return result
        } catch {
            record(action, sessionID: sessionID, startedAt: started, success: false, error: error.localizedDescription)
            pluginRegistry.notify(action, result: nil, error: error, sessionID: sessionID)
            publishEvent(sessionID: sessionID, action: action, success: false, startedAt: started, error: error.localizedDescription)
            throw error
        }
    }
    public func performWithSelectorRepair(_ action: ScoutAction, sessionID: String) throws -> Data? {
        if case .sequence(let actions) = action {
            var result: Data?
            for step in actions { result = try performWithSelectorRepair(step, sessionID: sessionID) }
            return result
        }
        do { return try perform(action, sessionID: sessionID) }
        catch ScoutError.noSuchElement, ScoutError.staleElementReference {
            guard let selector = selector(in: action) else { throw ScoutError.noSuchElement("No se pudo reparar la acción sin selector") }
            let repairs = try repairSelector(sessionID: sessionID, selector: selector, limit: 5).filter { $0.score >= 0.6 }
            guard let best = repairs.first else { throw ScoutError.noSuchElement("No se encontró una alternativa confiable para: \(selector.value)") }
            let repaired = replacingSelector(in: action, with: best.selector)
            recordRepair(sessionID: sessionID, proposal: ActionRepairProposal(original: action, proposed: repaired, score: best.score, reason: best.reason, requiresApproval: false), decision: .applied)
            return try perform(repaired, sessionID: sessionID)
        }
    }
    public func executeBatch(_ actions: [ScoutAction], sessionID: String, resilient: Bool = false, stopOnError: Bool = true, includeResults: Bool = false, requestID: String? = nil, timeoutSeconds: Double = 120, retryInfrastructure: Bool = false, maxRetries: Int = 1) throws -> BatchExecutionResult {
        try requireSession(sessionID)
        let validation = try validateBatch(actions, sessionID: sessionID)
        guard validation.valid else { throw ScoutError.invalidRequest(validation.errors.joined(separator: " ")) }
        let deadline = Date().addingTimeInterval(min(max(0, timeoutSeconds), 120))
        if let requestID, !requestID.isEmpty { lock.lock(); let cached = batchResults[sessionID]?[requestID]; lock.unlock(); if let cached { return cached } }
        var results: [BatchStepResult] = []
        for (index, action) in actions.enumerated() {
            if let requestID, !requestID.isEmpty { lock.lock(); let cancelled = cancelledBatches[sessionID]?.contains(requestID) == true; lock.unlock(); if cancelled { results.append(BatchStepResult(index: index, success: false, durationMilliseconds: 0, error: "batch_cancelled", category: "cancelled")); break } }
            if Date() >= deadline { results.append(BatchStepResult(index: index, success: false, durationMilliseconds: 0, error: "batch_timeout", category: "infrastructure")); break }
            let started = Date()
            var retries = 0
            while true {
                do {
                    let data = try resilient ? performWithSelectorRepair(action, sessionID: sessionID) : perform(action, sessionID: sessionID)
                    results.append(BatchStepResult(index: index, success: true, durationMilliseconds: Int(Date().timeIntervalSince(started) * 1000), resultBase64: includeResults ? data?.base64EncodedString() : nil)); break
                } catch {
                    let category = failureCategory(error)
                    if retryInfrastructure && category == "infrastructure" && retries < min(max(0, maxRetries), 3) && Date() < deadline { retries += 1; continue }
                    results.append(BatchStepResult(index: index, success: false, durationMilliseconds: Int(Date().timeIntervalSince(started) * 1000), error: error.localizedDescription, category: category)); if stopOnError { break }; break
                }
            }
            if results.last?.success == false && stopOnError { break }
        }
        let result = BatchExecutionResult(success: results.count == actions.count && results.allSatisfy(\.success), executed: results.count, total: actions.count, steps: results)
        lock.lock(); lastBatchResults[sessionID] = result; if let requestID, !requestID.isEmpty { var cache = batchResults[sessionID] ?? [:]; cache[requestID] = result; if cache.count > 100 { cache.removeValue(forKey: cache.keys.sorted().first ?? requestID) }; batchResults[sessionID] = cache; cancelledBatches[sessionID]?.remove(requestID) }; lock.unlock()
        return result
    }
    public func batchSummary(sessionID: String, requestID: String? = nil) throws -> BatchCompactSummary {
        try requireSession(sessionID)
        lock.lock(); let result = requestID.flatMap { batchResults[sessionID]?[$0] } ?? lastBatchResults[sessionID]; lock.unlock()
        guard let result else { throw ScoutError.invalidRequest("No existe un resultado batch para esta sesión") }
        let failed = result.steps.filter { !$0.success }
        let categories = Dictionary(grouping: failed, by: { $0.category ?? "unknown" }).mapValues(\.count)
        let retryable = failed.filter { $0.category == "infrastructure" }.count
        let hint: String? = result.success ? "continue_to_next_action" : (retryable > 0 ? "retry_infrastructure_only" : (categories["selector"] ?? 0 > 0 ? "repair_selector_before_retry" : "inspect_product_failure"))
        return BatchCompactSummary(requestID: requestID, success: result.success, executed: result.executed, total: result.total, failedSteps: failed.map(\.index), failureCategories: categories, retryableFailureCount: retryable, nextActionHint: hint)
    }
    private func failureCategory(_ error: Error) -> String { if let scoutError = error as? ScoutError { switch scoutError { case .noSuchElement, .staleElementReference: return "selector"; case .commandFailed(let message) where message.lowercased().contains("timeout") || message.lowercased().contains("bridge") || message.lowercased().contains("device"): return "infrastructure"; case .invalidRequest, .unsupported: return "environment"; default: return "product" } }; return "environment" }
    public func cancelBatch(sessionID: String, requestID: String) throws { try requireSession(sessionID); guard !requestID.isEmpty else { throw ScoutError.invalidRequest("requestID is required to cancel a batch") }; lock.lock(); if batchResults[sessionID]?[requestID] == nil { cancelledBatches[sessionID, default: []].insert(requestID) }; lock.unlock() }
    public func validateBatch(_ actions: [ScoutAction], sessionID: String) throws -> BatchValidation {
        try requireSession(sessionID)
        var errors: [String] = []; var warnings: [String] = []
        if actions.isEmpty { errors.append("El batch debe contener al menos una acción.") }
        if actions.count > 100 { errors.append("El batch no puede contener más de 100 acciones.") }
        func inspect(_ action: ScoutAction, path: String) {
            switch action {
            case .sequence(let nested):
                if nested.isEmpty { errors.append("\(path): la secuencia está vacía.") }
                nested.enumerated().forEach { inspect($0.element, path: "\(path).actions[\($0.offset)]") }
            case .typeElement(_, let text), .type(let text), .setClipboard(let text):
                if text == "<text>" || text == "<redacted>" { warnings.append("\(path): contiene un placeholder de dato sensible.") }
            case .assertText(_, let expected):
                if expected == "<text>" || expected == "<redacted>" { warnings.append("\(path): la assertion contiene un placeholder.") }
            default: break
            }
        }
        actions.enumerated().forEach { inspect($0.element, path: "actions[\($0.offset)]") }
        return BatchValidation(valid: errors.isEmpty, actionCount: actions.count, errors: errors, warnings: warnings)
    }

    private func performUnrecorded(_ action: ScoutAction, sessionID: String) throws -> Data? {
        lock.lock(); let session = sessions[sessionID]; lock.unlock(); guard let session else { throw ScoutError.sessionNotFound }
        if case .navigateBack = action, try currentContext(sessionID: sessionID) != "NATIVE_APP" { _ = try executeWebViewScript(sessionID: sessionID, script: "history.back(); true", argumentsJSON: "[]"); try waitForPageLoad(sessionID: sessionID); return nil }
        if case .navigateForward = action, try currentContext(sessionID: sessionID) != "NATIVE_APP" { _ = try executeWebViewScript(sessionID: sessionID, script: "history.forward(); true", argumentsJSON: "[]"); try waitForPageLoad(sessionID: sessionID); return nil }
        if case .refresh = action, try currentContext(sessionID: sessionID) != "NATIVE_APP" { _ = try executeWebViewScript(sessionID: sessionID, script: "location.reload(); true", argumentsJSON: "[]"); try waitForPageLoad(sessionID: sessionID); return nil }
        if case .openURL = action, try currentContext(sessionID: sessionID) != "NATIVE_APP" { if case .openURL(let url) = action { _ = try executeWebViewScript(sessionID: sessionID, script: "location.href = arguments[0]; true", argumentsJSON: jsonArguments([url])); try waitForPageLoad(sessionID: sessionID) }; return nil }
        if case .scroll(let x, let y) = action { if try currentContext(sessionID: sessionID) != "NATIVE_APP" { _ = try executeWebViewScript(sessionID: sessionID, script: "window.scrollBy(arguments[0], arguments[1]); true", argumentsJSON: jsonArguments([x, y])); return nil }; return try performThroughBridge(action, sessionID: sessionID) }
        if case .visualDiff(let tolerance) = action { return try JSONEncoder().encode(try visualDiff(sessionID: sessionID, tolerance: tolerance)) }
        switch action {
        case .tap, .swipe, .type, .accessibilityTree, .accessibilityTreeWithOptions, .accessibilityDiff, .clearElement, .elementAttribute, .elementDisplayed, .elementEnabled, .elementRect, .elementScreenshot, .elementSelected, .elementName, .elementProperty, .submit, .doubleTap, .longPress, .pinch, .findElement, .findElements, .findElementFromElement, .findElementsFromElement, .tapElement, .typeElement, .waitFor, .assertVisible, .assertText:
            if case .accessibilityDiff(let options) = action {
                let current = try performThroughBridge(.accessibilityTreeWithOptions(options), sessionID: sessionID) ?? Data()
                return accessibilityDiff(current, sessionID: sessionID)
            }
            return try performThroughBridge(action, sessionID: sessionID)
        default:
            return try executeThroughDriver(action, on: session.device, driverID: session.driverID)
        }
    }

    public func registerBridge(sessionID: String) throws { try requireSession(sessionID); lock.lock(); bridges[sessionID] = BridgeState(); lock.unlock() }
    public func pollBridge(sessionID: String) throws -> BridgeCommand? { try requireSession(sessionID); lock.lock(); let bridge = bridges[sessionID]; lock.unlock(); return bridge?.poll() }
    public func completeBridge(sessionID: String, result: BridgeResult) throws { try requireSession(sessionID); lock.lock(); let bridge = bridges[sessionID]; lock.unlock(); bridge?.complete(result) }
    public func bridgeStatus(sessionID: String) throws -> BridgeStatus { try requireSession(sessionID); lock.lock(); let bridge = bridges[sessionID]; lock.unlock(); return bridge?.status() ?? BridgeStatus(registered: false, pendingCommands: 0, lastActivity: nil, runnerAttached: false) }

    /// Instala un instalador (.app de simulador) en el dispositivo y resuelve su bundle ID,
    /// sin necesidad del código fuente de la app. Dispositivo: `deviceID` explícito o el
    /// primer simulador booted.
    public func prepareInstaller(appPath: String, deviceID: String?, bundleIdentifier explicit: String?) throws -> InstallerInfo {
        // `appium:app` acepta el entregable tal cual: un `.app` de simulador o un `.ipa`,
        // del que se extrae el `Payload/*.app`. El agente solo necesita el instalador.
        let expanded = try controller.resolveInstaller(at: appPath)
        let bundle = try explicit ?? controller.bundleIdentifier(ofAppAt: expanded)
        let devices = try controller.devices()
        guard let device = deviceID.flatMap({ wanted in devices.first { $0.id == wanted } }) ?? devices.first(where: { $0.state.lowercased() == "booted" }) else { throw ScoutError.invalidRequest("No hay un simulador booted disponible para instalar la app") }
        controller.enableSoftwareKeyboard(on: device)
        try controller.installApp(expanded, on: device)
        return InstallerInfo(bundleIdentifier: bundle, deviceID: device.id, appPath: expanded)
    }

    /// Lanza el runner genérico prebuilt contra la sesión, para que registre el puente XCTest
    /// por su cuenta. El proceso vive hasta el DELETE de la sesión (terminateRunner).
    public func launchRunner(sessionID: String) throws {
        try requireSession(sessionID)
        let session = try self.session(sessionID)
        guard let xctestrun = runnerXCTestRunPath() else { throw ScoutError.unsupported("Runner prebuilt no encontrado: ejecuta Scripts/build_scout_runner.sh o define CUYSCOUT_RUNNER_XCTESTRUN") }
        lock.lock(); let existing = runnerProcesses[sessionID]; lock.unlock()
        guard existing == nil else { return }
        try registerBridge(sessionID: sessionID)
        // La app se termina antes de arrancar el runner: `XCUIApplication.launch()` espera a
        // que la app quede en reposo, y una app ya abierta en una pantalla con animación
        // continua nunca llega a ese punto. El runner se queda colgado y muere por timeout,
        // dejando la sesión sin puente. Arrancar siempre desde un proceso limpio lo evita.
        if let bundle = session.bundleIdentifier { _ = try? controller.execute(.terminate(bundleIdentifier: bundle), on: session.device) }
        try? FileManager.default.removeItem(atPath: "/tmp/cuyscout-bridge-stop")
        // Config por sesión: un runner arrancando tarde no debe leer la config de otra sesión.
        let configPath = "/tmp/cuyscout-bridge-\(sessionID).json"
        var runnerConfig: [String: Any] = ["url": gatewayBaseURL, "sessionId": sessionID, "maxSeconds": 600]
        if let bundle = session.bundleIdentifier { runnerConfig["bundleId"] = bundle }
        try? JSONSerialization.data(withJSONObject: runnerConfig).write(to: URL(fileURLWithPath: configPath))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
        process.arguments = ["test-without-building", "-xctestrun", xctestrun, "-destination", "platform=iOS Simulator,id=\(session.device.id)", "-derivedDataPath", runnerDerivedDataPath()]
        var environment = ProcessInfo.processInfo.environment
        environment["TEST_RUNNER_CUYSCOUT_URL"] = gatewayBaseURL
        environment["TEST_RUNNER_CUYSCOUT_SESSION_ID"] = sessionID
        environment["TEST_RUNNER_CUYSCOUT_BUNDLE_ID"] = session.bundleIdentifier ?? ""
        environment["TEST_RUNNER_CUYSCOUT_CONFIG_FILE"] = configPath
        process.environment = environment
        // La salida de xcodebuild va a un log por sesión: un Pipe sin lector se llena
        // (64 KB) y bloquea xcodebuild a mitad de sesión. El log además permite diagnosticar.
        let logPath = "/tmp/cuyscout-runner-\(sessionID).log"
        FileManager.default.createFile(atPath: logPath, contents: nil)
        if let handle = FileHandle(forWritingAtPath: logPath) { process.standardOutput = handle; process.standardError = handle }
        try process.run()
        lock.lock(); runnerProcesses[sessionID] = process; lock.unlock()
    }

    /// Termina el runner XCTest asociado a la sesión (invocado por deleteSession).
    private func terminateRunner(sessionID: String) {
        lock.lock(); let process = runnerProcesses.removeValue(forKey: sessionID); lock.unlock()
        if let process, process.isRunning { process.terminate() }
        try? FileManager.default.removeItem(atPath: "/tmp/cuyscout-bridge-\(sessionID).json")
    }

    /// Derived data del runner prebuilt: CUYSCOUT_RUNNER_DIR, o `.build/scout-runner-dd`
    /// relativo al directorio actual o al ejecutable del gateway.
    private func runnerDerivedDataPath() -> String {
        if let dir = ProcessInfo.processInfo.environment["CUYSCOUT_RUNNER_DIR"] { return dir }
        let current = FileManager.default.currentDirectoryPath + "/.build/scout-runner-dd"
        if FileManager.default.fileExists(atPath: current + "/Build/Products") { return current }
        let executable = URL(fileURLWithPath: CommandLine.arguments.first ?? "/").deletingLastPathComponent()
        return executable.deletingLastPathComponent().appendingPathComponent("scout-runner-dd").path
    }

    /// Ruta del .xctestrun prebuilt: CUYSCOUT_RUNNER_XCTESTRUN explícito o el primero
    /// encontrado en el derived data del runner.
    public func runnerXCTestRunPath() -> String? {
        if let explicit = ProcessInfo.processInfo.environment["CUYSCOUT_RUNNER_XCTESTRUN"], FileManager.default.fileExists(atPath: explicit) { return explicit }
        let products = URL(fileURLWithPath: runnerDerivedDataPath()).appendingPathComponent("Build/Products")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: products.path)) ?? []
        return names.filter { $0.hasSuffix(".xctestrun") }.sorted().first.map { products.appendingPathComponent($0).path }
    }
    public func alertSnapshot(sessionID: String) throws -> AlertSnapshot {
        try requireSession(sessionID)
        let data = try performThroughBridge(.accessibilityTreeWithOptions(AccessibilityOptions(visibleOnly: true, interactiveOnly: false, maxElements: 500)), sessionID: sessionID) ?? Data()
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let elements = object?["elements"] as? [[String: Any]] ?? []
        let alerts = elements.filter { String(describing: $0["type"] ?? "").lowercased().contains("alert") }
        guard let alert = alerts.first else { throw ScoutError.invalidRequest("No hay una alerta visible") }
        let text = [alert["label"] as? String, alert["value"] as? String].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " ")
        let buttons = elements.filter { String(describing: $0["type"] ?? "").lowercased().contains("button") }.compactMap { $0["label"] as? String }.filter { !$0.isEmpty }
        return AlertSnapshot(text: text, buttons: Array(Set(buttons)).sorted())
    }

    /// Registra contextos publicados por un adaptador WebKit externo.
    public func registerWebView(sessionID: String, contexts: [String]) throws {
        try requireSession(sessionID)
        let valid = contexts.filter { $0.hasPrefix("WEBVIEW") }
        guard !valid.isEmpty else { throw ScoutError.invalidRequest("At least one WEBVIEW context is required") }
        lock.lock(); let state = webViews[sessionID] ?? WebViewState(); state.register(contexts: valid); webViews[sessionID] = state; lock.unlock()
    }

    public func webViewContexts(sessionID: String) throws -> [String] {
        try requireSession(sessionID); lock.lock(); let state = webViews[sessionID]; lock.unlock(); return ["NATIVE_APP"] + (state?.contexts() ?? [])
    }

    public func currentContext(sessionID: String) throws -> String {
        try requireSession(sessionID); lock.lock(); let state = webViews[sessionID]; lock.unlock(); return state?.currentContext() ?? "NATIVE_APP"
    }

    public func webViewStatus(sessionID: String) throws -> WebViewStatus {
        try requireSession(sessionID); lock.lock(); let state = webViews[sessionID]; lock.unlock()
        return WebViewStatus(connected: state != nil, contexts: state?.contexts() ?? [], currentContext: state?.currentContext() ?? "NATIVE_APP")
    }

    public func setContext(sessionID: String, context: String) throws {
        try requireSession(sessionID); guard context == "NATIVE_APP" || context.hasPrefix("WEBVIEW") else { throw ScoutError.unsupported("Context is not available: \(context)") }
        lock.lock(); let state = webViews[sessionID] ?? WebViewState(); webViews[sessionID] = state; lock.unlock(); try state.setContext(context)
    }

    public func executeWebViewScript(sessionID: String, script: String, argumentsJSON: String) throws -> String? {
        try requireSession(sessionID); lock.lock(); let state = webViews[sessionID]; let timeout = timeouts[sessionID]?["script"] ?? 30000; lock.unlock(); guard let state, state.currentContext() != "NATIVE_APP" else { throw ScoutError.unsupported("Select a WEBVIEW context before executing JavaScript") }
        return try state.execute(WebViewCommand(context: state.currentContext(), script: script, argumentsJSON: argumentsJSON), timeout: max(0, timeout / 1000))
    }
    public func pollWebView(sessionID: String) throws -> WebViewCommand? { try requireSession(sessionID); lock.lock(); let state = webViews[sessionID]; lock.unlock(); return state?.poll() }
    public func completeWebView(sessionID: String, result: WebViewResult) throws { try requireSession(sessionID); lock.lock(); let state = webViews[sessionID]; lock.unlock(); state?.complete(result) }

    public func startRecording(sessionID: String) throws { try requireSession(sessionID); lock.lock(); recordings[sessionID] = RecordingState(startedAt: Date()); lock.unlock() }
    public func stopRecording(sessionID: String) throws -> RecordedSession { try requireSession(sessionID); lock.lock(); let state = recordings[sessionID]; recordings[sessionID] = nil; lock.unlock(); guard let state else { throw ScoutError.invalidRequest("La grabación no está activa") }; let result = state.snapshot(sessionID: sessionID, stoppedAt: Date()); lock.lock(); completedRecordings[sessionID] = result; lock.unlock(); _ = try? sessionArtifactBundle(sessionID: sessionID); return result }
    public func recording(sessionID: String) throws -> RecordedSession { try requireSession(sessionID); lock.lock(); let state = recordings[sessionID]; let completed = completedRecordings[sessionID]; lock.unlock(); if let state { return state.snapshot(sessionID: sessionID, stoppedAt: nil) }; if let completed { return completed }; throw ScoutError.invalidRequest("No existe una grabación para esta sesión") }
    public func redactedRecording(sessionID: String) throws -> RecordedSession { let source = try recording(sessionID: sessionID); guard shouldRedactSensitiveData() else { return source }; return RecordedSession(sessionID: source.sessionID, startedAt: source.startedAt, stoppedAt: source.stoppedAt, steps: source.steps.map { RecordedStep(index: $0.index, action: $0.action.redactedSensitiveData(), startedAt: $0.startedAt, durationMilliseconds: $0.durationMilliseconds, success: $0.success, error: $0.error) }) }
    public func testPlan(sessionID: String) throws -> TestPlan {
        let recording = try recording(sessionID: sessionID)
        let steps = recording.steps.map { TestPlanStep(id: "step-\($0.index + 1)", action: $0.action, success: $0.success, durationMilliseconds: $0.durationMilliseconds) }
        var warnings: [String] = []
        if steps.contains(where: { if case .tap = $0.action { return true }; if case .swipe = $0.action { return true }; return false }) { warnings.append("El plan contiene coordenadas; prefiere selectores semánticos cuando sea posible.") }
        if steps.contains(where: { !$0.success }) { warnings.append("El plan contiene pasos fallidos y requiere revisión antes de exportarse.") }
        return TestPlan(sessionID: sessionID, steps: steps, warnings: warnings)
    }
    public func optimizedTestPlan(sessionID: String) throws -> TestPlan {
        TestPlanOptimizer.optimize(try testPlan(sessionID: sessionID))
    }

    public func validateTestPlan(sessionID: String) throws -> TestPlanValidation {
        let plan = try testPlan(sessionID: sessionID)
        let recording = try redactedRecording(sessionID: sessionID)
        return TestPlanValidator.validate(plan, exports: [recording.generatedXCTest, recording.generatedAppium, recording.generatedAppiumTypeScript, recording.generatedAppiumPython, recording.generatedAppiumJava, recording.generatedGherkin, recording.portableJSON])
    }
    public func replayRecording(sessionID: String, optimized: Bool = false, variables: [String: String] = [:], resilient: Bool = false, resetApp: Bool = false) throws -> ReplayResult {
        let recording = try recording(sessionID: sessionID)
        let steps = optimized ? try optimizedTestPlan(sessionID: sessionID).steps : recording.steps.map { TestPlanStep(id: "step-\($0.index + 1)", action: $0.action, success: $0.success, durationMilliseconds: $0.durationMilliseconds) }
        let started = Date()
        if resetApp, let bundle = (try self.session(sessionID)).bundleIdentifier { _ = try? performUnrecorded(.terminate(bundleIdentifier: bundle), sessionID: sessionID); _ = try? performUnrecorded(.launch(bundleIdentifier: bundle), sessionID: sessionID) }
        for (index, step) in steps.enumerated() {
            do { let action = resolveParameters(in: step.action, variables: variables); try enforcePolicy(action, sessionID: sessionID); if !resilient { try consumeUnrecordedCommandBudget(sessionID: sessionID) }; _ = try (resilient ? performWithSelectorRepair(action, sessionID: sessionID) : performUnrecorded(action, sessionID: sessionID)) }
            catch { return ReplayResult(success: false, executedSteps: index, totalSteps: steps.count, failedStep: index + 1, error: error.localizedDescription, durationMilliseconds: Int(Date().timeIntervalSince(started) * 1000)) }
        }
        return ReplayResult(success: true, executedSteps: steps.count, totalSteps: steps.count, durationMilliseconds: Int(Date().timeIntervalSince(started) * 1000))
    }
    public func repairSelector(sessionID: String, selector: ScoutSelector, limit: Int = 5) throws -> [SelectorRepair] {
        if try currentContext(sessionID: sessionID) != "NATIVE_APP" {
            let script = "Array.from(document.querySelectorAll('button,a,input,textarea,select,[role=button],[onclick]')).map(e => ({selector: e.id ? '#' + e.id : (e.getAttribute('name') ? e.tagName.toLowerCase() + '[name=\\\"' + e.getAttribute('name') + '\\\"]' : e.tagName.toLowerCase()), label: e.innerText || e.getAttribute('aria-label') || e.getAttribute('name') || e.value || ''}))"
            let value = try executeWebViewScript(sessionID: sessionID, script: script, argumentsJSON: "[]") ?? "[]"
            let elements = (try? JSONSerialization.jsonObject(with: Data(value.utf8))) as? [[String: Any]] ?? []
            let target = normalize(selector.value)
            let repairs = elements.compactMap { element -> SelectorRepair? in
                guard let raw = element["selector"] as? String, !raw.isEmpty else { return nil }
                let label = element["label"] as? String ?? ""
                let score = max(similarity(target, normalize(raw)), similarity(target, normalize(label)))
                guard score >= 0.2 else { return nil }
                return SelectorRepair(selector: ScoutSelector(strategy: .cssSelector, value: raw), score: score, reason: "Coincidencia semántica en DOM WebView")
            }
            return Array(repairs.sorted { $0.score > $1.score }.prefix(limit))
        }
        let data = try perform(.accessibilityTreeWithOptions(AccessibilityOptions(visibleOnly: true, interactiveOnly: false, maxElements: 200)), sessionID: sessionID) ?? Data()
        let elements = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["elements"] as? [[String: Any]] ?? []
        let target = normalize(selector.value); var repairs: [SelectorRepair] = []
        lock.lock(); let fingerprints = semanticFingerprints[sessionID] ?? [:]; lock.unlock()
        for fp in fingerprints.values { let score = max(similarity(target, normalize(fp.identifier)), similarity(target, normalize(fp.label))); if score >= 0.3 { repairs.append(SelectorRepair(selector: ScoutSelector(strategy: .accessibilityIdentifier, value: fp.identifier.isEmpty ? fp.label : fp.identifier), score: score + 0.1, reason: "Fingerprint semántico registrado previamente")) } }
        for element in elements {
            let identifier = (element["identifier"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let label = (element["label"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let value = (element["value"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let candidates: [(ScoutSelector, String)] = [(identifier.map { ScoutSelector(strategy: .accessibilityIdentifier, value: $0) }, "identifier"), (label.map { ScoutSelector(strategy: .label, value: $0) }, "label"), (value.map { ScoutSelector(strategy: .value, value: $0) }, "value")].compactMap { selector, name in selector.map { ($0, name) } }
            for (candidate, name) in candidates { let score = similarity(target, normalize(candidate.value)); if score >= 0.2 { repairs.append(SelectorRepair(selector: candidate, score: score, reason: "Coincidencia semántica por \(name)")) } }
        }
        return Array(repairs.sorted { $0.score > $1.score }.prefix(limit))
    }
    public func previewSelectorRepair(sessionID: String, action: ScoutAction, limit: Int = 5) throws -> [ActionRepairProposal] {
        guard let selector = selector(in: action) else { throw ScoutError.invalidRequest("La acción no contiene un selector reparable") }
        return try repairSelector(sessionID: sessionID, selector: selector, limit: limit).map { repair in
            ActionRepairProposal(original: action, proposed: replacingSelector(in: action, with: repair.selector), score: repair.score, reason: repair.reason)
        }
    }
    public func recordRepairDecision(sessionID: String, proposal: ActionRepairProposal, decision: RepairAuditEntry.Decision) throws -> RepairAuditEntry { try requireSession(sessionID); recordRepair(sessionID: sessionID, proposal: proposal, decision: decision); lock.lock(); let entry = repairEntries[sessionID]?.last; lock.unlock(); guard let entry else { throw ScoutError.invalidRequest("No se pudo registrar la reparación") }; return entry }
    public func repairAudit(sessionID: String, limit: Int = 100) throws -> [RepairAuditEntry] { try requireSession(sessionID); lock.lock(); let entries = Array((repairEntries[sessionID] ?? []).suffix(min(max(0, limit), 500))); lock.unlock(); return entries }
    public func accessibilityAudit(sessionID: String) throws -> AccessibilityAudit {
        if try currentContext(sessionID: sessionID) != "NATIVE_APP" {
            let script = "Array.from(document.querySelectorAll('button,a,input,textarea,select,[role=button]')).map(e => { const r=e.getBoundingClientRect(); return {identifier:e.id || '', label:e.getAttribute('aria-label') || e.getAttribute('name') || e.innerText || e.value || '', type:e.tagName.toLowerCase(), width:r.width, height:r.height}; })"
            let value = try executeWebViewScript(sessionID: sessionID, script: script, argumentsJSON: "[]") ?? "[]"
            let elements = (try? JSONSerialization.jsonObject(with: Data(value.utf8))) as? [[String: Any]] ?? []
            var issues: [AccessibilityIssue] = []; var labels: [String: Int] = [:]
            for element in elements {
                let identifier = element["identifier"] as? String; let label = element["label"] as? String; let type = element["type"] as? String ?? "control"
                if identifier?.isEmpty != false { issues.append(AccessibilityIssue(rule: "missing_identifier", severity: .warning, message: "Control DOM sin id estable", identifier: identifier, label: label)) }
                if label?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false { issues.append(AccessibilityIssue(rule: "missing_label", severity: .error, message: "Control DOM sin nombre accesible", identifier: identifier, label: label)) }
                if let label, !label.isEmpty { labels[label, default: 0] += 1 }
                if let width = element["width"] as? Double, let height = element["height"] as? Double, width < 44 || height < 44 { issues.append(AccessibilityIssue(rule: "small_hit_target", severity: .warning, message: "Área táctil DOM menor de 44 puntos", identifier: identifier, label: label)) }
                _ = type
            }
            for element in elements { guard let label = element["label"] as? String, labels[label, default: 0] > 1, !label.isEmpty else { continue }; issues.append(AccessibilityIssue(rule: "ambiguous_label", severity: .warning, message: "Label DOM repetido en varios controles", identifier: element["identifier"] as? String, label: label)) }
            return AccessibilityAudit(scannedElements: elements.count, issues: issues)
        }
        let data = try perform(.accessibilityTreeWithOptions(AccessibilityOptions(visibleOnly: true, interactiveOnly: false, maxElements: 500)), sessionID: sessionID) ?? Data()
        let elements = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["elements"] as? [[String: Any]] ?? []
        var issues: [AccessibilityIssue] = []; var labels: [String: Int] = [:]
        for element in elements {
            let identifier = element["identifier"] as? String; let label = element["label"] as? String; let type = String(describing: element["type"] ?? "").lowercased(); let interactive = type.contains("button") || type.contains("textfield") || type.contains("textview") || type.contains("link") || type.contains("cell") || type.contains("switch") || type.contains("slider") || type.contains("tab")
            guard interactive else { continue }
            if identifier?.isEmpty != false { issues.append(AccessibilityIssue(rule: "missing_identifier", severity: .warning, message: "Control interactivo sin accessibility identifier", identifier: identifier, label: label)) }
            if label?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false { issues.append(AccessibilityIssue(rule: "missing_label", severity: .error, message: "Control interactivo sin label accesible", identifier: identifier, label: label)) }
            if let label, !label.isEmpty { labels[label, default: 0] += 1 }
            if let frame = element["frame"] as? [String: Any], let width = frame["width"] as? Double, let height = frame["height"] as? Double, width < 44 || height < 44 { issues.append(AccessibilityIssue(rule: "small_hit_target", severity: .warning, message: "Área táctil menor de 44 puntos", identifier: identifier, label: label)) }
        }
        for element in elements { guard let label = element["label"] as? String, labels[label, default: 0] > 1, !label.isEmpty else { continue }; issues.append(AccessibilityIssue(rule: "ambiguous_label", severity: .warning, message: "Label repetido en varios controles", identifier: element["identifier"] as? String, label: label)) }
        return AccessibilityAudit(scannedElements: elements.count, issues: issues)
    }
    public func sessionReport(sessionID: String) throws -> SessionDiagnosticReport {
        try requireSession(sessionID); let context = try currentContext(sessionID: sessionID); let url = try currentURL(sessionID: sessionID); let title = try? pageTitle(sessionID: sessionID); let bridge = try bridgeStatus(sessionID: sessionID); let webView = try webViewStatus(sessionID: sessionID); let navigation = try navigationGraph(sessionID: sessionID); let checkpoints = try listCheckpoints(sessionID: sessionID); lock.lock(); let steps = recordings[sessionID]?.count ?? completedRecordings[sessionID]?.steps.count ?? 0; lock.unlock(); let audit = try? accessibilityAudit(sessionID: sessionID); return SessionDiagnosticReport(sessionID: sessionID, context: context, url: url, title: title ?? nil, bridge: bridge, webView: webView, navigation: navigation, checkpoints: checkpoints, recordedStepCount: steps, accessibilityIssueCount: audit?.issues.count, metrics: try metrics(sessionID: sessionID))
    }
    public func sessionReportHTML(sessionID: String) throws -> String {
        let report = try sessionReport(sessionID: sessionID); let data = try JSONEncoder().encode(report); let json = String(data: data, encoding: .utf8) ?? "{}"; let escaped = json.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        let overlay = (try? accessibilityOverlay(sessionID: sessionID))
        let screenshotTag = overlay?.screenshotBase64.isEmpty == false ? "<img src=\"data:image/png;base64,\(overlay!.screenshotBase64)\" style=\"max-width:100%;border-radius:8px;margin:16px 0\"/>" : ""
        let elementsHTML = (overlay?.elements ?? []).prefix(50).map { el -> String in "<tr><td>\(el.identifier.isEmpty ? "&mdash;" : el.identifier)</td><td>\(el.label.isEmpty ? "&mdash;" : el.label)</td><td>\(el.elementType)</td></tr>" }.joined(separator: "\n")
        return "<!doctype html><html><head><meta charset=\"utf-8\"><title>CuyScout report</title><style>body{font:15px -apple-system;margin:32px;background:#f6f7f9;color:#17202a}main{max-width:1000px;margin:auto;background:white;padding:24px;border-radius:12px;box-shadow:0 2px 12px #0001}pre{white-space:pre-wrap;background:#f0f2f5;padding:16px;border-radius:8px;overflow:auto}.ok{color:#16803c}table{width:100%;border-collapse:collapse;margin:16px 0}th,td{padding:8px 12px;text-align:left;border-bottom:1px solid #e0e0e0}th{background:#f6f7f9}</style></head><body><main><h1>CuyScout session report</h1><p class=\"ok\">Session \(sessionID)</p>\(screenshotTag)<h2>Accessibility elements</h2><table><thead><tr><th>Identifier</th><th>Label</th><th>Type</th></tr></thead><tbody>\(elementsHTML)</tbody></table><h2>Diagnostic JSON</h2><pre>\(escaped)</pre></main></body></html>"
    }
    private func normalize(_ value: String) -> String { value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression) }
    private func similarity(_ left: String, _ right: String) -> Double { if left == right { return 1 }; let a = Set(left.split(separator: " ")); let b = Set(right.split(separator: " ")); guard !a.isEmpty && !b.isEmpty else { return 0 }; return Double(a.intersection(b).count) / Double(max(a.count, b.count)) }

    public func findElement(sessionID: String, selector: ScoutSelector) throws -> String {
        let deadline = Date().addingTimeInterval(try implicitTimeout(sessionID: sessionID))
        while true {
            do {
                if try currentContext(sessionID: sessionID) == "NATIVE_APP" { _ = try perform(.findElement(selector), sessionID: sessionID) }
                else { let result = try executeWebViewScript(sessionID: sessionID, script: webElementScript(selector: selector, operation: "find"), argumentsJSON: jsonArguments([selector.value])); guard isJavaScriptTrue(result) else { throw ScoutError.noSuchElement("No se encontró el elemento WebView: \(selector.value)") } }
                break
            } catch let error as ScoutError { if Date() >= deadline { if case .unsupported = error { throw error }; throw ScoutError.noSuchElement("No se encontró el elemento: \(selector.value)") }; Thread.sleep(forTimeInterval: 0.1) }
            catch { if Date() >= deadline { throw ScoutError.noSuchElement("No se encontró el elemento: \(selector.value)") }; Thread.sleep(forTimeInterval: 0.1) }
        }
        let elementID = UUID().uuidString
        lock.lock(); elementReferences[sessionID, default: [:]][elementID] = selector; lock.unlock()
        return elementID
    }
    public func findElements(sessionID: String, selector: ScoutSelector) throws -> [String] {
        let deadline = Date().addingTimeInterval(try implicitTimeout(sessionID: sessionID)); var count = 0
        repeat {
            if try currentContext(sessionID: sessionID) == "NATIVE_APP" { let data = try perform(.findElements(selector), sessionID: sessionID) ?? Data(); let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]; count = (object?["elements"] as? [[String: Any]])?.count ?? 0 }
            else { let result = try executeWebViewScript(sessionID: sessionID, script: webElementScript(selector: selector, operation: "findAll"), argumentsJSON: jsonArguments([selector.value])); count = Int(result ?? "0") ?? 0 }
            if count == 0 && Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
        } while count == 0 && Date() < deadline
        guard count > 0 else { return [] }
        let ids = (0..<count).map { _ in UUID().uuidString }
        lock.lock(); var references = elementReferences[sessionID] ?? [:]; ids.forEach { references[$0] = selector }; elementReferences[sessionID] = references; lock.unlock()
        return ids
    }
    public func findElementFromElement(sessionID: String, parentElementID: String, selector: ScoutSelector) throws -> String {
        let parent = try elementSelector(sessionID: sessionID, elementID: parentElementID)
        if try currentContext(sessionID: sessionID) == "NATIVE_APP" {
            let deadline = Date().addingTimeInterval(try implicitTimeout(sessionID: sessionID))
            while true {
                do { _ = try performThroughBridge(.findElementFromElement(parent: parent, child: selector), sessionID: sessionID); break }
                catch let error as ScoutError { if Date() >= deadline { if case .unsupported = error { throw error }; throw ScoutError.noSuchElement("No se encontró el elemento relativo: \(selector.value)") }; Thread.sleep(forTimeInterval: 0.1) }
                catch { if Date() >= deadline { throw ScoutError.noSuchElement("No se encontró el elemento relativo: \(selector.value)") }; Thread.sleep(forTimeInterval: 0.1) }
            }
            let elementID = UUID().uuidString
            lock.lock(); elementReferences[sessionID, default: [:]][elementID] = selector; lock.unlock()
            return elementID
        }
        guard parent.strategy == .cssSelector, selector.strategy == .cssSelector else { throw ScoutError.unsupported("La búsqueda relativa WebView requiere selectores CSS") }
        return try findElement(sessionID: sessionID, selector: ScoutSelector(strategy: .cssSelector, value: "\(parent.value) \(selector.value)"))
    }
    public func findElementsFromElement(sessionID: String, parentElementID: String, selector: ScoutSelector) throws -> [String] {
        let parent = try elementSelector(sessionID: sessionID, elementID: parentElementID)
        if try currentContext(sessionID: sessionID) == "NATIVE_APP" {
            let deadline = Date().addingTimeInterval(try implicitTimeout(sessionID: sessionID)); var count = 0
            repeat {
                let data = try performThroughBridge(.findElementsFromElement(parent: parent, child: selector), sessionID: sessionID) ?? Data()
                let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                count = (object?["elements"] as? [[String: Any]])?.count ?? 0
                if count == 0 && Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
            } while count == 0 && Date() < deadline
            guard count > 0 else { return [] }
            let ids = (0..<count).map { _ in UUID().uuidString }
            lock.lock(); var references = elementReferences[sessionID] ?? [:]; ids.forEach { references[$0] = selector }; elementReferences[sessionID] = references; lock.unlock()
            return ids
        }
        guard parent.strategy == .cssSelector, selector.strategy == .cssSelector else { throw ScoutError.unsupported("La búsqueda relativa WebView requiere selectores CSS") }
        return try findElements(sessionID: sessionID, selector: ScoutSelector(strategy: .cssSelector, value: "\(parent.value) \(selector.value)"))
    }
    public func performElementAction(sessionID: String, elementID: String, action: (ScoutSelector) -> ScoutAction) throws -> Data? {
        lock.lock(); let selector = elementReferences[sessionID]?[elementID]; lock.unlock(); guard let selector else { throw ScoutError.staleElementReference("Unknown or expired element reference: \(elementID)") }
        if try currentContext(sessionID: sessionID) != "NATIVE_APP" { return try performWebElementAction(action(selector), sessionID: sessionID) }
        return try perform(action(selector), sessionID: sessionID)
    }
    public func elementSelector(sessionID: String, elementID: String) throws -> ScoutSelector {
        lock.lock(); let selector = elementReferences[sessionID]?[elementID]; lock.unlock(); guard let selector else { throw ScoutError.staleElementReference("Unknown or expired element reference: \(elementID)") }; return selector
    }
    public func updateTimeouts(sessionID: String, values: [String: Double]) throws { try requireSession(sessionID); let allowed = Set(["implicit", "pageLoad", "script"]); guard values.keys.allSatisfy({ allowed.contains($0) }), values.values.allSatisfy({ $0.isFinite && $0 >= 0 }) else { throw ScoutError.invalidRequest("Timeouts must contain only implicit, pageLoad or script with finite non-negative milliseconds") }; lock.lock(); timeouts[sessionID, default: [:]].merge(values) { _, new in new }; lock.unlock() }
    public func getTimeouts(sessionID: String) throws -> [String: Double] { try requireSession(sessionID); lock.lock(); let value = timeouts[sessionID] ?? [:]; lock.unlock(); return value }
    public func setCurrentURL(sessionID: String, url: String) throws { try requireSession(sessionID); lock.lock(); currentURLs[sessionID] = url; lock.unlock() }
    public func currentURL(sessionID: String) throws -> String { try requireSession(sessionID); lock.lock(); let value = currentURLs[sessionID] ?? ""; lock.unlock(); return value }
    public func pageTitle(sessionID: String) throws -> String {
        try requireSession(sessionID)
        if try currentContext(sessionID: sessionID) != "NATIVE_APP", let value = try executeWebViewScript(sessionID: sessionID, script: "document.title", argumentsJSON: "[]") { return decodeJavaScriptString(value) }
        lock.lock(); let title = sessions[sessionID]?.bundleIdentifier ?? ""; lock.unlock(); return title
    }
    public func pageSource(sessionID: String) throws -> String {
        try requireSession(sessionID)
        if try currentContext(sessionID: sessionID) != "NATIVE_APP", let value = try executeWebViewScript(sessionID: sessionID, script: "document.documentElement.outerHTML", argumentsJSON: "[]") { return decodeJavaScriptString(value) }
        return String(data: try perform(.accessibilityTree, sessionID: sessionID) ?? Data("{}".utf8), encoding: .utf8) ?? "{}"
    }
    public func pageInfo(sessionID: String) throws -> PageInfo {
        let context = try currentContext(sessionID: sessionID)
        let url = try currentURL(sessionID: sessionID)
        let title = try pageTitle(sessionID: sessionID)
        let sourceLength = try pageSource(sessionID: sessionID).utf8.count
        return PageInfo(context: context, url: url, title: title, sourceLength: sourceLength)
    }
    public func actionSuggestions(sessionID: String, maxSuggestions: Int = 20) throws -> [ActionSuggestion] {
        if try currentContext(sessionID: sessionID) != "NATIVE_APP" {
            let script = "Array.from(document.querySelectorAll('button,a,input,textarea,select,[role=button],[onclick]')).slice(0, arguments[0]).map(e => ({selector: e.id ? '#' + e.id : e.tagName.toLowerCase(), editable: ['INPUT','TEXTAREA','SELECT'].includes(e.tagName), label: e.innerText || e.getAttribute('aria-label') || e.getAttribute('name') || ''}))"
            let args = (try? JSONSerialization.data(withJSONObject: [maxSuggestions])).flatMap { String(data: $0, encoding: .utf8) } ?? "[20]"
            let value = try executeWebViewScript(sessionID: sessionID, script: script, argumentsJSON: args) ?? "[]"
            let elements = (try? JSONSerialization.jsonObject(with: Data(value.utf8))) as? [[String: Any]] ?? []
            return rankActionSuggestions(elements.compactMap { element in
                guard let selectorValue = element["selector"] as? String, !selectorValue.isEmpty else { return nil }
                let selector = ScoutSelector(strategy: .cssSelector, value: selectorValue)
                let editable = element["editable"] as? Bool ?? false
                let action = editable ? ScoutAction.typeElement(selector, text: "<text>") : ScoutAction.tapElement(selector)
                return ActionSuggestion(action: action, reason: editable ? "Campo DOM editable detectado" : "Control DOM interactivo visible", risk: suggestionRisk(action, selectorValue: selectorValue))
            }, sessionID: sessionID)
        }
        let data = try perform(.accessibilityTreeWithOptions(AccessibilityOptions(visibleOnly: true, interactiveOnly: true, maxElements: maxSuggestions * 2)), sessionID: sessionID) ?? Data()
        let elements = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["elements"] as? [[String: Any]] ?? []
        return nativeSuggestions(from: elements, sessionID: sessionID, maxSuggestions: maxSuggestions)
    }

    /// Un elemento se considera accionable por su tipo semántico. El árbol puede venir sin
    /// filtrar —`observe` lo pide una sola vez incluyendo textos estáticos para la identidad
    /// de pantalla— y proponer un tap sobre una etiqueta sería una acción sin efecto.
    private func isInteractiveType(_ type: String) -> Bool {
        let value = type.lowercased()
        return ["button", "textfield", "securetextfield", "textview", "searchfield", "link", "cell",
                "switch", "slider", "stepper", "toggle", "checkbox", "menuitem", "picker", "tab"]
            .contains { value.contains($0) }
    }

    private func nativeSuggestions(from elements: [[String: Any]], sessionID: String, maxSuggestions: Int) -> [ActionSuggestion] {
        var seen = Set<String>(); var suggestions: [ActionSuggestion] = []
        for element in elements {
            guard isInteractiveType(String(describing: element["type"] ?? "")) else { continue }
            let identifier = (element["identifier"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let label = (element["label"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let value = (element["value"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            guard let selectorValue = identifier ?? label ?? value else { continue }
            let strategy: ScoutSelector.Strategy = identifier != nil ? .accessibilityIdentifier : label != nil ? .label : .value
            let key = "\(strategy.rawValue):\(selectorValue)"; guard seen.insert(key).inserted else { continue }
            let selector = ScoutSelector(strategy: strategy, value: selectorValue)
            let type = String(describing: element["type"] ?? "").lowercased()
            if type.contains("textfield") || type.contains("textview") || type.contains("secure") || type.contains("searchfield") { let action = ScoutAction.typeElement(selector, text: "<text>"); suggestions.append(ActionSuggestion(action: action, reason: "Campo editable detectado", risk: suggestionRisk(action, selectorValue: selectorValue))) }
            else { let action = ScoutAction.tapElement(selector); suggestions.append(ActionSuggestion(action: action, reason: "Control interactivo visible", risk: suggestionRisk(action, selectorValue: selectorValue))) }
            if suggestions.count >= maxSuggestions { break }
        }
        return rankActionSuggestions(suggestions, sessionID: sessionID)
    }
    private func rankActionSuggestions(_ suggestions: [ActionSuggestion], sessionID: String) -> [ActionSuggestion] {
        lock.lock(); let transitions = navigationGraphs[sessionID]?.snapshot().transitions ?? []; lock.unlock()
        let explored = Set(transitions.compactMap { actionSignature($0.action) })
        return suggestions.enumerated().sorted { left, right in
            let leftNew = explored.contains(actionSignature(left.element.action)) ? 0 : 1
            let rightNew = explored.contains(actionSignature(right.element.action)) ? 0 : 1
            if leftNew != rightNew { return leftNew > rightNew }
            let leftRisk = riskRank(left.element.risk); let rightRisk = riskRank(right.element.risk)
            if leftRisk != rightRisk { return leftRisk < rightRisk }
            return left.offset < right.offset
        }.map { item in
            guard !explored.contains(actionSignature(item.element.action)) else { return item.element }
            return ActionSuggestion(action: item.element.action, reason: "Ruta nueva no cubierta; \(item.element.reason)", risk: item.element.risk)
        }
    }
    private func suggestionRisk(_ action: ScoutAction, selectorValue: String) -> String {
        let value = selectorValue.lowercased()
        if value.contains("delete") || value.contains("remove") || value.contains("reset") || value.contains("logout") || value.contains("purchase") || value.contains("submit") { return "high" }
        if isTypingAction(action) { return value.contains("password") || value.contains("secret") || value.contains("token") ? "high" : "medium" }
        return "low"
    }
    private func riskRank(_ risk: String?) -> Int { risk == "high" ? 2 : risk == "medium" ? 1 : 0 }
    private func actionSignature(_ action: ScoutAction) -> String { (try? JSONEncoder().encode(action).base64EncodedString()) ?? String(describing: action) }
    public func observe(sessionID: String, maxActions: Int = 20) throws -> AgentObservation {
        let context = try currentContext(sessionID: sessionID)
        // En NATIVE_APP el árbol se lee UNA vez y de ahí salen la identidad de pantalla y las
        // acciones sugeridas. Pedirlo por separado para `pageInfo`, para el `stateId` y para
        // las sugerencias costaba tres viajes al puente XCTest por cada observación: el mismo
        // trabajo en el dispositivo, repetido, en el bucle que el agente más ejecuta.
        guard context == "NATIVE_APP" else {
            let info = try pageInfo(sessionID: sessionID)
            let stateId = StateIdentity.stableID(try pageSource(sessionID: sessionID))
            lock.lock(); let previous = observationStates[sessionID]; observationStates[sessionID] = stateId; let exploration = explorations[sessionID]?.report(); lock.unlock()
            return AgentObservation(context: info.context, url: info.url, title: info.title, stateId: stateId, changed: previous != stateId, actions: try actionSuggestions(sessionID: sessionID, maxSuggestions: maxActions), exploration: exploration)
        }
        // Se incluyen los textos estáticos: un mensaje de error que aparece sin cambiar ningún
        // control es un cambio de estado, y sin él el agente reintentaría creyendo que nada pasó.
        let data = try perform(.accessibilityTreeWithOptions(AccessibilityOptions(visibleOnly: true, interactiveOnly: false, maxElements: max(maxActions * 8, 200))), sessionID: sessionID) ?? Data()
        let source = String(data: data, encoding: .utf8) ?? "{}"
        let elements = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["elements"] as? [[String: Any]] ?? []
        let stateId = StateIdentity.stableID(source)
        lock.lock(); let previous = observationStates[sessionID]; observationStates[sessionID] = stateId; let exploration = explorations[sessionID]?.report(); lock.unlock()
        let title = try pageTitle(sessionID: sessionID)
        let url = try currentURL(sessionID: sessionID)
        return AgentObservation(context: context, url: url, title: title, stateId: stateId, changed: previous != stateId, actions: nativeSuggestions(from: elements, sessionID: sessionID, maxSuggestions: maxActions), texts: visibleTexts(from: elements), exploration: exploration)
    }

    /// Punto de entrada para pruebas de la extracción de textos.
    public func visibleTextsForTesting(_ elements: [[String: Any]]) -> [String] { visibleTexts(from: elements) }

    /// El label de un icono de SF Symbols es el nombre del símbolo (`arrow.left.arrow.right.circle.fill`).
    /// No es texto que la persona vea en pantalla y solo añadiría ruido a la verificación.
    private func isSymbolName(_ value: String) -> Bool {
        guard !value.contains(" "), value.contains("."), value.count > 3 else { return false }
        return value.allSatisfy { $0.isLowercase || $0 == "." || $0.isNumber }
    }

    /// Textos visibles de la pantalla para que el agente pueda VERIFICAR sin descargar el
    /// árbol completo. Solo elementos que muestran texto, con su identificador cuando lo
    /// tienen, sin duplicados y sin la geometría que hace caro al árbol.
    private func visibleTexts(from elements: [[String: Any]], limit: Int = 60) -> [String] {
        var seen = Set<String>(); var result: [String] = []
        for element in elements {
            let type = String(describing: element["type"] ?? "").lowercased()
            guard ["statictext", "textfield", "securetextfield", "textview", "searchfield", "link", "alert"].contains(where: { type.contains($0) }) else { continue }
            let label = (element["label"] as? String) ?? ""
            let value = (element["value"] as? String) ?? ""
            // En un campo de texto lo que importa es lo escrito; en una etiqueta, su texto.
            let text = value.isEmpty ? label : (label.isEmpty ? value : "\(label): \(value)")
            let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty, !isSymbolName(clean) else { continue }
            let identifier = (element["identifier"] as? String) ?? ""
            let entry = identifier.isEmpty ? clean : "\(identifier): \(clean)"
            guard seen.insert(entry).inserted else { continue }
            result.append(entry)
            if result.count >= limit { break }
        }
        return result
    }
    public func agentState(sessionID: String, maxActions: Int = 20, recentEvents: Int = 5, lightweight: Bool = false) throws -> AgentStateSnapshot {
        let readiness = try sessionReadiness(sessionID: sessionID)
        let observation: AgentObservation
        if lightweight {
            lock.lock(); let exploration = explorations[sessionID]?.report(); lock.unlock()
            observation = AgentObservation(context: readiness.context, url: try currentURL(sessionID: sessionID), title: (try? pageTitle(sessionID: sessionID)) ?? "", stateId: "lightweight:\(readiness.context)", changed: false, actions: [], exploration: exploration)
        } else { do {
            observation = try observe(sessionID: sessionID, maxActions: maxActions)
        } catch ScoutError.unsupported {
            lock.lock(); let exploration = explorations[sessionID]?.report(); lock.unlock()
            let url = try currentURL(sessionID: sessionID); let title = (try? pageTitle(sessionID: sessionID)) ?? ""
            observation = AgentObservation(context: readiness.context, url: url, title: title, stateId: "unavailable:\(readiness.context)", changed: true, actions: [], exploration: exploration)
        } }
        let metricValues = try metrics(sessionID: sessionID)
        let eventValues = try events(sessionID: sessionID).suffix(min(max(0, recentEvents), 20))
        let summaries = eventValues.map { AgentEventSummary(id: $0.id, kind: $0.kind, success: $0.success, durationMilliseconds: $0.durationMilliseconds, error: $0.error) }
        let coverage = try explorationCoverage(sessionID: sessionID)
        // Bucle fuera del modo exploration: el agente repite la misma acción efectiva y la
        // pantalla no cambia. La protección anti-bucle solo corría dentro de una exploración,
        // así que un agente que trabaja por objetivo podía repetir el mismo tap indefinidamente.
        // La ventana del bucle es independiente de `recentEvents`: el agente puede pedir pocos
        // eventos y las lecturas de pantalla intercaladas consumirían ese margen.
        let repeatingIneffectiveAction = try !observation.changed && isRepeatingSameEffectiveAction(events(sessionID: sessionID).suffix(20))
        let loopDetected = observation.exploration?.status == .loopDetected || repeatingIneffectiveAction
        let learnedLessons = try contextualLessons(sessionID: sessionID, limit: 5)
        let hint: String
        if readiness.blockers.contains("xctest_bridge_not_registered") { hint = "connect_xctest_bridge" }
        else if readiness.blockers.contains("webview_adapter_not_connected") { hint = "connect_webview_adapter" }
        else if readiness.blockers.contains("command_budget_exhausted") { hint = "stop_session_or_create_new" }
        else if repeatingIneffectiveAction { hint = "stop_repeating_ineffective_action_and_choose_another" }
        else { hint = observation.exploration?.suggestion ?? learnedActionHint(lessons: learnedLessons, events: eventValues) ?? (summaries.last(where: { !$0.success }) != nil ? "inspect_last_error_and_retry_resilient" : (observation.changed ? "choose_from_actions" : "use_accessibility_diff")) }
        return AgentStateSnapshot(sessionID: sessionID, observation: observation, metrics: metricValues, recentEvents: summaries, coverage: coverage, readiness: readiness, loopDetected: loopDetected, nextActionHint: hint, lessons: learnedLessons)
    }
    /// Las lecturas de pantalla no cuentan como intentos del agente: `observe` publica su
    /// propia lectura del árbol como evento, y sin descartarlas cualquier observación repetida
    /// parecería una repetición de acción.
    private func isObservationalAction(_ action: ScoutAction) -> Bool {
        switch action {
        case .accessibilityTree, .accessibilityTreeWithOptions, .accessibilityDiff, .screenshot,
             .elementAttribute, .elementProperty, .elementDisplayed, .elementEnabled, .elementRect,
             .elementSelected, .elementName, .elementScreenshot, .findElement, .findElements,
             .findElementFromElement, .findElementsFromElement, .alertText, .activeElement, .listApps:
            return true
        default:
            return false
        }
    }

    /// Punto de entrada para pruebas del detector de repetición; la lógica de bucle es
    /// difícil de ejercitar de extremo a extremo sin un dispositivo.
    public func isRepeatingSameEffectiveActionForTesting(_ events: [ScoutEvent]) -> Bool { isRepeatingSameEffectiveAction(events) }

    private func isRepeatingSameEffectiveAction(_ events: some Collection<ScoutEvent>) -> Bool {
        let effective = events.filter { !isObservationalAction($0.action) }.suffix(3)
        guard effective.count == 3 else { return false }
        let signatures = Set(effective.map { actionSignature($0.action) })
        return signatures.count == 1
    }

    public func sessionReadiness(sessionID: String) throws -> SessionReadiness {
        try requireSession(sessionID)
        let context = try currentContext(sessionID: sessionID); let bridge = try bridgeStatus(sessionID: sessionID); let webView = try webViewStatus(sessionID: sessionID)
        let policy = try securityPolicy(sessionID: sessionID); lock.lock(); let commandsUsed = commandCounts[sessionID] ?? 0; lock.unlock(); let remaining = policy.maxCommandsPerSession > 0 ? max(0, policy.maxCommandsPerSession - commandsUsed) : nil
        var blockers: [String] = []
        if context == "NATIVE_APP" && !bridge.registered { blockers.append("xctest_bridge_not_registered") }
        // Distinguir "no hay puente" de "el runner está arrancando" evita que el agente
        // reinstale o recree la sesión cuando solo tenía que esperar unos segundos.
        if context == "NATIVE_APP" && bridge.registered && !bridge.runnerAttached { blockers.append("xctest_runner_starting") }
        if context != "NATIVE_APP" && !webView.connected { blockers.append("webview_adapter_not_connected") }
        if remaining == 0 { blockers.append("command_budget_exhausted") }
        return SessionReadiness(interactionReady: blockers.isEmpty, context: context, xctestBridgeConnected: bridge.registered, webViewConnected: webView.connected, commandsUsed: commandsUsed, commandsRemaining: remaining, blockers: blockers)
    }
    public func sessionHealth(sessionID: String) throws -> SessionHealthSnapshot { let readiness = try sessionReadiness(sessionID: sessionID); let metrics = try self.metrics(sessionID: sessionID); return SessionHealthSnapshot(sessionID: sessionID, healthy: readiness.interactionReady && metrics.failureRate < 0.5, context: readiness.context, blockers: readiness.blockers, commandsUsed: readiness.commandsUsed, commandsRemaining: readiness.commandsRemaining, failureRate: metrics.failureRate, p95DurationMilliseconds: metrics.p95DurationMilliseconds) }
    public func securityAudit(sessionID: String, limit: Int = 100) throws -> [SecurityAuditEntry] { try requireSession(sessionID); lock.lock(); let entries = Array((auditEntries[sessionID] ?? []).suffix(min(max(0, limit), 500))); lock.unlock(); return entries }
    public func navigationGraph(sessionID: String) throws -> NavigationGraph { try requireSession(sessionID); lock.lock(); let graph = navigationGraphs[sessionID]?.snapshot() ?? NavigationGraph(states: [], transitions: []); lock.unlock(); return graph }
    public func explorationCoverage(sessionID: String) throws -> ExplorationCoverage {
        let graph = try navigationGraph(sessionID: sessionID)
        let keys = graph.transitions.map { transition in
            let action = (try? JSONEncoder().encode(transition.action).base64EncodedString()) ?? String(describing: transition.action)
            return "\(transition.fromState)->\(transition.toState):\(action)"
        }
        let unique = Set(keys).count; let repeated = max(0, keys.count - unique)
        lock.lock(); let report = explorations[sessionID]?.report(); lock.unlock()
        return ExplorationCoverage(stateCount: graph.states.count, transitionCount: keys.count, uniqueTransitionCount: unique, repeatedTransitionCount: repeated, repeatedTransitionRate: keys.isEmpty ? 0 : Double(repeated) / Double(keys.count), loopRisk: report?.status == .loopDetected, nextActionHint: report?.suggestion)
    }
    public func generateScreenContract(sessionID: String, name: String = "screen") throws -> ScreenContract {
        let context = try currentContext(sessionID: sessionID)
        let data = try perform(.accessibilityTreeWithOptions(AccessibilityOptions(visibleOnly: true, interactiveOnly: true, maxElements: 500)), sessionID: sessionID) ?? Data()
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let values = object?["elements"] as? [[String: Any]] ?? []
        let elements = values.compactMap { value -> ScreenContractElement? in
            let identifier = (value["identifier"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let label = (value["label"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let role = String(describing: value["type"] ?? "unknown")
            guard !identifier.isEmpty || label?.isEmpty == false else { return nil }
            return ScreenContractElement(identifier: identifier.isEmpty ? label! : identifier, role: role, label: label?.isEmpty == true ? nil : label)
        }
        let source = try pageSource(sessionID: sessionID); let stateId = StateIdentity.stableID(source)
        return ScreenContract(name: name, stateId: stateId, context: context, elements: elements)
    }
    public func compareScreenContract(sessionID: String, contract: ScreenContract) throws -> ScreenContractComparison {
        let current = try generateScreenContract(sessionID: sessionID, name: contract.name)
        let currentByID = Dictionary(uniqueKeysWithValues: current.elements.map { ($0.identifier, $0) })
        let expectedByID = Dictionary(uniqueKeysWithValues: contract.elements.map { ($0.identifier, $0) })
        let missing = contract.elements.filter { currentByID[$0.identifier] == nil }
        let changed = contract.elements.compactMap { expected -> ScreenContractElement? in guard let actual = currentByID[expected.identifier], actual.role != expected.role || actual.label != expected.label else { return nil }; return actual }
        let unexpected = current.elements.filter { expectedByID[$0.identifier] == nil }
        return ScreenContractComparison(matches: missing.isEmpty && changed.isEmpty, missing: missing, changed: changed, unexpected: unexpected)
    }
    public func createCheckpoint(sessionID: String, name: String) throws -> ExplorationCheckpoint {
        try requireSession(sessionID); let source = try pageSource(sessionID: sessionID); let stateId = StateIdentity.stableID(source); lock.lock(); let steps = recordings[sessionID]?.count ?? completedRecordings[sessionID]?.steps.count ?? 0; let checkpoint = ExplorationCheckpoint(name: name, stateId: stateId, stepCount: steps); checkpoints[sessionID, default: []].append(checkpoint); lock.unlock(); return checkpoint
    }
    public func listCheckpoints(sessionID: String) throws -> [ExplorationCheckpoint] { try requireSession(sessionID); lock.lock(); let result = checkpoints[sessionID] ?? []; lock.unlock(); return result }
    public func restoreCheckpoint(sessionID: String, checkpointID: String, resetApp: Bool = false) throws -> CheckpointRestoreResult {
        let checkpoint: ExplorationCheckpoint
        lock.lock(); checkpoint = (checkpoints[sessionID] ?? []).first { $0.id == checkpointID } ?? ExplorationCheckpoint(name: "missing", stateId: "", stepCount: 0); lock.unlock()
        guard checkpoint.name != "missing" else { throw ScoutError.invalidRequest("Checkpoint not found") }
        let session = try self.session(sessionID); var didReset = false
        if resetApp, let bundle = session.bundleIdentifier { let policy = try securityPolicy(sessionID: sessionID); guard policy.allowLifecycle else { throw ScoutError.unsupported("La política de seguridad bloquea resetApp durante checkpoint restore") }; _ = try? controller.execute(.terminate(bundleIdentifier: bundle), on: session.device); _ = try? controller.execute(.launch(bundleIdentifier: bundle), on: session.device); didReset = true }
        let recording = try recording(sessionID: sessionID); let steps = recording.steps.prefix(checkpoint.stepCount)
        for step in steps { try enforcePolicy(step.action, sessionID: sessionID); try consumeUnrecordedCommandBudget(sessionID: sessionID); _ = try performUnrecorded(step.action, sessionID: sessionID) }
        return CheckpointRestoreResult(checkpoint: checkpoint, replayedSteps: steps.count, resetPerformed: didReset, warning: didReset ? nil : "El replay se ejecutó desde el estado actual; solicita resetApp para empezar limpio.")
    }
    public func updateSettings(sessionID: String, values: [String: Any]) throws { try requireSession(sessionID); lock.lock(); settings[sessionID, default: [:]].merge(values) { _, new in new }; lock.unlock() }
    public func getSettings(sessionID: String) throws -> [String: Any] { try requireSession(sessionID); lock.lock(); let value = settings[sessionID] ?? [:]; lock.unlock(); return value }
    public func setOrientation(sessionID: String, orientation: DeviceOrientation) throws { try requireSession(sessionID); _ = try perform(.rotate(orientation), sessionID: sessionID); lock.lock(); orientations[sessionID] = orientation; lock.unlock() }
    public func orientation(sessionID: String) throws -> DeviceOrientation { try requireSession(sessionID); lock.lock(); let value = orientations[sessionID] ?? .portrait; lock.unlock(); return value }
    public func windowRect(sessionID: String) throws -> [String: Double] {
        try requireSession(sessionID)
        if try currentContext(sessionID: sessionID) != "NATIVE_APP" {
            if let value = try executeWebViewScript(sessionID: sessionID, script: "({x: window.screenX, y: window.screenY, width: window.innerWidth, height: window.innerHeight})", argumentsJSON: "[]"), let data = value.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return ["x": obj["x"] as? Double ?? 0, "y": obj["y"] as? Double ?? 0, "width": obj["width"] as? Double ?? 0, "height": obj["height"] as? Double ?? 0]
            }
        }
        let data = try perform(.screenshot, sessionID: sessionID) ?? Data()
        if let source = CGImageSourceCreateWithData(data as CFData, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            return ["x": 0, "y": 0, "width": Double(image.width), "height": Double(image.height)]
        }
        return ["x": 0, "y": 0, "width": 0, "height": 0]
    }
    public func setWindowRect(sessionID: String, x: Double, y: Double, width: Double, height: Double) throws {
        try requireSession(sessionID)
        if try currentContext(sessionID: sessionID) != "NATIVE_APP" {
            _ = try executeWebViewScript(sessionID: sessionID, script: "window.moveTo(\(Int(x)), \(Int(y))); window.resizeTo(\(Int(width)), \(Int(height))); true", argumentsJSON: "[]"); return
        }
        throw ScoutError.unsupported("setWindowRect no es soportado en Native iOS")
    }
    public func activeElement(sessionID: String) throws -> String? {
        try requireSession(sessionID)
        if try currentContext(sessionID: sessionID) != "NATIVE_APP" {
            if let value = try executeWebViewScript(sessionID: sessionID, script: "(function() { const e = document.activeElement; if (!e || e === document.body) return null; const id = e.id || e.name || e.getAttribute('data-testid') || ''; return id || e.tagName.toLowerCase(); })()", argumentsJSON: "[]"), let data = value.data(using: .utf8), let parsed = try? JSONSerialization.jsonObject(with: data) as? String, !parsed.isEmpty {
                let selector = ScoutSelector(strategy: .cssSelector, value: parsed)
                return try findElement(sessionID: sessionID, selector: selector)
            }
            return nil
        }
        return nil
    }
    public func setAlertText(sessionID: String, text: String) throws {
        try requireSession(sessionID)
        _ = try performThroughBridge(.alertText(text), sessionID: sessionID)
    }
    public func cookies(sessionID: String) throws -> [Cookie] {
        try requireSession(sessionID)
        guard try currentContext(sessionID: sessionID) != "NATIVE_APP" else { return [] }
        guard let value = try executeWebViewScript(sessionID: sessionID, script: "JSON.stringify(document.cookie ? document.cookie.split('; ').map(c => { const [name, ...rest] = c.split('='); return {name, value: rest.join('='), path:'/', domain:location.hostname, secure:location.protocol==='https:', httpOnly:false, expiry:null}; }) : [])", argumentsJSON: "[]"), let data = value.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([Cookie].self, from: data)) ?? []
    }
    public func addCookie(sessionID: String, cookie: Cookie) throws {
        try requireSession(sessionID)
        guard try currentContext(sessionID: sessionID) != "NATIVE_APP" else { throw ScoutError.unsupported("Cookies requieren un contexto WebView") }
        var parts = "\(cookie.name)=\(cookie.value)"
        if let path = cookie.path { parts += "; path=\(path)" }
        if let domain = cookie.domain { parts += "; domain=\(domain)" }
        if cookie.secure { parts += "; secure" }
        if cookie.httpOnly { parts += "; httponly" }
        if let expiry = cookie.expiry { parts += "; max-age=\(Int(expiry))" }
        _ = try executeWebViewScript(sessionID: sessionID, script: "document.cookie = arguments[0]; true", argumentsJSON: jsonArguments([parts]))
    }
    public func deleteCookie(sessionID: String, name: String) throws {
        try requireSession(sessionID)
        guard try currentContext(sessionID: sessionID) != "NATIVE_APP" else { throw ScoutError.unsupported("Cookies requieren un contexto WebView") }
        _ = try executeWebViewScript(sessionID: sessionID, script: "document.cookie = arguments[0] + '=; expires=Thu, 01 Jan 1970 00:00:00 GMT; path=/'; true", argumentsJSON: jsonArguments([name]))
    }
    public func deleteAllCookies(sessionID: String) throws {
        try requireSession(sessionID)
        guard try currentContext(sessionID: sessionID) != "NATIVE_APP" else { throw ScoutError.unsupported("Cookies requieren un contexto WebView") }
        _ = try executeWebViewScript(sessionID: sessionID, script: "document.cookie.split('; ').forEach(c => { const name = c.split('=')[0]; document.cookie = name + '=; expires=Thu, 01 Jan 1970 00:00:00 GMT; path=/'; }); true", argumentsJSON: "[]")
    }
    public func grantPermission(sessionID: String, bundleIdentifier: String, service: String) throws -> PermissionGrant {
        try requireSession(sessionID)
        let session = try self.session(sessionID)
        _ = try performUnrecorded(.grantPermission(bundleIdentifier: bundleIdentifier, service: service), sessionID: sessionID)
        return PermissionGrant(bundleIdentifier: bundleIdentifier, service: service, granted: true)
    }
    public func setBiometry(sessionID: String, enrolled: Bool, enabled: Bool = true) throws -> BiometryResult {
        try requireSession(sessionID)
        _ = try performUnrecorded(.setBiometry(enrolled: enrolled, enabled: enabled), sessionID: sessionID)
        return BiometryResult(enrolled: enrolled, enabled: enabled)
    }
    public func setLocation(sessionID: String, latitude: Double, longitude: Double) throws {
        try requireSession(sessionID)
        _ = try performUnrecorded(.setLocation(latitude: latitude, longitude: longitude), sessionID: sessionID)
    }
    public func visualDiff(sessionID: String, tolerance: Double = 0.1) throws -> VisualDiffResult {
        try requireSession(sessionID)
        let current = try perform(.screenshot, sessionID: sessionID) ?? Data()
        lock.lock(); let previous = visualBaselines[sessionID]; visualBaselines[sessionID] = current; lock.unlock()
        guard let previous else { lock.lock(); visualBaselines[sessionID] = current; lock.unlock(); return VisualDiffResult(identical: true, differenceRatio: 0, tolerance: tolerance, pixelDifferences: 0) }
        return try comparePNG(previous, current, tolerance: tolerance)
    }
    public func timeline(sessionID: String, includeScreenshots: Bool = false) throws -> [TimelineEntry] {
        try requireSession(sessionID)
        lock.lock(); let rawEvents = events[sessionID] ?? []; lock.unlock()
        return rawEvents.map { event in
            let screenshot: String? = includeScreenshots && !event.success ? nil : nil
            return TimelineEntry(id: event.id, timestamp: event.timestamp, actionType: actionName(event.action), success: event.success, durationMilliseconds: event.durationMilliseconds, error: event.error, screenshotBase64: screenshot)
        }
    }
    public func enqueueSession(deviceID: String?, bundleIdentifier: String?, driverID: String = "ios-simulator", priority: SessionPriority = .normal) -> QueueEntry {
        let entry = QueueEntry(sessionID: UUID().uuidString, deviceID: deviceID, bundleIdentifier: bundleIdentifier, driverID: driverID, priority: priority)
        lock.lock(); sessionQueue.append(entry); sessionQueue.sort { $0.priority > $1.priority }; lock.unlock()
        return entry
    }
    public func sessionQueueSnapshot() -> [QueueEntry] { lock.lock(); defer { lock.unlock() }; return sessionQueue }
    public func cancelQueuedSession(sessionID: String) -> Bool { lock.lock(); defer { lock.unlock() }; let before = sessionQueue.count; sessionQueue.removeAll { $0.sessionID == sessionID }; return sessionQueue.count < before }
    public func fleetDashboard() throws -> FleetDashboard {
        let allDevices = try listDevices(); let leases = scheduler.leaseSnapshot()
        let leasedIDs = Set(leases.map(\.deviceID))
        let available = allDevices.filter { $0.isAvailable && !leasedIDs.contains($0.id) }
        let metrics = fleetMetrics()
        lock.lock(); let queued = sessionQueue; let totalEvents = events.values.flatMap { $0 }.count; lock.unlock()
        let workers = farmWorkersStatus()
        return FleetDashboard(activeSessions: metrics.activeSessions, queuedSessions: queued.count, leasedDevices: leases.count, availableDevices: available.count, totalEvents: totalEvents, failureRate: metrics.failureRate, averageDurationMilliseconds: metrics.averageDurationMilliseconds, leases: leases, queue: queued, workersOnline: workers.filter { $0.status == .online }.count, workersExpired: workers.filter { $0.status == .expired }.count)
    }
    public func recordConsoleLog(sessionID: String, level: String, message: String, source: String? = nil) throws {
        try requireSession(sessionID)
        lock.lock(); consoleLogSequence += 1; var logs = consoleLogs[sessionID] ?? []; logs.append(ConsoleLogEntry(id: consoleLogSequence, level: level, message: message, source: source)); let retention = min(max(Int(ProcessInfo.processInfo.environment["CUYSCOUT_CONSOLE_RETENTION"] ?? "500") ?? 500, 10), 10000); if logs.count > retention { logs.removeFirst(logs.count - retention) }; consoleLogs[sessionID] = logs; lock.unlock()
    }
    public func consoleLogs(sessionID: String, after: Int = 0) throws -> [ConsoleLogEntry] {
        try requireSession(sessionID); lock.lock(); let logs = (consoleLogs[sessionID] ?? []).filter { $0.id > after }; lock.unlock(); return logs
    }
    public func addReactiveRule(sessionID: String, rule: ReactiveRule) throws {
        try requireSession(sessionID); lock.lock(); reactiveRules[sessionID, default: []].append(rule); lock.unlock()
    }
    public func reactiveRulesList(sessionID: String) throws -> [ReactiveRule] {
        try requireSession(sessionID); lock.lock(); let rules = reactiveRules[sessionID] ?? []; lock.unlock(); return rules
    }
    public func removeReactiveRule(sessionID: String, ruleID: String) throws -> Bool {
        try requireSession(sessionID); lock.lock(); let before = reactiveRules[sessionID]?.count ?? 0; reactiveRules[sessionID]?.removeAll { $0.id == ruleID }; let after = reactiveRules[sessionID]?.count ?? 0; lock.unlock(); return after < before
    }
    public func cacheApp(bundleIdentifier: String, path: String) -> AppCacheEntry {
        let entry = AppCacheEntry(bundleIdentifier: bundleIdentifier, path: path); lock.lock(); appCache[bundleIdentifier] = entry; lock.unlock(); return entry
    }
    public func cachedApp(bundleIdentifier: String) -> AppCacheEntry? { lock.lock(); defer { lock.unlock() }; return appCache[bundleIdentifier] }
    public func appCacheList() -> [AppCacheEntry] { lock.lock(); defer { lock.unlock() }; return Array(appCache.values).sorted { $0.bundleIdentifier < $1.bundleIdentifier } }
    public func clearAppCache(bundleIdentifier: String? = nil) { lock.lock(); if let bundleIdentifier { appCache.removeValue(forKey: bundleIdentifier) } else { appCache.removeAll() }; lock.unlock() }
    public func registerFarmWorker(url: String, capabilities: [String] = [], maxSessions: Int = 4) throws -> FarmWorker {
        guard let parsed = URL(string: url), let scheme = parsed.scheme?.lowercased(), scheme == "http" || scheme == "https", parsed.host != nil else { throw ScoutError.invalidRequest("worker url must be an absolute http(s) URL") }
        let worker = FarmWorker(id: UUID().uuidString, url: url, capabilities: capabilities, maxSessions: max(1, maxSessions), activeSessions: 0, ttlSeconds: farmWorkerTTLSeconds())
        lock.lock(); farmWorkers[worker.id] = worker; lock.unlock()
        return worker
    }
    public func farmWorkerHeartbeat(workerID: String, activeSessions: Int? = nil) throws -> FarmWorker {
        lock.lock()
        guard var worker = farmWorkers[workerID] else { lock.unlock(); throw ScoutError.invalidRequest("worker_not_registered") }
        worker.lastHeartbeat = Date()
        if let activeSessions { worker.activeSessions = max(0, activeSessions) }
        worker.status = .online
        worker.capacityAvailable = worker.activeSessions < worker.maxSessions
        farmWorkers[workerID] = worker
        lock.unlock()
        return worker
    }
    public func deregisterFarmWorker(workerID: String) -> Bool { lock.lock(); defer { lock.unlock() }; return farmWorkers.removeValue(forKey: workerID) != nil }
    public func farmWorkersStatus(asOf reference: Date = Date()) -> [FarmWorker] {
        lock.lock(); var workers = Array(farmWorkers.values); lock.unlock()
        for index in workers.indices {
            if reference.timeIntervalSince(workers[index].lastHeartbeat) > Double(workers[index].ttlSeconds) { workers[index].status = .expired }
            workers[index].capacityAvailable = workers[index].status == .online && workers[index].activeSessions < workers[index].maxSessions
        }
        return workers.sorted { $0.registeredAt < $1.registeredAt }
    }
    private func farmWorkerTTLSeconds() -> Int { min(max(Int(ProcessInfo.processInfo.environment["CUYSCOUT_WORKER_TTL_SECONDS"] ?? "60") ?? 60, 10), 3600) }
    public func recordFingerprint(sessionID: String, elementID: String, identifier: String, label: String, elementType: String, frame: [String: Double]) throws {
        try requireSession(sessionID)
        let hash = StateIdentity.stableID("\(identifier)|\(label)|\(elementType)|\(frame["x"] ?? 0)|\(frame["y"] ?? 0)|\(frame["width"] ?? 0)|\(frame["height"] ?? 0)")
        let fingerprint = SemanticFingerprint(elementID: elementID, identifier: identifier, label: label, elementType: elementType, frame: frame, fingerprintHash: hash)
        lock.lock(); semanticFingerprints[sessionID, default: [:]][elementID] = fingerprint; lock.unlock()
    }
    public func fingerprints(sessionID: String) throws -> [SemanticFingerprint] {
        try requireSession(sessionID); lock.lock(); let values = Array(semanticFingerprints[sessionID]?.values ?? [:].values); lock.unlock(); return values
    }
    public func matchFingerprint(sessionID: String, identifier: String?, label: String?, elementType: String?) throws -> SemanticFingerprint? {
        try requireSession(sessionID); lock.lock(); let prints = semanticFingerprints[sessionID] ?? [:]; lock.unlock()
        return prints.values.first { fp in
            (identifier == nil || fp.identifier == identifier) && (label == nil || fp.label == label) && (elementType == nil || fp.elementType == elementType)
        }
    }
    public func compareBehavior(sessionID: String, expectedSuccess: Bool, actualSuccess: Bool, expectedError: String?) throws -> BehaviorComparison {
        try requireSession(sessionID)
        var diffs: [String] = []
        if expectedSuccess != actualSuccess { diffs.append("success_mismatch: expected \(expectedSuccess), got \(actualSuccess)") }
        if let expectedError, !actualSuccess { diffs.append("error_expected: \(expectedError)") }
        return BehaviorComparison(matched: diffs.isEmpty, differences: diffs, expectedSuccess: expectedSuccess, actualSuccess: actualSuccess)
    }
    public func driverManifests() -> [DriverManifest] { driverRegistry.manifests() }
    public func registerDriverManifest(_ manifest: DriverManifest) { driverRegistry.registerManifest(manifest) }
    public func loadDriverFromManifest(_ manifest: DriverManifest) -> DriverLoadResult {
        let result = driverRegistry.loadDriverFromManifest(manifest)
        if result.loaded, let driver = driverRegistry.driver(id: manifest.id) { _ = driver.health() }
        return result
    }
    public func pluginRoutes() -> [PluginRoute] { pluginRegistry.allRoutes() }
    public func handlePluginRoute(method: String, path: String, body: String, sessionID: String?) throws -> PluginRouteHandlerResult? { try pluginRegistry.handlePluginRoute(method: method, path: path, body: body, sessionID: sessionID) }
    public func recordNetworkRequest(sessionID: String, method: String, url: String, status: Int = 0, requestSize: Int = 0, responseSize: Int = 0, durationMilliseconds: Int = 0) throws {
        try requireSession(sessionID)
        lock.lock(); networkRequestSequence += 1; var requests = networkRequests[sessionID] ?? []; requests.append(NetworkRequestEntry(id: networkRequestSequence, method: method, url: url, status: status, requestSize: requestSize, responseSize: responseSize, durationMilliseconds: durationMilliseconds)); let retention = min(max(Int(ProcessInfo.processInfo.environment["CUYSCOUT_NETWORK_RETENTION"] ?? "500") ?? 500, 10), 10000); if requests.count > retention { requests.removeFirst(requests.count - retention) }; networkRequests[sessionID] = requests; lock.unlock()
    }
    public func networkRequestsList(sessionID: String, after: Int = 0) throws -> [NetworkRequestEntry] {
        try requireSession(sessionID); lock.lock(); let requests = (networkRequests[sessionID] ?? []).filter { $0.id > after }; lock.unlock(); return requests
    }
    public func setShardConfig(sessionID: String, shardIndex: Int, shardCount: Int) throws {
        try requireSession(sessionID); guard shardCount > 0, shardIndex >= 0, shardIndex < shardCount else { throw ScoutError.invalidRequest("Shard config invalid: index \(shardIndex), count \(shardCount)") }; lock.lock(); shardConfigs[sessionID] = ShardConfig(shardIndex: shardIndex, shardCount: shardCount); lock.unlock()
    }
    public func shardConfig(sessionID: String) throws -> ShardConfig? {
        try requireSession(sessionID); lock.lock(); let config = shardConfigs[sessionID]; lock.unlock(); return config
    }
    public func shouldRunInShard(sessionID: String, stepIndex: Int) throws -> Bool {
        guard let config = try shardConfig(sessionID: sessionID) else { return true }; return stepIndex % config.shardCount == config.shardIndex
    }
    public func recordOtelSpan(sessionID: String, span: OtelSpan) throws {
        try requireSession(sessionID); lock.lock(); otelSpans[sessionID, default: []].append(span); lock.unlock()
    }
    public func otelSpansList(sessionID: String) throws -> [OtelSpan] {
        try requireSession(sessionID); lock.lock(); let spans = otelSpans[sessionID] ?? []; lock.unlock(); return spans
    }
    public func setAppearance(sessionID: String, mode: String) throws {
        try requireSession(sessionID); _ = try performUnrecorded(.setAppearance(mode), sessionID: sessionID); lock.lock(); appearanceStates[sessionID] = mode; lock.unlock()
    }
    public func setStatusBar(sessionID: String, config: StatusBarConfig) throws {
        try requireSession(sessionID); _ = try performUnrecorded(.setStatusBar(time: config.time, dataNetwork: config.dataNetwork, wifiMode: config.wifiMode, batteryLevel: config.batteryLevel, batteryState: config.batteryState), sessionID: sessionID)
    }
    public func startVideoRecording(sessionID: String, path: String) throws -> VideoRecordingResult {
        try requireSession(sessionID); _ = try performUnrecorded(.startVideoRecording(path), sessionID: sessionID); return VideoRecordingResult(path: path, started: true)
    }
    public func stopVideoRecording(sessionID: String) throws {
        try requireSession(sessionID); _ = try performUnrecorded(.stopVideoRecording, sessionID: sessionID)
    }
    public func listInstalledApps(sessionID: String) throws -> [AppInfo] {
        try requireSession(sessionID); let session = try self.session(sessionID)
        let data = try performUnrecorded(.listApps, sessionID: sessionID) ?? Data()
        let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        return root.compactMap { bundleID, value in (value as? [String: Any]).map { AppInfo(bundleIdentifier: bundleID, name: $0["CFBundleName"] as? String ?? bundleID, type: $0["ApplicationType"] as? String ?? "User") } }.sorted { $0.bundleIdentifier < $1.bundleIdentifier }
    }
    public func resetKeychain(sessionID: String) throws {
        try requireSession(sessionID); _ = try performUnrecorded(.resetKeychain, sessionID: sessionID)
    }
    public func deepLink(sessionID: String, url: String) throws {
        try requireSession(sessionID); _ = try performUnrecorded(.deepLink(url), sessionID: sessionID)
    }
    public func pushNotification(sessionID: String, bundleIdentifier: String, payloadPath: String) throws -> PushNotificationPayload {
        try requireSession(sessionID); _ = try performUnrecorded(.pushNotification(bundleIdentifier: bundleIdentifier, payloadPath: payloadPath), sessionID: sessionID); return PushNotificationPayload(bundleIdentifier: bundleIdentifier, payloadPath: payloadPath, sent: true)
    }
    public func setContentSize(sessionID: String, size: String) throws {
        try requireSession(sessionID); _ = try performUnrecorded(.setContentSize(size), sessionID: sessionID); lock.lock(); contentSizeStates[sessionID] = size; lock.unlock()
    }
    public func addMedia(sessionID: String, path: String) throws {
        try requireSession(sessionID); _ = try performUnrecorded(.addMedia(path), sessionID: sessionID)
    }
    public func spawnProcess(sessionID: String, bundleIdentifier: String, args: [String] = []) throws -> ProcessSpawnResult {
        try requireSession(sessionID); let output = String(data: try performUnrecorded(.spawnProcess(bundleIdentifier: bundleIdentifier, args: args), sessionID: sessionID) ?? Data(), encoding: .utf8) ?? ""; return ProcessSpawnResult(bundleIdentifier: bundleIdentifier, pid: 0, output: output)
    }
    public func icloudSync(sessionID: String) throws -> ICloudSyncStatus {
        try requireSession(sessionID); _ = try? performUnrecorded(.icloudSync, sessionID: sessionID); return ICloudSyncStatus(synced: true, detail: "iCloud sync triggered")
    }
    public func elementLocation(sessionID: String, elementID: String) throws -> [String: Double] {
        let data = try performElementAction(sessionID: sessionID, elementID: elementID) { .elementRect($0) } ?? Data()
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let rect = (object["value"] as? [String: Any]) ?? [:]
        let x = (rect["x"] as? Double) ?? 0; let y = (rect["y"] as? Double) ?? 0
        let width = (rect["width"] as? Double) ?? 0; let height = (rect["height"] as? Double) ?? 0
        return ["x": x, "y": y, "centerX": x + width / 2, "centerY": y + height / 2]
    }
    public func elementSize(sessionID: String, elementID: String) throws -> [String: Double] {
        let data = try performElementAction(sessionID: sessionID, elementID: elementID) { .elementRect($0) } ?? Data()
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let rect = (object["value"] as? [String: Any]) ?? [:]
        return ["width": (rect["width"] as? Double) ?? 0, "height": (rect["height"] as? Double) ?? 0]
    }
    public func shake(sessionID: String) throws {
        try requireSession(sessionID); _ = try performUnrecorded(.shake, sessionID: sessionID)
    }
    public func appearance(sessionID: String) throws -> String {
        try requireSession(sessionID); lock.lock(); let value = appearanceStates[sessionID] ?? "light"; lock.unlock(); return value
    }
    public func contentSize(sessionID: String) throws -> String {
        try requireSession(sessionID); lock.lock(); let value = contentSizeStates[sessionID] ?? "standard"; lock.unlock(); return value
    }
    public func enumerateFiles(sessionID: String, path: String) throws -> String {
        try requireSession(sessionID); let data = try performUnrecorded(.enumerateFiles(path), sessionID: sessionID) ?? Data(); return String(data: data, encoding: .utf8) ?? ""
    }
    public func bootDevice(deviceID: String) throws { try controller.boot(deviceID: deviceID) }
    public func shutdownDevice(deviceID: String) throws { try controller.shutdown(deviceID: deviceID) }
    public func eraseDevice(deviceID: String) throws { try controller.erase(deviceID: deviceID) }
    public func cloneDevice(sourceDeviceID: String, name: String) throws -> Device { try controller.clone(sourceDeviceID: sourceDeviceID, name: name) }
    public func deleteDevice(deviceID: String) throws { try controller.delete(deviceID: deviceID) }
    public func createDevice(name: String, runtime: String) throws -> Device { try controller.create(name: name, runtime: runtime) }
    public func renameDevice(deviceID: String, name: String) throws { try controller.rename(deviceID: deviceID, name: name) }
    public func pbsync(sessionID: String) throws { try requireSession(sessionID); let session = try self.session(sessionID); try controller.pbsync(deviceID: session.device.id) }
    public func downloadFile(sessionID: String, source: String, destination: String) throws {
        try requireSession(sessionID); _ = try performUnrecorded(.downloadFile(source: source, destination: destination), sessionID: sessionID)
    }
    public func uploadFile(sessionID: String, source: String, destination: String) throws {
        try requireSession(sessionID); _ = try performUnrecorded(.uploadFile(source: source, destination: destination), sessionID: sessionID)
    }
    public func getAppContainer(sessionID: String, bundleIdentifier: String, container: String = "data") throws -> String {
        try requireSession(sessionID); let session = try self.session(sessionID); let data = try controller.execute(.getAppContainer(bundleIdentifier: bundleIdentifier, container: container), on: session.device) ?? Data(); return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
    public func getConfig(sessionID: String, key: String) throws -> String {
        try requireSession(sessionID); let session = try self.session(sessionID); let data = try controller.execute(.getConfig(key), on: session.device) ?? Data(); return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
    public func setConfig(sessionID: String, key: String, value: String) throws {
        try requireSession(sessionID); _ = try performUnrecorded(.setConfig(key: key, value: value), sessionID: sessionID)
    }
    public func verifyTestPlan(sessionID: String, format: String = "xctest", resetApp: Bool = true) throws -> TestVerificationResult {
        try requireSession(sessionID); let started = Date()
        let recording = try redactedRecording(sessionID: sessionID)
        let export: String
        switch format.lowercased() {
        case "appium", "webdriverio", "js": export = recording.generatedAppium
        case "typescript", "ts": export = recording.generatedAppiumTypeScript
        case "python": export = recording.generatedAppiumPython
        case "java": export = recording.generatedAppiumJava
        case "gherkin": export = recording.generatedGherkin
        case "portable", "json": export = recording.portableJSON
        default: export = recording.generatedXCTest
        }
        let compiled = !export.isEmpty && export.contains("func test") || export.contains("describe(") || export.contains("def test") || export.contains("@Test") || export.contains("Feature:")
        let replay = try replayRecording(sessionID: sessionID, optimized: true, resilient: true, resetApp: resetApp)
        return TestVerificationResult(compiled: compiled, executed: true, passed: replay.success, exportFormat: format, error: replay.error, durationMilliseconds: Int(Date().timeIntervalSince(started) * 1000))
    }
    public func classifyFailure(_ error: Error) -> FailureCategory {
        if let scoutError = error as? ScoutError {
            switch scoutError {
            case .noSuchElement, .staleElementReference: return .selector
            case .commandFailed(let message):
                let lower = message.lowercased()
                if lower.contains("timeout") || lower.contains("bridge") || lower.contains("device") || lower.contains("xctest") { return .infrastructure }
                if lower.contains("network") || lower.contains("connection") { return .environment }
                return .product
            case .invalidRequest, .unsupported: return .environment
            default: return .product
            }
        }
        return .environment
    }
    public func accessibilityOverlay(sessionID: String) throws -> AccessibilityOverlay {
        try requireSession(sessionID)
        let screenshotData = try perform(.screenshot, sessionID: sessionID) ?? Data()
        let treeData = try performThroughBridge(.accessibilityTreeWithOptions(AccessibilityOptions(visibleOnly: true, interactiveOnly: false, maxElements: 200)), sessionID: sessionID) ?? Data()
        let object = (try? JSONSerialization.jsonObject(with: treeData)) as? [String: Any] ?? [:]
        let elements = (object["elements"] as? [[String: Any]] ?? []).map { element in
            OverlayElement(identifier: (element["identifier"] as? String) ?? "", label: (element["label"] as? String) ?? "", elementType: String(describing: element["type"] ?? ""), frame: (element["frame"] as? [String: Any])?.compactMapValues { ($0 as? Double) ?? ($0 as? Int).map(Double.init) } ?? [:])
        }
        return AccessibilityOverlay(screenshotBase64: screenshotData.base64EncodedString(), elements: elements)
    }
    public func visualCompareRegion(sessionID: String, x: Double, y: Double, width: Double, height: Double, tolerance: Double = 0.1) throws -> VisualRegionCompare {
        try requireSession(sessionID)
        let current = try perform(.screenshot, sessionID: sessionID) ?? Data()
        lock.lock(); let previous = visualBaselines[sessionID]; visualBaselines[sessionID] = current; lock.unlock()
        guard let previous else { return VisualRegionCompare(identical: true, differenceRatio: 0, region: ["x": x, "y": y, "width": width, "height": height], pixelDifferences: 0) }
        let croppedPrev = try cropPNG(previous, x: x, y: y, width: width, height: height)
        let croppedCurr = try cropPNG(current, x: x, y: y, width: width, height: height)
        let result = try comparePNG(croppedPrev, croppedCurr, tolerance: tolerance)
        return VisualRegionCompare(identical: result.identical, differenceRatio: result.differenceRatio, region: ["x": x, "y": y, "width": width, "height": height], pixelDifferences: result.pixelDifferences)
    }
    public func setPluginSecurityPolicy(_ policy: PluginSecurityPolicy) { pluginRegistry.setSecurityPolicy(policy) }
    public func detectCycles(sessionID: String) throws -> CycleDetectionResult {
        try requireSession(sessionID)
        let graph = try navigationGraph(sessionID: sessionID)
        var adjacency: [String: Set<String>] = [:]
        for state in graph.states { adjacency[state] = [] }
        for transition in graph.transitions { if adjacency[transition.fromState] != nil { adjacency[transition.fromState]?.insert(transition.toState) } }
        var visited = Set<String>(); var recursionStack = Set<String>(); var cycles: [[String]] = []
        func dfs(_ node: String, _ path: [String]) {
            visited.insert(node); recursionStack.insert(node)
            for neighbor in adjacency[node] ?? [] {
                if !visited.contains(neighbor) { dfs(neighbor, path + [neighbor]) }
                else if recursionStack.contains(neighbor) { let cycleStart = path.firstIndex(of: neighbor) ?? 0; cycles.append(Array(path[cycleStart...]) + [neighbor]) }
            }
            recursionStack.remove(node)
        }
        for state in graph.states where !visited.contains(state) { dfs(state, [state]) }
        let cycleStates = Array(Set(cycles.flatMap { $0 })).sorted()
        let recommendation = cycles.isEmpty ? nil : "backtrack_to_checkpoint_and_try_unexplored_action"
        return CycleDetectionResult(cyclesDetected: cycles.count, cycleStates: cycleStates, hasCycle: !cycles.isEmpty, recommendation: recommendation)
    }
    public func recognizeText(sessionID: String, x: Double? = nil, y: Double? = nil, width: Double? = nil, height: Double? = nil) throws -> OCRResult {
        try requireSession(sessionID)
        let screenshotData = try perform(.screenshot, sessionID: sessionID) ?? Data()
        let imageData: Data
        if let x, let y, let width, let height { imageData = try cropPNG(screenshotData, x: x, y: y, width: width, height: height) } else { imageData = screenshotData }
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return OCRResult(recognizedText: "", confidence: 0) }
        return performOCR(image: image)
    }
    private func performOCR(image: CGImage) -> OCRResult {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US", "es-MX"]
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
        try? handler.perform([request])
        let results = request.results ?? []
        var texts: [String] = []; var confidences: [Double] = []; var ocrObs: [OCRObservation] = []
        for obs in results {
            guard let candidate = obs.topCandidates(1).first else { continue }
            texts.append(candidate.string)
            confidences.append(Double(candidate.confidence))
            let bb = obs.boundingBox
            ocrObs.append(OCRObservation(text: candidate.string, confidence: Double(candidate.confidence), boundingBox: ["x": Double(bb.origin.x), "y": Double(bb.origin.y), "width": Double(bb.width), "height": Double(bb.height)]))
        }
        let text = texts.joined(separator: " ")
        let avgConfidence = confidences.isEmpty ? 0.0 : confidences.reduce(0, +) / Double(confidences.count)
        return OCRResult(recognizedText: text, confidence: avgConfidence, observations: ocrObs)
    }
    public func buildRunner(projectPath: String, scheme: String, destination: String, signingIdentity: String? = nil) throws -> RunnerBuildResult {
        var args = ["-project", projectPath, "-scheme", scheme, "-destination", destination, "build-for-testing"]
        if let signingIdentity { args += ["CODE_SIGN_IDENTITY=\(signingIdentity)"] }
        let output = try controller.runCommand("/usr/bin/xcodebuild", args)
        let built = output.contains("BUILD SUCCEEDED")
        let runnerPath = built ? output.components(separatedBy: "\n").first { $0.contains(".xctestrun") }?.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        return RunnerBuildResult(built: built, runnerPath: runnerPath, error: built ? nil : output, signed: signingIdentity != nil)
    }

    public func startExploration(sessionID: String, limits: ExplorationLimits = ExplorationLimits()) throws -> ExplorationReport {
        try requireSession(sessionID); lock.lock(); explorations[sessionID] = ExplorationState(limits: limits); lock.unlock(); try? startRecording(sessionID: sessionID); return try explorationStatus(sessionID: sessionID)
    }
    public func explorationStatus(sessionID: String) throws -> ExplorationReport { try requireSession(sessionID); lock.lock(); let state = explorations[sessionID]; lock.unlock(); guard let state else { throw ScoutError.invalidRequest("No existe una exploración activa") }; return state.report() }
    public func stopExploration(sessionID: String) throws -> ExplorationResult { let report = try explorationStatus(sessionID: sessionID); lock.lock(); explorations.removeValue(forKey: sessionID); lock.unlock(); let recording = try? stopRecording(sessionID: sessionID); let session = try self.session(sessionID); let learningScope: LessonScope = session.bundleIdentifier == nil ? .session : .project; _ = try? learnFromSession(sessionID: sessionID, scope: learningScope, persist: true, exploration: report); let audit = try? accessibilityAudit(sessionID: sessionID); if let audit { lock.lock(); accessibilityAudits[sessionID] = audit; lock.unlock(); _ = try? sessionArtifactBundle(sessionID: sessionID) }; return ExplorationResult(report: report, recording: recording, accessibilityAudit: audit) }

    private func performThroughBridge(_ action: ScoutAction, sessionID: String) throws -> Data? {
        lock.lock(); let bridge = bridges[sessionID]; lock.unlock(); guard let bridge else { throw ScoutError.unsupported("Registra primero el runner XCTest en /session/SESSION_ID/bridge/register") }
        return try bridge.execute(BridgeCommand(action: action))
    }
    private func executeThroughDriver(_ action: ScoutAction, on device: Device, driverID: String) throws -> Data? {
        guard let driver = driverRegistry.driver(id: driverID) else { throw ScoutError.unsupported("No hay un driver registrado para la sesión: \(driverID)") }
        return try driver.execute(action, on: device)
    }
    private func requireSession(_ id: String) throws { lock.lock(); defer { lock.unlock() }; guard sessions[id] != nil else { throw ScoutError.sessionNotFound } }
    private func recordAudit(action: ScoutAction, sessionID: String, allowed: Bool, reason: String?) { let name = actionName(action); let sensitive = ["launch", "terminate", "backgroundApp", "rotate", "getClipboard", "setClipboard", "openURL"].contains(name); lock.lock(); auditSequence += 1; auditEntries[sessionID, default: []].append(SecurityAuditEntry(id: auditSequence, sessionID: sessionID, actionType: name, allowed: allowed, sensitive: sensitive, reason: reason)); lock.unlock() }
    private func recordRepair(sessionID: String, proposal: ActionRepairProposal, decision: RepairAuditEntry.Decision) { lock.lock(); repairSequence += 1; repairEntries[sessionID, default: []].append(RepairAuditEntry(id: repairSequence, sessionID: sessionID, proposal: proposal, decision: decision)); lock.unlock(); _ = try? sessionArtifactBundle(sessionID: sessionID) }
    private func implicitTimeout(sessionID: String) throws -> Double { try requireSession(sessionID); lock.lock(); let value = timeouts[sessionID]?["implicit"] ?? 0; lock.unlock(); return max(0, value / 1000) }
    private func pageLoadTimeout(sessionID: String) throws -> Double { try requireSession(sessionID); lock.lock(); let value = timeouts[sessionID]?["pageLoad"] ?? 300000; lock.unlock(); return max(0, value / 1000) }
    private func waitForPageLoad(sessionID: String) throws {
        let timeout = try pageLoadTimeout(sessionID: sessionID); guard timeout > 0 else { return }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let ready = try executeWebViewScript(sessionID: sessionID, script: "document.readyState", argumentsJSON: "[]"), ready == "\"complete\"" || ready == "complete" { return }
            Thread.sleep(forTimeInterval: 0.1)
        }
    }
    private func publishEvent(sessionID: String, action: ScoutAction, success: Bool, startedAt: Date, error: String?) { lock.lock(); eventSequence += 1; let eventKind = success ? "command.completed" : "command.failed"; let event = ScoutEvent(id: eventSequence, kind: eventKind, action: action, success: success, durationMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1000), error: error); events[sessionID, default: []].append(event); commandCounts[sessionID, default: 0] += 1; let retention = min(max(Int(ProcessInfo.processInfo.environment["CUYSCOUT_EVENT_RETENTION"] ?? "500") ?? 500, 10), 10000); let retainedCount = events[sessionID]?.count ?? 0; if retainedCount > retention { events[sessionID]?.removeFirst(retainedCount - retention) }; let commandCount = commandCounts[sessionID] ?? 0; let interval = max(0, Int(ProcessInfo.processInfo.environment["CUYSCOUT_AUTOSAVE_INTERVAL"] ?? "10") ?? 10); let shouldAutosave = interval > 0 && commandCount % interval == 0; let rules = reactiveRules[sessionID] ?? []; lock.unlock(); if shouldAutosave { _ = try? sessionArtifactBundle(sessionID: sessionID) }; for rule in rules where rule.enabled && rule.eventKind == eventKind { _ = try? performUnrecorded(rule.action, sessionID: sessionID) } }
    private func actionName(_ action: ScoutAction) -> String {
        guard let data = try? JSONEncoder().encode(action), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let name = object.keys.first else { return "unknown" }
        return name
    }
    private func learnedActionHint(lessons: [LearnedLesson], events: ArraySlice<ScoutEvent>) -> String? {
        guard let last = events.last else { return nil }
        let tags = Set(lessons.flatMap(\.tags))
        if last.success, isTypingAction(last.action), tags.contains("keyboard") { return "dismiss_keyboard_or_scroll_before_next_control" }
        if !last.success && tags.contains("selector") { return "repair_selector_before_retry" }
        if !last.success && tags.contains("timing") { return "wait_for_semantic_stability_before_retry" }
        return nil
    }
    private func isTypingAction(_ action: ScoutAction) -> Bool { if case .type = action { return true }; if case .typeElement = action { return true }; return false }
    private func shouldRedactSensitiveData() -> Bool { ProcessInfo.processInfo.environment["CUYSCOUT_REDACT_SENSITIVE"]?.lowercased() != "false" }
    private func selector(in action: ScoutAction) -> ScoutSelector? {
        switch action { case .findElement(let s), .findElements(let s), .tapElement(let s), .typeElement(let s, _), .waitFor(let s, _), .assertVisible(let s), .assertText(let s, _), .clearElement(let s), .elementAttribute(let s, _), .elementDisplayed(let s), .elementEnabled(let s), .elementRect(let s), .elementScreenshot(let s), .elementSelected(let s), .elementName(let s), .elementProperty(let s, _), .submit(let s), .doubleTap(let s), .longPress(let s, _): return s; default: return nil }
    }
    private func replacingSelector(in action: ScoutAction, with selector: ScoutSelector) -> ScoutAction {
        switch action { case .findElement: return .findElement(selector); case .findElements: return .findElements(selector); case .tapElement: return .tapElement(selector); case .typeElement(_, let text): return .typeElement(selector, text: text); case .waitFor(_, let timeout): return .waitFor(selector, timeout: timeout); case .assertVisible: return .assertVisible(selector); case .assertText(_, let expected): return .assertText(selector, expected: expected); case .clearElement: return .clearElement(selector); case .elementAttribute(_, let name): return .elementAttribute(selector, name: name); case .elementDisplayed: return .elementDisplayed(selector); case .elementEnabled: return .elementEnabled(selector); case .elementRect: return .elementRect(selector); case .elementScreenshot: return .elementScreenshot(selector); case .elementSelected: return .elementSelected(selector); case .elementName: return .elementName(selector); case .elementProperty(_, let name): return .elementProperty(selector, name: name); case .submit: return .submit(selector); case .doubleTap: return .doubleTap(selector); case .longPress(_, let duration): return .longPress(selector, duration: duration); default: return action }
    }
    private func resolveParameters(in action: ScoutAction, variables: [String: String]) -> ScoutAction {
        let resolve: (String) -> String = { value in if value == "<redacted>" { return variables["redacted"] ?? value }; if value == "<text>" { return variables["text"] ?? value }; return value }
        switch action { case .type(let text): return .type(resolve(text)); case .setClipboard(let text): return .setClipboard(resolve(text)); case .typeElement(let selector, let text): return .typeElement(selector, text: resolve(text)); case .assertText(let selector, let expected): return .assertText(selector, expected: resolve(expected)); case .sequence(let actions): return .sequence(actions.map { resolveParameters(in: $0, variables: variables) }); default: return action }
    }
    private func enforcePolicy(_ action: ScoutAction, sessionID: String) throws { if case .sequence(let actions) = action { for child in actions { try enforcePolicy(child, sessionID: sessionID) } }; let policy = try securityPolicy(sessionID: sessionID); let name = actionName(action); if policy.deniedActionTypes.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) { throw ScoutError.unsupported("La política de seguridad bloquea la acción \(name)") }; switch action { case .launch, .terminate, .backgroundApp, .rotate: guard policy.allowLifecycle else { throw ScoutError.unsupported("La política de seguridad bloquea lifecycle/orientación") }; case .getClipboard, .setClipboard: guard policy.allowClipboard else { throw ScoutError.unsupported("La política de seguridad bloquea clipboard") }; case .tap, .swipe, .type: guard policy.allowCoordinates else { throw ScoutError.unsupported("La política de seguridad bloquea acciones directas") }; case .openURL(let url): if URL(string: url)?.scheme?.lowercased() != "file" && !policy.allowExternalURLs { throw ScoutError.unsupported("La política de seguridad bloquea URLs externas") }; default: break } }
    private func enforceCommandBudget(sessionID: String) throws { let policy = try securityPolicy(sessionID: sessionID); guard policy.maxCommandsPerSession > 0 else { return }; lock.lock(); let count = commandCounts[sessionID] ?? 0; lock.unlock(); guard count < policy.maxCommandsPerSession else { throw ScoutError.invalidRequest("Session command budget exhausted") } }
    private func consumeUnrecordedCommandBudget(sessionID: String) throws { let policy = try securityPolicy(sessionID: sessionID); guard policy.maxCommandsPerSession > 0 else { return }; lock.lock(); defer { lock.unlock() }; let count = commandCounts[sessionID] ?? 0; guard count < policy.maxCommandsPerSession else { throw ScoutError.invalidRequest("Session command budget exhausted") }; commandCounts[sessionID] = count + 1 }

    private func performWebElementAction(_ action: ScoutAction, sessionID: String) throws -> Data? {
        let selector: ScoutSelector
        switch action {
        case .findElement(let value), .tapElement(let value), .clearElement(let value), .elementDisplayed(let value), .elementEnabled(let value), .elementRect(let value), .elementScreenshot(let value), .elementAttribute(let value, _), .elementSelected(let value), .elementName(let value), .elementProperty(let value, _): selector = value
        case .typeElement(let value, _): selector = value
        default: throw ScoutError.unsupported("Action is not supported for a WebView element")
        }
        let operation: String
        var args: [Any] = [selector.value]
        switch action {
        case .findElement: operation = "find"
        case .tapElement: operation = "click"
        case .clearElement: operation = "clear"
        case .elementDisplayed: operation = "displayed"
        case .elementEnabled: operation = "enabled"
        case .elementRect: operation = "rect"
        case .elementScreenshot: operation = "screenshot"
        case .elementAttribute(_, let name): operation = "attribute"; args.append(name)
        case .elementProperty(_, let name): operation = "property"; args.append(name)
        case .elementSelected: operation = "selected"
        case .elementName: operation = "name"
        case .typeElement(_, let text): operation = "type"; args.append(text)
        default: throw ScoutError.unsupported("Action is not supported for a WebView element")
        }
        let result = try executeWebViewScript(sessionID: sessionID, script: webElementScript(selector: selector, operation: operation), argumentsJSON: jsonArguments(args))
        guard let result else { return nil }
        guard let data = result.data(using: .utf8) else { return nil }
        if operation == "click" || operation == "clear" || operation == "type" { guard isJavaScriptTrue(result) else { throw ScoutError.noSuchElement("No se encontró el elemento WebView: \(selector.value)") }; return nil }
        if operation == "displayed" || operation == "enabled" { return Data((result == "true" ? "{\"value\":true}" : "{\"value\":false}").utf8) }
        if operation == "selected" { return Data((result == "true" ? "{\"value\":true}" : "{\"value\":false}").utf8) }
        if operation == "name" { return Data(("{\"value\":" + (result == "null" ? "\"\"" : result) + "}").utf8) }
        if operation == "property" { return Data(("{\"value\":" + (result == "null" ? "\"\"" : result) + "}").utf8) }
        if operation == "screenshot" { return try webViewElementScreenshot(selector: selector, sessionID: sessionID) }
        if operation == "attribute" { return Data(("{\"value\":" + result + "}").utf8) }
        return data
    }

    private func webElementScript(selector: ScoutSelector, operation: String) -> String {
        let getter = selector.strategy == .xpath ? "document.evaluate(arguments[0], document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null).singleNodeValue" : "document.querySelector(arguments[0])"
        switch operation {
        case "find": return "(() => { const e = \(getter); return !!e; })()"
        case "findAll": return selector.strategy == .xpath ? "document.evaluate(arguments[0], document, null, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null).snapshotLength" : "document.querySelectorAll(arguments[0]).length"
        case "click": return "(() => { const e = \(getter); if (!e) return false; e.click(); return true; })()"
        case "clear": return "(() => { const e = \(getter); if (!e) return false; e.focus(); e.value = ''; e.dispatchEvent(new Event('input', {bubbles:true})); e.dispatchEvent(new Event('change', {bubbles:true})); return true; })()"
        case "type": return "(() => { const e = \(getter); if (!e) return false; e.focus(); e.value = arguments[1]; e.dispatchEvent(new Event('input', {bubbles:true})); e.dispatchEvent(new Event('change', {bubbles:true})); return true; })()"
        case "displayed": return "(() => { const e = \(getter); return !!(e && e.getClientRects().length); })()"
        case "enabled": return "(() => { const e = \(getter); return !!(e && !e.disabled); })()"
        case "rect": return "(() => { const e = \(getter); if (!e) return null; const r = e.getBoundingClientRect(); return {x:r.x, y:r.y, width:r.width, height:r.height, devicePixelRatio:window.devicePixelRatio || 1}; })()"
        case "screenshot": return "(() => { const e = \(getter); if (!e) return null; const r = e.getBoundingClientRect(); return {x:r.x, y:r.y, width:r.width, height:r.height, devicePixelRatio:window.devicePixelRatio || 1}; })()"
        case "attribute": return "(() => { const e = \(getter); return e ? e.getAttribute(arguments[1]) : null; })()"
        case "selected": return "(() => { const e = \(getter); return !!(e && e.selected); })()"
        case "name": return "(() => { const e = \(getter); return e ? (e.name || '') : null; })()"
        case "property": return "(() => { const e = \(getter); return e ? e[arguments[1]] : null; })()"
        default: return "(() => { const e = \(getter); return e ? {element:{label:e.innerText || e.textContent || '', value:e.value || '', exists:true}} : null; })()"
        }
    }

    private func jsonArguments(_ values: [Any]) -> String { (try? JSONSerialization.data(withJSONObject: values)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]" }
    private func webViewElementScreenshot(selector: ScoutSelector, sessionID: String) throws -> Data {
        let rectJSON = try executeWebViewScript(sessionID: sessionID, script: webElementScript(selector: selector, operation: "screenshot"), argumentsJSON: jsonArguments([selector.value])) ?? "null"
        guard let rectData = rectJSON.data(using: .utf8), let rect = try JSONSerialization.jsonObject(with: rectData) as? [String: Any], let x = rect["x"] as? Double, let y = rect["y"] as? Double, let width = rect["width"] as? Double, let height = rect["height"] as? Double, let scale = rect["devicePixelRatio"] as? Double, width > 0, height > 0 else { throw ScoutError.noSuchElement("No se encontró un rectángulo visible para el elemento WebView: \(selector.value)") }
        let session = try self.session(sessionID)
        guard let screenshot = try executeThroughDriver(.screenshot, on: session.device, driverID: session.driverID) else { throw ScoutError.commandFailed("No se recibió screenshot del dispositivo") }
        return try cropPNG(screenshot, x: x * scale, y: y * scale, width: width * scale, height: height * scale)
    }
    private func cropPNG(_ data: Data, x: Double, y: Double, width: Double, height: Double) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw ScoutError.commandFailed("No se pudo decodificar el screenshot PNG") }
        let originX = max(0, min(image.width - 1, Int(x.rounded()))); let originY = max(0, min(image.height - 1, Int(y.rounded())))
        let cropWidth = min(image.width - originX, max(1, Int(width.rounded()))); let cropHeight = min(image.height - originY, max(1, Int(height.rounded())))
        guard let cropped = image.cropping(to: CGRect(x: originX, y: image.height - originY - cropHeight, width: cropWidth, height: cropHeight)) else { throw ScoutError.commandFailed("No se pudo recortar el screenshot del elemento") }
        let output = NSMutableData(); guard let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else { throw ScoutError.commandFailed("No se pudo codificar el screenshot del elemento") }; CGImageDestinationAddImage(destination, cropped, nil); guard CGImageDestinationFinalize(destination) else { throw ScoutError.commandFailed("No se pudo finalizar el screenshot del elemento") }; return output as Data
    }
    private func comparePNG(_ baseline: Data, _ current: Data, tolerance: Double) throws -> VisualDiffResult {
        guard let sourceA = CGImageSourceCreateWithData(baseline as CFData, nil), let imageA = CGImageSourceCreateImageAtIndex(sourceA, 0, nil) else { throw ScoutError.commandFailed("No se pudo decodificar el screenshot baseline") }
        guard let sourceB = CGImageSourceCreateWithData(current as CFData, nil), let imageB = CGImageSourceCreateImageAtIndex(sourceB, 0, nil) else { throw ScoutError.commandFailed("No se pudo decodificar el screenshot actual") }
        let width = min(imageA.width, imageB.width); let height = min(imageA.height, imageB.height)
        guard width > 0, height > 0 else { return VisualDiffResult(identical: false, differenceRatio: 1.0, tolerance: tolerance, pixelDifferences: -1) }
        let bytesPerRow = width * 4; var pixelsA = [UInt8](repeating: 0, count: bytesPerRow * height); var pixelsB = [UInt8](repeating: 0, count: bytesPerRow * height)
        let colorSpace = CGColorSpaceCreateDeviceRGB(); let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let contextA = CGContext(data: &pixelsA, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo.rawValue), let contextB = CGContext(data: &pixelsB, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo.rawValue) else { throw ScoutError.commandFailed("No se pudo crear contexto de comparación") }
        contextA.draw(imageA, in: CGRect(x: 0, y: 0, width: width, height: height)); contextB.draw(imageB, in: CGRect(x: 0, y: 0, width: width, height: height))
        var differences = 0; let totalPixels = width * height
        for i in 0..<totalPixels { let offset = i * 4; let dr = abs(Int(pixelsA[offset]) - Int(pixelsB[offset])); let dg = abs(Int(pixelsA[offset + 1]) - Int(pixelsB[offset + 1])); let db = abs(Int(pixelsA[offset + 2]) - Int(pixelsB[offset + 2])); if dr > 10 || dg > 10 || db > 10 { differences += 1 } }
        let ratio = totalPixels > 0 ? Double(differences) / Double(totalPixels) : 0
        return VisualDiffResult(identical: ratio <= tolerance, differenceRatio: ratio, tolerance: tolerance, pixelDifferences: differences)
    }
    private func isJavaScriptTrue(_ value: String?) -> Bool { value?.trimmingCharacters(in: .whitespacesAndNewlines) == "true" || value == "\"true\"" }
    private func decodeJavaScriptString(_ value: String) -> String { (try? JSONSerialization.jsonObject(with: Data(value.utf8))) as? String ?? value }

    private func record(_ action: ScoutAction, sessionID: String, startedAt: Date, success: Bool, error: String?) {
        lock.lock(); defer { lock.unlock() }; guard let state = recordings[sessionID] else { return }
        state.append(RecordedStep(index: state.count, action: action, startedAt: startedAt, durationMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1000), success: success, error: error))
    }

    private func explorationBefore(_ action: ScoutAction, sessionID: String) throws {
        lock.lock(); let state = explorations[sessionID]; lock.unlock(); try state?.before(action)
    }
    private func explorationAfter(_ action: ScoutAction, _ data: Data?, sessionID: String) {
        lock.lock(); let state = explorations[sessionID]; lock.unlock(); state?.after(data)
        let stateData = data ?? (try? performThroughBridge(.accessibilityTree, sessionID: sessionID)); guard let stateData else { return }; let source = String(data: stateData, encoding: .utf8) ?? stateData.base64EncodedString(); let toState = StateIdentity.stableID(source); lock.lock(); let graph = navigationGraphs[sessionID] ?? NavigationGraphState(); graph.record(action: action, toState: toState); navigationGraphs[sessionID] = graph; lock.unlock()
    }

    private func accessibilityDiff(_ data: Data, sessionID: String) -> Data {
        let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let elements = root["elements"] as? [[String: Any]] ?? []
        var current: [String: String] = [:]
        for element in elements {
            let id = (element["identifier"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "\(element["type"] ?? "")|\(element["label"] ?? "")|\(element["frame"] ?? "")"
            current[id] = (try? JSONSerialization.data(withJSONObject: element)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        }
        lock.lock(); let previous = accessibilitySnapshots[sessionID] ?? [:]; accessibilitySnapshots[sessionID] = current; lock.unlock()
        let added = current.keys.filter { previous[$0] == nil }.sorted()
        let removed = previous.keys.filter { current[$0] == nil }.sorted()
        let changed = current.keys.filter { previous[$0] != nil && previous[$0] != current[$0] }.sorted()
        return (try? JSONSerialization.data(withJSONObject: ["count": current.count, "added": added, "removed": removed, "changed": changed])) ?? Data("{}".utf8)
    }
}

private final class RecordingState: @unchecked Sendable {
    let startedAt: Date
    private var steps: [RecordedStep] = []
    init(startedAt: Date) { self.startedAt = startedAt }
    var count: Int { steps.count }
    func append(_ step: RecordedStep) { steps.append(step) }
    func snapshot(sessionID: String, stoppedAt: Date?) -> RecordedSession { RecordedSession(sessionID: sessionID, startedAt: startedAt, stoppedAt: stoppedAt, steps: steps) }
}

private final class NavigationGraphState: @unchecked Sendable {
    private var states = Set<String>()
    private var transitions: [NavigationTransition] = []
    private var lastState: String?
    func record(action: ScoutAction, toState: String) { if let lastState { transitions.append(NavigationTransition(fromState: lastState, toState: toState, action: action)) }; states.insert(toState); lastState = toState }
    func restore(_ graph: NavigationGraph) { states = Set(graph.states); transitions = graph.transitions; lastState = graph.transitions.last?.toState ?? graph.states.last }
    func snapshot() -> NavigationGraph { NavigationGraph(states: states.sorted(), transitions: transitions) }
}

private final class ExplorationState: @unchecked Sendable {
    private let lock = NSLock()
    private let limits: ExplorationLimits
    private let startedAt = Date()
    private var status: ExplorationReport.Status = .running
    private var reason: String?
    private var actionCount = 0
    private var repeatedStateCount = 0
    private var visitedStates = Set<String>()
    private var actionRepeats: [String: Int] = [:]
    init(limits: ExplorationLimits) { self.limits = limits }
    func before(_ action: ScoutAction) throws {
        lock.lock(); defer { lock.unlock() }
        guard status == .running else { throw ScoutError.message(reason ?? "La exploración terminó") }
        if Date().timeIntervalSince(startedAt) >= limits.timeoutSeconds { status = .timeout; reason = "timeout"; throw ScoutError.message("La exploración alcanzó su límite de tiempo") }
        if actionCount >= limits.maxActions { status = .actionLimitReached; reason = "action_limit"; throw ScoutError.message("La exploración alcanzó el límite de acciones") }
        actionCount += 1
        let key = (try? JSONEncoder().encode(action).base64EncodedString()) ?? String(describing: action)
        actionRepeats[key, default: 0] += 1
        if actionRepeats[key, default: 0] > limits.maxActionRepeats { status = .loopDetected; reason = "same_action_repeated"; throw ScoutError.message("Bucle detectado: la misma acción se repitió demasiadas veces") }
    }
    func after(_ data: Data?) {
        guard let data else { return }; let state = data.base64EncodedString(); lock.lock(); defer { lock.unlock() }; guard status == .running else { return }
        if visitedStates.contains(state) { repeatedStateCount += 1 } else { visitedStates.insert(state) }
        if repeatedStateCount >= limits.maxStateRepeats { status = .loopDetected; reason = "same_state_repeated" }
    }
    func report() -> ExplorationReport { lock.lock(); defer { lock.unlock() }; return ExplorationReport(status: status, reason: reason, actionCount: actionCount, repeatedStateCount: repeatedStateCount, visitedStateCount: visitedStates.count, suggestion: status == .loopDetected ? "try_alternative_action" : nil) }
}

private final class BridgeState: @unchecked Sendable {
    private let condition = NSCondition()
    private var queue: [BridgeCommand] = []
    private var results: [String: BridgeResult] = [:]
    private var lastActivity: Date?
    /// El runner se considera conectado cuando pide su primer comando, no cuando el gateway
    /// registra el puente: entre una cosa y otra `xcodebuild` tarda decenas de segundos.
    private var runnerAttached = false

    func enqueue(_ command: BridgeCommand) { condition.lock(); queue.append(command); lastActivity = Date(); condition.signal(); condition.unlock() }
    func poll() -> BridgeCommand? { condition.lock(); defer { condition.unlock() }; lastActivity = Date(); runnerAttached = true; return queue.isEmpty ? nil : queue.removeFirst() }
    func complete(_ result: BridgeResult) { condition.lock(); results[result.commandID] = result; lastActivity = Date(); condition.broadcast(); condition.unlock() }
    func status() -> BridgeStatus { condition.lock(); defer { condition.unlock() }; return BridgeStatus(registered: true, pendingCommands: queue.count, lastActivity: lastActivity, runnerAttached: runnerAttached) }
    func execute(_ command: BridgeCommand) throws -> Data? {
        // Sin runner al otro lado la acción solo puede agotar el timeout. Fallar de inmediato
        // con un motivo accionable le ahorra al agente treinta segundos de silencio por
        // comando y le dice exactamente qué esperar.
        condition.lock(); let attached = runnerAttached; condition.unlock()
        guard attached else { throw ScoutError.invalidRequest("xctest_runner_starting: el runner todavía no atiende comandos; espera a que readiness deje de reportar este bloqueo") }
        enqueue(command); condition.lock(); let deadline = Date().addingTimeInterval(30)
        while results[command.id] == nil && condition.wait(until: deadline) {}
        let result = results.removeValue(forKey: command.id); condition.unlock()
        guard let result else { throw ScoutError.commandFailed("Timeout esperando respuesta de XCTest") }
        let message = result.error ?? "XCTest rechazó la acción"
        // Un selector que no resuelve es `no such element`, no un fallo genérico: de esa
        // distinción dependen la respuesta W3C (404), la autocuración de selectores y la
        // categoría con la que se aprende del fallo.
        guard result.success else { throw result.errorCode == 8 ? ScoutError.noSuchElement(message) : ScoutError.commandFailed(message) }
        return result.payloadBase64.flatMap { Data(base64Encoded: $0) }
    }
}

private final class WebViewState: @unchecked Sendable {
    private let condition = NSCondition()
    private var availableContexts: [String] = []
    private var selectedContext = "NATIVE_APP"
    private var queue: [WebViewCommand] = []
    private var results: [String: WebViewResult] = [:]

    func register(contexts: [String]) {
        condition.lock(); availableContexts = Array(Set(availableContexts + contexts)).sorted(); condition.unlock()
    }
    func contexts() -> [String] { condition.lock(); defer { condition.unlock() }; return availableContexts }
    func currentContext() -> String { condition.lock(); defer { condition.unlock() }; return selectedContext }
    func setContext(_ context: String) throws {
        condition.lock(); defer { condition.unlock() }
        guard context == "NATIVE_APP" || availableContexts.contains(context) else { throw ScoutError.unsupported("Context is not available: \(context)") }
        selectedContext = context
    }
    func poll() -> WebViewCommand? { condition.lock(); defer { condition.unlock() }; return queue.isEmpty ? nil : queue.removeFirst() }
    func complete(_ result: WebViewResult) { condition.lock(); results[result.commandID] = result; condition.broadcast(); condition.unlock() }
    func execute(_ command: WebViewCommand, timeout: Double = 30) throws -> String? {
        condition.lock(); queue.append(command); condition.signal(); let deadline = Date().addingTimeInterval(timeout)
        while results[command.id] == nil && condition.wait(until: deadline) {}
        let result = results.removeValue(forKey: command.id); condition.unlock()
        guard let result else { throw ScoutError.commandFailed("Timeout esperando respuesta del adaptador WebView") }
        guard result.success else { throw ScoutError.commandFailed(result.error ?? "El adaptador WebView rechazó el script") }
        return result.valueJSON
    }
}
