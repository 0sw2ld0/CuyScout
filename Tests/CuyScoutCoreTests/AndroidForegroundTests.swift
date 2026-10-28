import XCTest
@testable import CuyScoutCore

/// MIUI deniega que el runner abra la app desde segundo plano: el gateway la trae al frente por adb.
final class AndroidForegroundTests: XCTestCase {
    private final class Recorder: @unchecked Sendable {
        var focus: String, commands: [[String]] = []
        init(focus: String) { self.focus = focus }
        func execute(_ command: AndroidController.Command) throws -> AndroidController.Output {
            commands.append(command.arguments)
            let shell = command.arguments.last ?? ""
            if shell.contains("'dumpsys' 'window'") { return .init(stdout: Data(focus.utf8)) }
            if shell.contains("'am' 'start'") || shell.contains("'monkey'") { return .init(stdout: Data("Starting: Intent".utf8)) }
            return .init()
        }
        var launches: [String] { commands.map { $0.last ?? "" }.filter { $0.contains("'am' 'start'") || $0.contains("'monkey'") } }
    }
    private let phone = Device(id: "9tlvcmpfln75zpeq", name: "Redmi", runtime: "Android 14", state: "Booted", isAvailable: true, kind: .physical, platform: .android)
    private func controller(_ recorder: Recorder) -> AndroidController {
        AndroidController(environment: ["ANDROID_HOME": "/sdk"], homeDirectory: "/h", isExecutable: { $0 == "/sdk/platform-tools/adb" }, executor: recorder.execute)
    }
    private let launcher = "  mCurrentFocus=Window{97f65e0 u0 com.miui.home/com.miui.home.launcher.Launcher}\n"

    func testForegroundPackageIsReadFromTheFocusedWindow() {
        XCTAssertEqual(AndroidController.foregroundPackage(from: launcher), "com.miui.home")
        XCTAssertEqual(AndroidController.foregroundPackage(from: "x\n  mCurrentFocus=Window{9837ba3 u0 com.bcp.bank.bcp.dev/com.bcp.bank.authentication.presentation.AuthenticationActivity}\ny"), "com.bcp.bank.bcp.dev")
        XCTAssertEqual(AndroidController.foregroundPackage(from: "  mCurrentFocus=Window{1 u10 com.work.app/.Main}"), "com.work.app")
        XCTAssertNil(AndroidController.foregroundPackage(from: "  mCurrentFocus=null\n"))
        XCTAssertNil(AndroidController.foregroundPackage(from: "sin dato"))
        XCTAssertNil(AndroidController.foregroundPackage(from: "  mCurrentFocus=Window{1 u0 NotificationShade}"))
    }

    func testLaunchesTheAppFromAdbWhenTheLauncherHasTheFocus() throws {
        let recorder = Recorder(focus: launcher)
        XCTAssertTrue(try controller(recorder).bringToForeground("com.bcp.bank.bcp.dev", activity: nil, on: phone, settle: 0))
        XCTAssertEqual(recorder.launches.count, 1)
        XCTAssertTrue(recorder.launches[0].contains("'monkey' '-p' 'com.bcp.bank.bcp.dev'"))
    }

    func testUsesTheConfiguredActivityAndExpandsARelativeOne() throws {
        let recorder = Recorder(focus: launcher)
        _ = try controller(recorder).bringToForeground("com.example.wallet", activity: ".LoginActivity", on: phone, settle: 0)
        XCTAssertEqual(recorder.launches, ["'am' 'start' '-W' '--user' '0' '-n' 'com.example.wallet/com.example.wallet.LoginActivity'"])
    }

    func testDoesNothingWhenTheAppAlreadyHasTheFocusOrTheFocusIsUnknown() throws {
        let inFront = Recorder(focus: "  mCurrentFocus=Window{1 u0 com.bcp.bank.bcp.dev/.Main}")
        XCTAssertFalse(try controller(inFront).bringToForeground("com.bcp.bank.bcp.dev", activity: nil, on: phone, settle: 0))
        XCTAssertTrue(inFront.launches.isEmpty)
        let unknown = Recorder(focus: "  mCurrentFocus=null")
        XCTAssertFalse(try controller(unknown).bringToForeground("com.bcp.bank.bcp.dev", activity: nil, on: phone, settle: 0))
        XCTAssertTrue(unknown.launches.isEmpty, "sin un dato fiable no se debe tocar el teléfono")
    }

    func testWaitsForTheAppToAppearBeforeLaunchingItself() throws {
        let recorder = Recorder(focus: launcher)
        let wait = Thread { Thread.sleep(forTimeInterval: 0.3); recorder.focus = "  mCurrentFocus=Window{1 u0 com.example.wallet/.Main}" }
        wait.start()
        XCTAssertFalse(try controller(recorder).bringToForeground("com.example.wallet", activity: nil, on: phone, settle: 3))
        XCTAssertTrue(recorder.launches.isEmpty, "si el runner sí la abrió, no se lanza otra vez")
    }

    func testInvalidActionMessageSaysWhatWasReceivedAndTheValidShapes() {
        let tapWithSelector = AgentContract.invalidActionMessage(for: ["type": "tap", "selector": ["strategy": "label", "value": "Ingresar"]])
        XCTAssertTrue(tapWithSelector.contains("\"tap\"") && tapWithSelector.contains("{type:tapElement,selector"))
        XCTAssertFalse(tapWithSelector.hasPrefix("Invalid HTTP action arguments: copy the observed action exactly; typeElement"))
        XCTAssertTrue(AgentContract.invalidActionMessage(for: ["type": "tapElement"]).contains("tapElement requires selector"))
        XCTAssertTrue(AgentContract.invalidActionMessage(for: ["type": "typeElement"]).contains("text:string"))
        XCTAssertTrue(AgentContract.invalidActionMessage(for: ["type": "scroll", "direction": "down"]).contains("{type:scroll,x:0,y:400}"), "un scroll lleva desplazamiento, no dirección")
        for message in [tapWithSelector, AgentContract.invalidActionMessage(for: ["type": "swipe"])] {
            XCTAssertTrue(message.contains("Valid shapes") && message.contains("No action performed"))
        }
    }
}
