import Foundation

public enum LessonScope: String, Codable, Sendable { case global, project, session }

public struct LearnedLesson: Codable, Sendable, Equatable {
    public let id: String
    public let scope: LessonScope
    public let projectKey: String?
    public let sessionID: String?
    public let title: String
    public let observation: String
    public let recommendation: String
    public let evidence: String?
    public let tags: [String]
    public let confidence: Double
    public let createdAt: Date
    public let updatedAt: Date
    public let occurrences: Int
    /// Veces que un intento usó la lección y aun así falló. Opcional para leer archivos anteriores.
    public let failures: Int?
    /// Debajo de este umbral la lección queda descartada: ya no se entrega a los agentes.
    public static let discardThreshold = 0.3
    public var isDiscarded: Bool { confidence < Self.discardThreshold }
    public init(id: String = UUID().uuidString, scope: LessonScope, projectKey: String? = nil, sessionID: String? = nil, title: String, observation: String, recommendation: String, evidence: String? = nil, tags: [String] = [], confidence: Double = 0.8, createdAt: Date = Date(), updatedAt: Date = Date(), occurrences: Int = 1, failures: Int = 0) {
        self.id = id; self.scope = scope; self.projectKey = projectKey; self.sessionID = sessionID; self.title = title; self.observation = observation; self.recommendation = recommendation; self.evidence = evidence; self.tags = tags; self.confidence = min(1, max(0, confidence)); self.createdAt = createdAt; self.updatedAt = updatedAt; self.occurrences = max(1, occurrences); self.failures = max(0, failures)
    }
}

public final class LessonStore: @unchecked Sendable {
    private let lock = NSLock()
    private let fileURL: URL
    private var lessons: [LearnedLesson] = []
    public init(fileURL: URL? = nil) {
        if let fileURL { self.fileURL = fileURL } else if let configured = ProcessInfo.processInfo.environment["CUYSCOUT_LESSONS_FILE"] { self.fileURL = URL(fileURLWithPath: configured) } else if ArtifactStore.isRunningTests { self.fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("cuyscout-test-lessons-\(ProcessInfo.processInfo.processIdentifier).json") } else { self.fileURL = (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory).appendingPathComponent("CuyScout/lessons.json") }
        load()
    }
    public func upsert(_ lesson: LearnedLesson) throws { let safeLesson = LessonRedactor.redact(lesson); lock.lock(); if let index = lessons.firstIndex(where: { $0.id == safeLesson.id }) { lessons[index] = safeLesson } else { lessons.append(safeLesson) }; let snapshot = lessons; lock.unlock(); try persist(snapshot) }
    @discardableResult public func record(_ candidate: LearnedLesson) throws -> LearnedLesson {
        let candidate = LessonRedactor.redact(candidate)
        lock.lock()
        let recorded: LearnedLesson
        if let index = lessons.firstIndex(where: { Self.sameIdentity($0, candidate) }) {
            let existing = lessons[index]
            recorded = LearnedLesson(
                id: existing.id,
                scope: existing.scope,
                projectKey: existing.projectKey,
                sessionID: existing.sessionID,
                title: candidate.title,
                observation: candidate.observation,
                recommendation: candidate.recommendation,
                evidence: candidate.evidence ?? existing.evidence,
                tags: Self.mergedTags(existing.tags, candidate.tags),
                // Una lección descartada por resultados no revive porque se la vuelva a proponer.
                confidence: existing.isDiscarded ? existing.confidence : min(1, max(existing.confidence, candidate.confidence) + 0.02),
                createdAt: existing.createdAt,
                updatedAt: Date(),
                occurrences: existing.occurrences + 1,
                failures: existing.failures ?? 0
            )
            lessons[index] = recorded
        } else {
            recorded = candidate
            lessons.append(candidate)
        }
        let snapshot = lessons
        lock.unlock()
        try persist(snapshot)
        return recorded
    }
    /// Resultado de aplicar la lección en un intento: si ayudó sube su confianza; si falló la baja
    /// y, bajo `discardThreshold`, deja de entregarse.
    @discardableResult public func feedback(id: String, helped: Bool) throws -> LearnedLesson? {
        lock.lock()
        guard let index = lessons.firstIndex(where: { $0.id == id }) else { lock.unlock(); return nil }
        let l = lessons[index]
        let updated = LearnedLesson(id: l.id, scope: l.scope, projectKey: l.projectKey, sessionID: l.sessionID, title: l.title,
            observation: l.observation, recommendation: l.recommendation, evidence: l.evidence, tags: l.tags,
            confidence: helped ? min(1, l.confidence + 0.15) : max(0, l.confidence - 0.25), createdAt: l.createdAt,
            updatedAt: Date(), occurrences: helped ? l.occurrences + 1 : l.occurrences, failures: (l.failures ?? 0) + (helped ? 0 : 1))
        lessons[index] = updated
        let snapshot = lessons
        lock.unlock()
        try persist(snapshot)
        return updated
    }
    public func list() -> [LearnedLesson] { lock.lock(); defer { lock.unlock() }; return lessons.sorted { $0.updatedAt > $1.updatedAt } }
    public func search(query: String? = nil, tags: [String] = [], scope: LessonScope? = nil, includeDiscarded: Bool = false) -> [LearnedLesson] {
        let words = Self.normalized(query ?? "").split(separator: " ").map(String.init)
        let requestedTags = Set(tags.map(Self.normalized).filter { !$0.isEmpty })
        lock.lock(); let snapshot = lessons; lock.unlock()
        return snapshot.filter { lesson in
            if !includeDiscarded && lesson.isDiscarded { return false }
            if let scope, lesson.scope != scope { return false }
            let lessonTags = Set(lesson.tags.map(Self.normalized))
            if !requestedTags.isEmpty && requestedTags.isDisjoint(with: lessonTags) { return false }
            guard !words.isEmpty else { return true }
            let corpus = Self.normalized(([lesson.title, lesson.observation, lesson.recommendation] + lesson.tags).joined(separator: " "))
            return words.allSatisfy { corpus.contains($0) }
        }.sorted {
            if $0.occurrences != $1.occurrences { return $0.occurrences > $1.occurrences }
            if $0.confidence != $1.confidence { return $0.confidence > $1.confidence }
            return $0.updatedAt > $1.updatedAt
        }
    }
    private func load() { lock.lock(); defer { lock.unlock() }; guard let data = try? Data(contentsOf: fileURL), let value = try? JSONDecoder().decode([LearnedLesson].self, from: data) else { return }; lessons = value }
    private func persist(_ value: [LearnedLesson]) throws { let directory = fileURL.deletingLastPathComponent(); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true); try JSONEncoder().encode(value).write(to: fileURL, options: .atomic) }
    private static func sameIdentity(_ lhs: LearnedLesson, _ rhs: LearnedLesson) -> Bool { lhs.scope == rhs.scope && lhs.projectKey == rhs.projectKey && lhs.sessionID == rhs.sessionID && normalized(lhs.title) == normalized(rhs.title) }
    private static func normalized(_ value: String) -> String { value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).split(whereSeparator: { $0.isWhitespace }).joined(separator: " ") }
    private static func mergedTags(_ lhs: [String], _ rhs: [String]) -> [String] { Dictionary(grouping: lhs + rhs, by: normalized).compactMap { key, values in key.isEmpty ? nil : values.first }.sorted { normalized($0) < normalized($1) } }
}
