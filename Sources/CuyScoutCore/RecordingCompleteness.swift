import Foundation

/// Whether a recording is a complete test: it may not end in a failed step. A failed read at the end changed
/// nothing, and a failed check at the end (an extra `assertText` the agent tried after the scenario finished)
/// is dropped too, but only when another check that passed verifies the end of the scenario: otherwise the
/// failed check may be the scenario itself failing. Replay only runs the steps that succeeded.
public enum RecordingCompleteness {
    static let reads: Set<String> = ["accessibilityTree", "accessibilityTreeWithOptions", "accessibilityDiff", "screenshot", "screenStatic", "visualDiff",
                                     "elementAttribute", "elementProperty", "elementDisplayed", "elementEnabled", "elementRect", "elementSelected", "elementName",
                                     "elementScreenshot", "findElement", "findElements", "findElementFromElement", "findElementsFromElement", "alertText",
                                     "activeElement", "listApps", "getClipboard"]
    static let checks: Set<String> = ["assertText", "assertVisible", "waitFor"]

    /// The position of the step that leaves the recording incomplete, or nil when it is complete.
    /// An empty recording returns -1.
    public static func incompleteStep(types: [String], success: [Bool]) -> Int? {
        var end = types.count
        while end > 0, !success[end - 1], reads.contains(types[end - 1]) || checks.contains(types[end - 1]) { end -= 1 }
        guard end > 0 else { return -1 }
        if !success[end - 1] { return end - 1 }
        guard (end..<types.count).contains(where: { checks.contains(types[$0]) }) else { return nil }
        let lastAction = (0..<end).last { !reads.contains(types[$0]) && !checks.contains(types[$0]) } ?? -1
        let verified = (lastAction + 1..<end).contains { checks.contains(types[$0]) && success[$0] }
        return verified ? nil : end
    }

    public static func incompleteStep(_ steps: [RecordedStep]) -> Int? {
        incompleteStep(types: steps.map { type(of: $0.action) }, success: steps.map(\.success))
    }

    static func type(of action: ScoutAction) -> String {
        guard let data = try? JSONEncoder().encode(action), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "" }
        return object["type"] as? String ?? ""
    }

    /// The same rule for the project scripts. Defines `incomplete(steps)`, which takes the steps as JSON
    /// objects (`action.type`, `success`) and returns the position of the offending step, -1 for an empty
    /// recording, or None.
    static let python = """
    READS = {\(reads.sorted().map { "\"\($0)\"" }.joined(separator: ", "))}
    CHECKS = {\(checks.sorted().map { "\"\($0)\"" }.joined(separator: ", "))}
    def incomplete(steps):
        kind = lambda s: s.get("action", {}).get("type")
        ok = lambda s: s.get("success", True)
        end = len(steps)
        while end and not ok(steps[end - 1]) and kind(steps[end - 1]) in READS | CHECKS: end -= 1
        if not end: return -1
        if not ok(steps[end - 1]): return end - 1
        if not any(kind(s) in CHECKS for s in steps[end:]): return None
        last = max([i for i in range(end) if kind(steps[i]) not in READS | CHECKS], default=-1)
        return None if any(kind(s) in CHECKS and ok(s) for s in steps[last + 1:end]) else end
    """
}
