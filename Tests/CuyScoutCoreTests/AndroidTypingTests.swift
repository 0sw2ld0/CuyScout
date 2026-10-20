import XCTest
@testable import CuyScoutCore

/// Escribir por adb cuando el campo no es editable para accesibilidad (p. ej. un monto en React Native).
final class AndroidTypingTests: XCTestCase {
    private final class Recorder: @unchecked Sendable {
        var keyboard: Bool, commands: [String] = []
        init(keyboard: Bool) { self.keyboard = keyboard }
        func execute(_ command: AndroidController.Command) throws -> AndroidController.Output {
            let shell = command.arguments.last ?? ""; commands.append(shell)
            if shell.contains("'dumpsys' 'input_method'") { return .init(stdout: Data((keyboard ? "  mInputShown=true\n" : "  mInputShown=false\n").utf8)) }
            if shell.contains("KEYCODE_BACK") { keyboard = false }
            return .init()
        }
    }
    private let phone = Device(id: "9tlvcmpfln75zpeq", name: "Redmi", runtime: "Android 14", state: "Booted", isAvailable: true, kind: .physical, platform: .android)
    private func controller(_ recorder: Recorder) -> AndroidController {
        AndroidController(environment: ["ANDROID_HOME": "/sdk"], homeDirectory: "/h", isExecutable: { $0 == "/sdk/platform-tools/adb" }, executor: recorder.execute)
    }

    func testTypesIntoTheFocusedFieldAndClosesTheKeyboardWithBack() throws {
        let recorder = Recorder(keyboard: true)
        XCTAssertTrue(try controller(recorder).typeIntoFocusedField("10.00", on: phone))
        XCTAssertTrue(recorder.commands.contains("'input' 'text' '10.00'"))
        XCTAssertEqual(recorder.commands.filter { $0.contains("KEYCODE_BACK") }.count, 1)
        XCTAssertFalse(recorder.commands.contains { $0.contains("KEYCODE_ENTER") }, "Enter podría enviar un formulario")
    }

    func testDoesNotSendBackWhenTheKeyboardAlreadyClosedItself() throws {
        final class SelfClosing: @unchecked Sendable {
            var shownChecks = 0, commands: [String] = []
            func execute(_ c: AndroidController.Command) throws -> AndroidController.Output {
                let shell = c.arguments.last ?? ""; commands.append(shell)
                if shell.contains("'dumpsys' 'input_method'") { shownChecks += 1; return .init(stdout: Data((shownChecks == 1 ? "mInputShown=true" : "mInputShown=false").utf8)) }
                return .init()
            }
        }
        let fake = SelfClosing()
        let c = AndroidController(environment: ["ANDROID_HOME": "/sdk"], homeDirectory: "/h", isExecutable: { $0 == "/sdk/platform-tools/adb" }, executor: fake.execute)
        XCTAssertTrue(try c.typeIntoFocusedField("5", on: phone))
        XCTAssertFalse(fake.commands.contains { $0.contains("KEYCODE_BACK") }, "Atrás con el teclado ya cerrado haría navegar a la app")
    }

    func testDoesNothingWithoutAnOpenKeyboard() throws {
        let recorder = Recorder(keyboard: false)
        XCTAssertFalse(try controller(recorder).typeIntoFocusedField("10.00", on: phone))
        XCTAssertFalse(recorder.commands.contains { $0.contains("'input'") })
    }

    func testInputTextArgumentEscapesSpacesAndRejectsWhatItCannotSend() {
        XCTAssertEqual(AndroidController.inputTextArgument("10.00"), "10.00")
        XCTAssertEqual(AndroidController.inputTextArgument("Juan Perez"), "Juan%sPerez")
        XCTAssertNil(AndroidController.inputTextArgument(""))
        XCTAssertNil(AndroidController.inputTextArgument("niño"), "input text no envía no ASCII")
        XCTAssertNil(AndroidController.inputTextArgument("50%sOff"), "%s se tomaría como espacio")
        XCTAssertNil(AndroidController.inputTextArgument("a\nb"))
    }

    func testRefusesToTypeNonAsciiOrSecretLookingFieldsThroughAdb() throws {
        let recorder = Recorder(keyboard: true)
        XCTAssertFalse(try controller(recorder).typeIntoFocusedField("niño", on: phone))
        XCTAssertFalse(recorder.commands.contains { $0.contains("'input' 'text'") })
        for secret in ["login-password", "Clave de Internet", "cvv.input", "pin", "otp_code", "Contraseña"] {
            XCTAssertTrue(AndroidController.isSensitiveField(.init(strategy: .label, value: secret)), secret)
        }
        for plain in ["amount-input.input", "Ingrese el monto, monto en soles", "email", "search", "shipping-address"] {
            XCTAssertFalse(AndroidController.isSensitiveField(.init(strategy: .label, value: plain)), plain)
        }
    }

    func testKeyboardStateIsReadFromDumpsys() {
        XCTAssertTrue(AndroidController.keyboardShown(from: "  mInputShown=true\n"))
        XCTAssertFalse(AndroidController.keyboardShown(from: "  mInputShown=false\n"))
        XCTAssertFalse(AndroidController.keyboardShown(from: ""))
    }
}
