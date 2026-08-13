import Foundation

public enum LessonRedactor {
    public static func redact(_ lesson: LearnedLesson) -> LearnedLesson {
        LearnedLesson(id: lesson.id, scope: lesson.scope, projectKey: lesson.projectKey, sessionID: lesson.sessionID, title: redact(lesson.title), observation: redact(lesson.observation), recommendation: redact(lesson.recommendation), evidence: lesson.evidence.map(redact), tags: lesson.tags.map(redact), confidence: lesson.confidence, createdAt: lesson.createdAt, updatedAt: lesson.updatedAt, occurrences: lesson.occurrences)
    }

    public static func redact(_ text: String) -> String {
        var value = text
        let patterns = [
            #"\b[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}\b"#,
            #"(?i)\b(?:bearer\s+)[A-Z0-9._~+/\-]+=*"#,
            #"(?i)\b(?:password|passwd|token|secret|api[_-]?key)\s*[:=]\s*[^\s,;]+"#,
            #"\b\d{8,}\b"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            value = regex.stringByReplacingMatches(in: value, range: NSRange(value.startIndex..., in: value), withTemplate: "<redacted>")
        }
        return value
    }
}
