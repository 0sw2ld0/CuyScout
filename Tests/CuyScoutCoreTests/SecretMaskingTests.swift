import XCTest
@testable import CuyScoutCore

/// Lo que lee la pantalla (observe, árbol, diagnósticos) nunca devuelve una clave en claro.
final class SecretMaskingTests: XCTestCase {
    private func project(_ credentials: [String: [String: String]]) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("secret-mask-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("fixtures"), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: credentials).write(to: root.appendingPathComponent("fixtures/credentials.test.json"))
        try Data("{}".utf8).write(to: root.appendingPathComponent(".cuyscout-project.json"))
        return root
    }

    func testOnlySecretCredentialFieldsAreMasked() {
        XCTAssertTrue(ScoutEngine.isSecretField("password_android"))
        XCTAssertTrue(ScoutEngine.isSecretField("Clave"))
        XCTAssertTrue(ScoutEngine.isSecretField("otp"))
        XCTAssertFalse(ScoutEngine.isSecretField("usuario"))
        XCTAssertFalse(ScoutEngine.isSecretField("documento"))
        XCTAssertEqual(ScoutEngine.masking("campo-1: : Secreta123", secrets: ["Secreta123"]), "campo-1: : ••••")
    }

    func testTreeHidesSecureValuesAndCredentialSecretsEvenInPlainFields() throws {
        let root = try project(["demo_user": ["usuario": "demo", "password_android": "Secreta123"]])
        defer { try? FileManager.default.removeItem(at: root) }
        let engine = ScoutEngine(artifactStore: ArtifactStore(directory: root.appendingPathComponent("store")))
        let session = try engine.createSession(deviceID: nil, bundleIdentifier: "com.example.app")
        try engine.setProjectDirectory(sessionID: session.id, path: root.path)
        let tree = try JSONSerialization.data(withJSONObject: ["elements": [
            ["type": "securetextfield", "identifier": "pin", "value": "9876"],
            ["type": "textfield", "identifier": "campo-1", "value": "Secreta123"],
            ["type": "textfield", "identifier": "user", "value": "demo"],
            ["type": "statictext", "label": "S/ 15.00"]]])
        let masked = String(decoding: engine.maskSecrets(in: tree, sessionID: session.id), as: UTF8.self)
        XCTAssertFalse(masked.contains("9876"), "campo de contraseña")
        XCTAssertFalse(masked.contains("Secreta123"), "clave de las credenciales en un campo no marcado")
        XCTAssertTrue(masked.contains("demo"), "el usuario no es un secreto")
        XCTAssertTrue(masked.contains("15.00"))
        XCTAssertEqual(masked.components(separatedBy: ScoutEngine.secretMask).count - 1, 2)
    }

    func testANumericTokenIsMaskedOnlyInsideTexts() throws {
        let root = try project(["demo_user": ["token_fisico": "123456"]])
        defer { try? FileManager.default.removeItem(at: root) }
        let engine = ScoutEngine(artifactStore: ArtifactStore(directory: root.appendingPathComponent("store")))
        let session = try engine.createSession(deviceID: nil, bundleIdentifier: "com.example.app")
        try engine.setProjectDirectory(sessionID: session.id, path: root.path)
        let tree = try JSONSerialization.data(withJSONObject: ["capturedAt": 1234567, "elements": [["type": "textfield", "value": "123456", "x": 123456]]])
        let masked = try XCTUnwrap(JSONSerialization.jsonObject(with: engine.maskSecrets(in: tree, sessionID: session.id)) as? [String: Any], "el árbol sigue siendo JSON")
        let element = try XCTUnwrap((masked["elements"] as? [[String: Any]])?.first)
        XCTAssertEqual(element["value"] as? String, ScoutEngine.secretMask)
        XCTAssertEqual(element["x"] as? Int, 123456, "un número no es el token")
        XCTAssertEqual(masked["capturedAt"] as? Int, 1234567)
    }

    func testAppiumFailureEvidenceHidesWhatTheReplayTyped() {
        let recording = RecordedSession(sessionID: "s", startedAt: Date(), stoppedAt: nil, steps: [
            RecordedStep(index: 0, action: .tapElement(.init(strategy: .accessibilityIdentifier, value: "ok")), startedAt: Date(), durationMilliseconds: 1, success: true)])
        let source = recording.generatedAppiumTypeScript
        XCTAssertTrue(source.contains("const hide = (value: string) => typed.reduce((text, secret) => text.split(secret).join('••••'), value);"))
        XCTAssertTrue(source.contains("!/^\\d+[.,]\\d{2}$/.test(value)"), "los importes siguen visibles")
    }
}
