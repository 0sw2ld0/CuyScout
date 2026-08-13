import Foundation

public enum LessonRelevance {
    /// Scores a lesson against the compact signals observed in the current step.
    /// Matching tags are intentionally weighted more than recency so a rare but
    /// highly applicable lesson is not hidden by generic history.
    public static func score(_ lesson: LearnedLesson, contextTags: Set<String>) -> Int {
        let tags = Set(lesson.tags.map { $0.lowercased() })
        let matches = tags.intersection(contextTags).count
        let scopeWeight: Int = lesson.scope == .session ? 3 : lesson.scope == .project ? 2 : 1
        return matches * 100 + scopeWeight * 10 + min(lesson.occurrences, 10) + Int(lesson.confidence * 10)
    }
}
