// Re-export saved recordings with the CURRENT product exporter, without repeating app actions.
// Compile against CuyScoutCore; arguments: recording.json output.ts
import Foundation
import CuyScoutCore

let saved = try JSONDecoder().decode(RecordedSession.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
let regenerated = RecordedSession(sessionID: saved.sessionID, startedAt: saved.startedAt,
    stoppedAt: saved.stoppedAt, steps: saved.steps)
let output = URL(fileURLWithPath: CommandLine.arguments[2])
guard !FileManager.default.fileExists(atPath: output.path) else { fatalError("Refusing to overwrite an existing export") }
try regenerated.generatedAppiumTypeScript.write(to: output, atomically: true, encoding: .utf8)
