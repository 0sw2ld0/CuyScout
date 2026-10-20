import XCTest
@testable import CuyScoutCore

/// Fragmentos: lo escrito nunca llega a disco y las credenciales se resuelven por alias al ejecutar.
final class SessionFragmentStoreTests: XCTestCase {
    private let password = ScoutSelector(strategy: .accessibilityIdentifier, value: "bcp-input-1")
    private let creds: [String: [String: String]] = [
        "demo_user": ["password_ios": "ios-secret-1", "password_android": "android-secret-1"],
        "otro": ["password_android": "android-secret-2"],
    ]
    private func project() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("frag-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testNamesAreRestrictedToSafeFileNames() {
        for ok in ["login", "login-2", "a_b", "x"] { XCTAssertNoThrow(try FragmentStore.validate(name: ok), ok) }
        for bad in ["", "../x", "Login", "a/b", "a b", "-x", String(repeating: "a", count: 41), "login.json"] { XCTAssertThrowsError(try FragmentStore.validate(name: bad), bad) }
    }

    func testTypedTextBecomesAVariablePointingAtACredentialField() throws {
        let steps: [ScoutAction] = [.tapElement(.init(strategy: .label, value: "Ingresar")), .typeElement(password, text: "android-secret-1"), .tapElement(.init(strategy: .label, value: "Continuar"))]
        let result = try FragmentStore.prepare(steps: steps, credentials: creds, alias: nil, allowLiteral: false)
        XCTAssertEqual(result.steps[1], .typeElement(password, text: "<redacted>"))
        XCTAssertEqual(result.variables, ["1.text": "password_android"])
        XCTAssertEqual(result.alias, "demo_user", "el primer alias (por orden) que contiene el valor")
        XCTAssertEqual(result.steps[0], steps[0]); XCTAssertEqual(result.steps[2], steps[2])
    }

    func testAnExplicitAliasWinsAndUnknownTextIsNeverWrittenToDisk() throws {
        let typed: [ScoutAction] = [.typeElement(password, text: "android-secret-2")]
        XCTAssertEqual(try FragmentStore.prepare(steps: typed, credentials: creds, alias: "otro", allowLiteral: false).alias, "otro")
        XCTAssertThrowsError(try FragmentStore.prepare(steps: [.typeElement(password, text: "no-esta-en-ningun-lado")], credentials: creds, alias: nil, allowLiteral: false)) {
            let message = "\($0)"
            XCTAssertTrue(message.contains("paso 1") && message.contains("credentials.test.json"))
            XCTAssertFalse(message.contains("no-esta-en-ningun-lado"), "el error no repite el texto escrito")
        }
    }

    func testLiteralsAreOnlyAllowedForFieldsThatDoNotLookLikeSecrets() throws {
        let amount = ScoutSelector(strategy: .accessibilityIdentifier, value: "amount-input.input")
        let kept = try FragmentStore.prepare(steps: [.typeElement(amount, text: "10.00")], credentials: creds, alias: nil, allowLiteral: true)
        XCTAssertEqual(kept.steps, [.typeElement(amount, text: "10.00")]); XCTAssertTrue(kept.variables.isEmpty)
        let secretField = ScoutSelector(strategy: .accessibilityIdentifier, value: "login-password")
        XCTAssertThrowsError(try FragmentStore.prepare(steps: [.typeElement(secretField, text: "x")], credentials: creds, alias: nil, allowLiteral: true), "una clave nunca se guarda como literal")
        XCTAssertThrowsError(try FragmentStore.prepare(steps: [.sequence([.typeElement(password, text: "android-secret-1")])], credentials: creds, alias: nil, allowLiteral: false))
    }

    func testSaveLoadListAndOverwriteProtection() throws {
        let dir = try project(); defer { try? FileManager.default.removeItem(at: dir) }
        let fragment = SessionFragment(name: "login", platform: .android, bundleIdentifier: "com.example", defaultAlias: "demo_user", variables: ["1.text": "password_android"],
                                       exitCheck: .init(selector: .init(strategy: .label, value: "Transferir")), skipIfAlreadyDone: true,
                                       steps: [.tapElement(.init(strategy: .label, value: "Ingresar")), .typeElement(password, text: "<redacted>")])
        try FragmentStore.save(fragment, in: dir, overwrite: false)
        XCTAssertEqual(try FragmentStore.load(name: "login", platform: .android, in: dir).steps, fragment.steps)
        XCTAssertThrowsError(try FragmentStore.save(fragment, in: dir, overwrite: false)) { XCTAssertTrue("\($0)".contains("overwrite")) }
        XCTAssertNoThrow(try FragmentStore.save(fragment, in: dir, overwrite: true))
        XCTAssertEqual(FragmentStore.list(in: dir, platform: .android).map(\.name), ["login"])
        XCTAssertTrue(FragmentStore.list(in: dir, platform: .ios).isEmpty, "los fragmentos son por plataforma")
        XCTAssertThrowsError(try FragmentStore.load(name: "otro", platform: .android, in: dir)) { XCTAssertTrue("\($0)".contains("Disponibles: login")) }
        let raw = try String(contentsOf: dir.appendingPathComponent("fragments/login.android.json"), encoding: .utf8)
        XCTAssertFalse(raw.contains("android-secret"), "el archivo no contiene ninguna clave")
        XCTAssertTrue(raw.contains("<redacted>") && raw.contains("password_android"))
    }

    func testValuesComeFromTheChosenAliasAndErrorsNameFieldsNotValues() throws {
        let fragment = SessionFragment(name: "login", platform: .android, bundleIdentifier: nil, defaultAlias: "demo_user", variables: ["1.text": "password_android"],
                                       exitCheck: .init(selector: .init(strategy: .label, value: "x")), skipIfAlreadyDone: true, steps: [])
        XCTAssertEqual(try FragmentStore.values(for: fragment, alias: nil, credentials: creds), ["1.text": "android-secret-1"])
        XCTAssertEqual(try FragmentStore.values(for: fragment, alias: "otro", credentials: creds), ["1.text": "android-secret-2"])
        XCTAssertThrowsError(try FragmentStore.values(for: fragment, alias: "nadie", credentials: creds)) { XCTAssertTrue("\($0)".contains("Disponibles: demo_user, otro")) }
        XCTAssertThrowsError(try FragmentStore.values(for: fragment, alias: "demo_user", credentials: ["demo_user": ["password_ios": "x"]])) {
            let message = "\($0)"; XCTAssertTrue(message.contains("password_android")); XCTAssertFalse(message.contains("x\""))
        }
        let noVariables = SessionFragment(name: "n", platform: .ios, bundleIdentifier: nil, defaultAlias: nil, variables: [:], exitCheck: fragment.exitCheck, skipIfAlreadyDone: false, steps: [])
        XCTAssertEqual(try FragmentStore.values(for: noVariables, alias: nil, credentials: [:]), [:])
    }

    func testActionRoundTripsAndIsAnExecutablePlanStepWithAWarning() throws {
        let action = ScoutAction.runFragment(name: "login", alias: "demo_user")
        XCTAssertEqual(try JSONDecoder().decode(ScoutAction.self, from: JSONEncoder().encode(action)), action)
        XCTAssertEqual(try JSONDecoder().decode(ScoutAction.self, from: Data(#"{"type":"runFragment","name":"login"}"#.utf8)), .runFragment(name: "login", alias: nil))
        let plan = TestPlan(sessionID: "s", steps: [TestPlanStep(id: "step-1", action: action, success: true, durationMilliseconds: 1)], warnings: [])
        let result = TestPlanValidator.validate(plan)
        XCTAssertTrue(result.executable)
        XCTAssertTrue(result.warnings.contains { $0.contains("login") && $0.contains("Appium") })
    }
}
