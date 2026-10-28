import Foundation

/// Appium and Maestro do not know fragments: in what is exported, each `runFragment` that passed becomes the
/// fragment's steps plus its exit check. Typed credentials stay `<redacted>` (the fragment stores them that way)
/// and the local replay values supply them, keyed by the expanded path (`0.2.text`). The CuyScout artifact keeps
/// `runFragment`, so a login recorded again serves every test that uses it.
public enum FragmentExpansion {
    public static func expand(_ steps: [RecordedStep], platform: Device.Platform, project: URL?,
                              resolve: (ScoutAction, Int, SessionFragment, String?) throws -> ScoutAction = { action, _, _, _ in action }) throws -> [RecordedStep] {
        try steps.map { step in
            guard step.success, case .runFragment(let name, let alias) = step.action else { return step }
            guard let project else {
                throw ScoutError.invalidRequest("La prueba usa el fragmento «\(name)»: expórtala desde la carpeta del proyecto, donde está fragments/")
            }
            let fragment = try FragmentStore.load(name: name, platform: platform, in: project)
            var actions = try fragment.steps.enumerated().map { try resolve($0.element, $0.offset, fragment, alias) }
            if let check = fragment.exitCheck { actions.append(.waitFor(check.selector, timeout: check.timeout)) }
            return RecordedStep(index: step.index, action: .sequence(actions), startedAt: step.startedAt, durationMilliseconds: step.durationMilliseconds, success: true, error: nil)
        }
    }

    /// The project of an artifact saved as `<project>/output/<scenario>.cuyscout.json`.
    public static func project(forArtifact url: URL) -> URL? {
        let project = url.deletingLastPathComponent().deletingLastPathComponent()
        return FileManager.default.fileExists(atPath: project.appendingPathComponent("fragments").path) ? project : nil
    }
}
