import XCTest
@testable import CuyScoutCore

final class ProjectAuthoringTests: XCTestCase {
    private func project() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("auth-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: credenciales

    func testCredentialsRoundTripWithOwnerOnlyPermissions() throws {
        let dir = try project(); defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertEqual(try CredentialsStore.load(in: dir), CredentialsStore.Document(), "sin archivo: documento vacío")
        let aliases = ["demo_user": ["password_android": "a-1", "password_ios": "i-1"], "otro": ["password_android": "a-2"]]
        try CredentialsStore.save(aliases, in: dir)
        XCTAssertEqual(try CredentialsStore.load(in: dir).aliases, aliases)
        let permissions = try FileManager.default.attributesOfItem(atPath: CredentialsStore.url(in: dir).path)[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o600, "solo el dueño puede leer las credenciales")
    }

    func testNamesAreValidatedAndAnUnreadableFileIsNeverOverwritten() throws {
        let dir = try project(); defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertThrowsError(try CredentialsStore.save(["../x": ["a": "b"]], in: dir))
        XCTAssertThrowsError(try CredentialsStore.save(["ok": ["campo con espacio": "b"]], in: dir))
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("fixtures"), withIntermediateDirectories: true)
        let odd = #"{"demo_user":{"password":"x","reintentos":3},"nota":"hola"}"#
        try Data(odd.utf8).write(to: CredentialsStore.url(in: dir))
        let loaded = try CredentialsStore.load(in: dir)
        XCTAssertTrue(loaded.hasUnsupportedValues, "números y valores sueltos no son alias → campo → texto")
        XCTAssertThrowsError(try CredentialsStore.save(["demo_user": ["password": "y"]], in: dir)) { XCTAssertTrue("\($0)".contains("edítalo a mano")) }
        XCTAssertEqual(try String(contentsOf: CredentialsStore.url(in: dir), encoding: .utf8), odd, "el archivo quedó intacto")
    }

    func testGitIgnoreCheckAndExplicitAddition() throws {
        let dir = try project(); defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertFalse(CredentialsStore.isGitIgnored(in: dir))
        try Data("node_modules".utf8).write(to: dir.appendingPathComponent(".gitignore"))
        XCTAssertFalse(CredentialsStore.isGitIgnored(in: dir))
        try CredentialsStore.addToGitIgnore(in: dir)
        XCTAssertTrue(CredentialsStore.isGitIgnored(in: dir))
        let text = try String(contentsOf: dir.appendingPathComponent(".gitignore"), encoding: .utf8)
        XCTAssertEqual(text, "node_modules\nfixtures/credentials.test.json\n", "conserva lo que había y añade una línea")
        try CredentialsStore.addToGitIgnore(in: dir)
        XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent(".gitignore"), encoding: .utf8), text, "no se duplica")
    }

    // MARK: escenarios

    func testTemplateWithAndWithoutALoginFragment() {
        let with = FeatureFile.template(featureTitle: "Transferencia", scenarioTitle: "Entre mis cuentas", fragment: "login")
        XCTAssertTrue(with.hasPrefix("@fragment:login\nFeature: Transferencia"))
        XCTAssertTrue(with.contains("Background:\n    Given el usuario ha iniciado sesión"))
        let without = FeatureFile.template(featureTitle: "Transferencia", scenarioTitle: "Entre mis cuentas", fragment: nil)
        XCTAssertTrue(without.hasPrefix("Feature: Transferencia")); XCTAssertFalse(without.contains("Background"))
        XCTAssertFalse(FeatureFile.problems(in: without.replacingOccurrences(of: "describe aquí la acción", with: "toco Transferir").replacingOccurrences(of: "describe aquí lo que debes ver", with: "veo el monto")).contains { $0.contains("Feature") || $0.contains("Scenario") })
    }

    func testTheFragmentTagIsReadSetChangedAndRemovedWithoutTouchingTheRest() {
        let text = "@smoke\nFeature: Algo\n\n  Scenario: Uno\n    Given x\n"
        XCTAssertNil(FeatureFile.fragment(in: text))
        let tagged = FeatureFile.settingFragment("login", in: text)
        XCTAssertEqual(tagged, "@smoke\n@fragment:login\nFeature: Algo\n\n  Scenario: Uno\n    Given x\n")
        XCTAssertEqual(FeatureFile.fragment(in: tagged), "login")
        let changed = FeatureFile.settingFragment("login-2", in: tagged)
        XCTAssertEqual(FeatureFile.fragment(in: changed), "login-2")
        XCTAssertEqual(changed.components(separatedBy: "@fragment:").count, 2, "una sola etiqueta")
        XCTAssertEqual(FeatureFile.settingFragment(nil, in: changed), text, "quitarla devuelve el archivo original")
        XCTAssertEqual(FeatureFile.settingFragment("login", in: "sin feature"), "sin feature")
        XCTAssertNil(FeatureFile.fragment(in: "Feature: A\n  # @fragment:login\n  Scenario: S\n"), "una etiqueta fuera de las líneas previas a Feature no cuenta")
    }

    func testProblemsAndSaveRules() throws {
        XCTAssertEqual(FeatureFile.problems(in: "hola").count, 2)
        XCTAssertTrue(FeatureFile.problems(in: FeatureFile.template(featureTitle: "A", scenarioTitle: "B", fragment: nil)).contains { $0.contains("plantilla") })
        let dir = try project(); defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertThrowsError(try FeatureFile.save("x", name: "../escape", in: dir, overwrite: false))
        XCTAssertThrowsError(try FeatureFile.save("x", name: "Mayusculas", in: dir, overwrite: false))
        try FeatureFile.save("Feature: A\n  Scenario: B\n", name: "transferencia-propia", in: dir, overwrite: false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("features/transferencia-propia.feature").path))
        XCTAssertThrowsError(try FeatureFile.save("otro", name: "transferencia-propia", in: dir, overwrite: false)) { XCTAssertTrue("\($0)".contains("Ya existe")) }
        XCTAssertNoThrow(try FeatureFile.save("Feature: A2\n  Scenario: B\n", name: "transferencia-propia", in: dir, overwrite: true))
    }

    func testDeletingAFragmentRemovesOnlyThatPlatformsFile() throws {
        let dir = try project(); defer { try? FileManager.default.removeItem(at: dir) }
        let check = SessionFragment.Check(selector: .init(strategy: .label, value: "x"))
        for platform in [Device.Platform.android, .ios] {
            try FragmentStore.save(SessionFragment(name: "login", platform: platform, bundleIdentifier: nil, defaultAlias: nil, variables: [:], exitCheck: check, skipIfAlreadyDone: true, steps: []), in: dir, overwrite: false)
        }
        try FragmentStore.delete(name: "login", platform: .android, in: dir)
        XCTAssertEqual(FragmentStore.list(in: dir).map(\.platform), [.ios])
        XCTAssertNoThrow(try FragmentStore.delete(name: "login", platform: .android, in: dir), "borrar lo que no existe no falla")
        XCTAssertThrowsError(try FragmentStore.delete(name: "../x", platform: .ios, in: dir))
    }
}
