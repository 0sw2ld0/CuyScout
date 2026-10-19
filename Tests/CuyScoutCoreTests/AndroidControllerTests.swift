import XCTest
@testable import CuyScoutCore

final class AndroidControllerTests: XCTestCase {
    private let emulator = Device(id: "emulator-5554", name: "Pixel_API_35", runtime: "Android 15", state: "Booted", platform: .android)
    private let physical = Device(id: "FAKE_USB_01", name: "Demo Phone", runtime: "Android 15", state: "Booted", kind: .physical, platform: .android)

    private func fixture(_ name: String) throws -> String {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "txt", subdirectory: "Fixtures/android"))
        return try String(contentsOf: url, encoding: .utf8)
    }
    private func controller(_ fake: AndroidExecutor = AndroidExecutor()) -> AndroidController {
        AndroidController(environment: ["ANDROID_HOME": "/sdk"], homeDirectory: "/fake-home", isExecutable: { ["/sdk/platform-tools/adb", "/sdk/emulator/emulator", "/sdk/cmdline-tools/latest/bin/avdmanager"].contains($0) }, executor: fake.execute)
    }
    private func shell(_ arguments: [String]) -> String { arguments.map(AndroidController.quote).joined(separator: " ") }

    func testToolDiscoveryHonorsSDKVariablesThenPATHThenStudio() {
        let all: Set<String> = ["/primary/platform-tools/adb", "/secondary/platform-tools/adb", "/bin/adb", "/fake-home/Library/Android/sdk/platform-tools/adb"]
        for (env, expected) in [
            (["ANDROID_HOME": "/primary", "ANDROID_SDK_ROOT": "/secondary", "PATH": "/bin"], "/primary/platform-tools/adb"),
            (["ANDROID_HOME": "/missing", "ANDROID_SDK_ROOT": "/secondary", "PATH": "/bin"], "/secondary/platform-tools/adb"),
            (["PATH": "/missing:/bin"], "/bin/adb"),
            ([:], "/fake-home/Library/Android/sdk/platform-tools/adb")
        ] {
            let c = AndroidController(environment: env, homeDirectory: "/fake-home", isExecutable: { all.contains($0) })
            XCTAssertEqual(c.toolPath("adb"), expected)
        }
        XCTAssertNil(controller().toolPath("unknown"))
        XCTAssertEqual(controller().toolPath("emulator"), "/sdk/emulator/emulator")
        XCTAssertEqual(controller().toolPath("avdmanager"), "/sdk/cmdline-tools/latest/bin/avdmanager")
    }

    /// Un .app abierto desde Finder no hereda el PATH ni ANDROID_HOME del shell: solo ve /usr/bin:/bin.
    func testFinderEnvironmentStillFindsHomebrewAdb() {
        let finder = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
        for adb in ["/opt/homebrew/bin/adb", "/usr/local/bin/adb", "/opt/homebrew/share/android-commandlinetools/platform-tools/adb"] {
            let c = AndroidController(environment: finder, homeDirectory: "/fake-home", isExecutable: { $0 == adb })
            XCTAssertEqual(c.toolPath("adb"), adb)
        }
        let emulator = AndroidController(environment: finder, homeDirectory: "/fake-home", isExecutable: { $0 == "/opt/homebrew/share/android-commandlinetools/emulator/emulator" })
        XCTAssertNotNil(emulator.toolPath("emulator"))
        XCTAssertNil(AndroidController(environment: finder, homeDirectory: "/fake-home", isExecutable: { _ in false }).toolPath("adb"))
    }

    func testDestinationHintExplainsWhyNoPhoneShowsUp() {
        func phone(_ state: String) -> Device { Device(id: "R58", name: "Pixel", runtime: "Android 15", state: state == "device" ? "Booted" : state, isAvailable: state == "device", kind: .physical, platform: .android) }
        XCTAssertTrue(AndroidController.destinationHint(devices: [], adbFound: false, physical: true)!.contains("adb"))
        XCTAssertTrue(AndroidController.destinationHint(devices: [phone("unauthorized")], adbFound: true, physical: true)!.contains("autoriz"))
        XCTAssertTrue(AndroidController.destinationHint(devices: [phone("offline")], adbFound: true, physical: true)!.contains("offline"))
        XCTAssertTrue(AndroidController.destinationHint(devices: [], adbFound: true, physical: true)!.contains("Depuración USB"))
        XCTAssertNil(AndroidController.destinationHint(devices: [phone("device")], adbFound: true, physical: true))
    }

    func testMissingSDKDoctorGivesInstallationCommandsWithoutLaunchingProcesses() {
        let fake = AndroidExecutor()
        let c = AndroidController(environment: [:], homeDirectory: "/missing", isExecutable: { _ in false }, executor: fake.execute)
        let report = c.doctor()
        XCTAssertFalse(report.ready)
        XCTAssertTrue(report.recommendations.joined().contains("sdkmanager \"platform-tools\""))
        XCTAssertTrue(report.recommendations.joined().contains("avdmanager list avd"))
        XCTAssertTrue(fake.commands.isEmpty)
        XCTAssertThrowsError(try c.devices())
        XCTAssertTrue(fake.commands.isEmpty)
    }

    func testADBParserPreservesSerialStatusAndModel() throws {
        let parsed = AndroidController.adbDevices(from: try fixture("adb-devices"))
        XCTAssertEqual(parsed.count, 5)
        XCTAssertEqual(parsed[1].serial, "FAKE_USB_01")
        XCTAssertEqual(parsed[1].model, "Demo Phone")
        XCTAssertEqual(parsed[2].state, "unauthorized")
        XCTAssertEqual(parsed[3].state, "offline")
        XCTAssertTrue(AndroidController.adbDevices(from: "* daemon started successfully *\nList of devices attached\n").isEmpty)
    }

    func testDevicesMergeRunningPhysicalOfflineAndStoppedAVDsWithoutDuplicatingNames() throws {
        let adb = try fixture("adb-devices"), avds = try fixture("avds")
        let fake = AndroidExecutor { command in
            if command.arguments == ["devices", "-l"] { return .text(adb) }
            if command.arguments == ["-list-avds"] { return .text(avds) }
            if command.arguments.suffix(3) == ["emu", "avd", "name"] { return .text(command.arguments[1] == "emulator-5554" ? "Pixel_API_35\nOK\n" : "WiFi_AVD\nOK\n") }
            let remote = command.arguments.last ?? ""
            if remote.contains("ro.kernel.qemu") { return .text(command.arguments[1] == "192.0.2.10:5555" ? "1\n" : "0\n") }
            if remote.contains("ro.build.version.release") { return .text("15\n") }
            throw FakeError.unexpected
        }
        let devices = try controller(fake).devices()
        XCTAssertEqual(devices.count, 6)
        XCTAssertTrue(devices.allSatisfy { $0.platform == .android })
        XCTAssertEqual(devices.first { $0.id == "emulator-5554" }?.name, "Pixel_API_35")
        XCTAssertEqual(devices.first { $0.id == "192.0.2.10:5555" }?.kind, .simulator)
        XCTAssertEqual(devices.first { $0.id == "FAKE_USB_01" }?.kind, .physical)
        XCTAssertEqual(devices.first { $0.id == "FAKE_USB_01" }?.runtime, "Android 15")
        XCTAssertEqual(devices.first { $0.id == "FAKE_USB_02" }?.isAvailable, false)
        XCTAssertEqual(devices.first { $0.id == "emulator-5556" }?.isAvailable, false)
        XCTAssertEqual(devices.first { $0.id == "Tablet_API_35" }?.state, "Shutdown")
        XCTAssertFalse(devices.contains { $0.id == "Pixel_API_35" || $0.id == "WiFi_AVD" })
        XCTAssertFalse(fake.commands.contains { $0.arguments.count > 1 && ["FAKE_USB_02", "emulator-5556"].contains($0.arguments[1]) })
    }

    func testPhysicalOnlySDKDoesNotRequireEmulator() throws {
        let fake = AndroidExecutor { _ in .text("List of devices attached\n") }
        let c = AndroidController(environment: ["PATH": "/tools"], isExecutable: { $0 == "/tools/adb" }, executor: fake.execute)
        XCTAssertTrue(try c.devices().isEmpty)
        XCTAssertTrue(c.doctor().ready)
        XCTAssertFalse(c.doctor().checks.first { $0.name == "android_emulator" }!.available)
    }

    func testDoctorReportsUnauthorizedOfflineAndADBFailure() throws {
        let adb = try fixture("adb-devices")
        let fake = AndroidExecutor { _ in .text(adb) }
        let report = controller(fake).doctor()
        XCTAssertFalse(report.ready)
        XCTAssertTrue(report.recommendations.joined().contains("RSA"))
        XCTAssertTrue(report.recommendations.joined().contains("adb reconnect offline"))
        let failure = controller(AndroidExecutor { _ in .init(status: 1, stderr: Data("private device info".utf8)) }).doctor()
        XCTAssertFalse(failure.ready)
        XCTAssertFalse(failure.checks.map(\.detail).joined().contains("private device info"))
    }

    func testPackagesUseExactMatchInsteadOfSubstring() throws {
        let packages = try fixture("packages")
        let c = controller(AndroidExecutor { _ in .text(packages) })
        XCTAssertTrue(try c.isAppInstalled("com.example.wallet", on: physical))
        XCTAssertFalse(try c.isAppInstalled("com.example", on: physical))
        XCTAssertEqual(AndroidController.packages(from: packages), ["com.example.store", "com.example.wallet", "com.example.wallet.demo"])
    }

    func testInstallAndUninstallUseSerialAndKeepAPKPathAsSingleArgument() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let apk = root.appendingPathComponent("Demo App.apk")
        try Data().write(to: apk)
        let fake = AndroidExecutor(), c = controller(fake)
        try c.installApp(apk.path, on: physical)
        XCTAssertEqual(fake.commands.last?.arguments, ["-s", physical.id, "install", "-r", apk.path])
        try c.uninstallApp("com.example.wallet", on: physical)
        XCTAssertEqual(fake.commands.last?.arguments, ["-s", physical.id, "uninstall", "com.example.wallet"])
        XCTAssertThrowsError(try c.installApp("/missing.apk", on: physical))
    }

    func testHostActionsTranslateToADBCommandsOnBothKinds() throws {
        let fake = AndroidExecutor(), c = controller(fake)
        for device in [emulator, physical] {
            for (action, expected) in [
                (ScoutAction.launch(bundleIdentifier: "com.example.wallet"), ["monkey", "-p", "com.example.wallet", "-c", "android.intent.category.LAUNCHER", "1"]),
                (.terminate(bundleIdentifier: "com.example.wallet"), ["am", "force-stop", "com.example.wallet"]),
                (.grantPermission(bundleIdentifier: "com.example.wallet", service: "android.permission.CAMERA"), ["pm", "grant", "com.example.wallet", "android.permission.CAMERA"]),
                (.setAppearance("dark"), ["cmd", "uimode", "night", "yes"]),
                (.setAppearance("light"), ["cmd", "uimode", "night", "no"])
            ] {
                _ = try c.execute(action, on: device)
                XCTAssertEqual(fake.commands.last?.arguments, ["-s", device.id, "shell", shell(expected)])
            }
        }
    }

    func testURLsAndActivitiesAreQuotedForRemoteShell() throws {
        let url = "demo://pay?note=Sam's&amount=1;$(id)"
        let fake = AndroidExecutor(), c = controller(fake)
        for action in [ScoutAction.openURL(url), .deepLink(url)] {
            _ = try c.execute(action, on: physical)
            XCTAssertEqual(fake.commands.last?.arguments, ["-s", physical.id, "shell", shell(["am", "start", "-W", "-a", "android.intent.action.VIEW", "-d", url])])
        }
        try c.launchApp("com.example.wallet", activity: ".MainActivity", on: emulator)
        XCTAssertEqual(fake.commands.last?.arguments.last, shell(["am", "start", "-W", "-n", "com.example.wallet/.MainActivity"]))
        XCTAssertEqual(AndroidController.quote("a'b"), "'a'\\''b'")
    }

    func testActivityAndMonkeyFailuresAreNotReportedAsSuccess() {
        for message in ["Error: Activity not started", "Error type 3", "java.lang.SecurityException"] {
            XCTAssertThrowsError(try controller(AndroidExecutor { _ in .text(message) }).launchApp("com.example.wallet", activity: ".MainActivity", on: physical))
        }
        XCTAssertThrowsError(try controller(AndroidExecutor { _ in .text("No activities found to run, monkey aborted.") }).execute(.launch(bundleIdentifier: "com.example.wallet"), on: physical))
    }

    func testActivityErrorsOnStderrAndInvalidScreenshotFailExplicitly() {
        let activity = controller(AndroidExecutor { _ in .init(stderr: Data("Error type 3".utf8)) })
        XCTAssertThrowsError(try activity.launchApp("com.example.wallet", activity: ".Missing", on: physical))
        let screenshot = controller(AndroidExecutor { _ in .text("screencap failed") })
        XCTAssertThrowsError(try screenshot.execute(.screenshot, on: physical))
    }

    func testLocationUsesLongitudeFirstAndRejectsPhysicalAndInvalidCoordinates() throws {
        let fake = AndroidExecutor(), c = controller(fake)
        _ = try c.execute(.setLocation(latitude: -12.04, longitude: -77.03), on: emulator)
        XCTAssertEqual(fake.commands.last?.arguments, ["-s", emulator.id, "emu", "geo", "fix", "-77.03", "-12.04"])
        XCTAssertThrowsError(try c.execute(.setLocation(latitude: 0, longitude: 0), on: physical))
        XCTAssertThrowsError(try c.execute(.setLocation(latitude: .nan, longitude: 0), on: emulator))
        XCTAssertThrowsError(try c.execute(.setLocation(latitude: 91, longitude: 0), on: emulator))
        XCTAssertEqual(fake.commands.count, 1)
    }

    func testRotationsDisableAutoRotateAndMapAllFourValues() throws {
        let fake = AndroidExecutor(), c = controller(fake)
        for (orientation, value) in [(DeviceOrientation.portrait, "0"), (.landscapeLeft, "1"), (.portraitUpsideDown, "2"), (.landscapeRight, "3")] {
            _ = try c.execute(.rotate(orientation), on: emulator)
            XCTAssertEqual(fake.commands.suffix(2).map(\.arguments), [
                ["-s", emulator.id, "shell", shell(["settings", "put", "system", "accelerometer_rotation", "0"])],
                ["-s", emulator.id, "shell", shell(["settings", "put", "system", "user_rotation", value])]
            ])
        }
    }

    func testScreenshotPreservesBinaryAndListAppsReturnsJSON() throws {
        let binary = Data([0x89, 0x50, 0x4e, 0x47, 13, 10, 0x1a, 10, 0xff, 0])
        let packages = try fixture("packages")
        let fake = AndroidExecutor { command in command.arguments.contains("exec-out") ? .init(stdout: binary) : .text(packages) }
        let c = controller(fake)
        XCTAssertEqual(try c.execute(.screenshot, on: physical), binary)
        XCTAssertEqual(fake.commands.last?.arguments, ["-s", physical.id, "exec-out", "screencap", "-p"])
        let data = try XCTUnwrap(c.execute(.listApps, on: physical))
        XCTAssertEqual(try JSONDecoder().decode([InstalledApp].self, from: data).map(\.bundleIdentifier), AndroidController.packages(from: packages))
    }

    func testUnsupportedActionsAreExplicitAndDoNotLaunchProcesses() {
        let fake = AndroidExecutor(), c = controller(fake)
        let selector = ScoutSelector(strategy: .accessibilityIdentifier, value: "login")
        let actions: [ScoutAction] = [.getClipboard, .setClipboard("demo"), .pushNotification(bundleIdentifier: "com.example", payloadPath: "demo.json"), .icloudSync, .resetKeychain, .setBiometry(enrolled: true, enabled: true), .setStatusBar(time: nil, dataNetwork: nil, wifiMode: nil, batteryLevel: nil, batteryState: nil), .setContentSize("large"), .shake, .addMedia("demo.png"), .tap(x: 1, y: 2), .type("demo"), .accessibilityTree, .tapElement(selector), .findElement(.init(strategy: .predicate, value: "true")), .getConfig("demo")]
        for action in actions {
            XCTAssertThrowsError(try c.execute(action, on: emulator)) { error in
                guard case ScoutError.unsupported(let message) = error else { return XCTFail("Unexpected error: \(error)") }
                XCTAssertFalse(message.isEmpty)
            }
        }
        XCTAssertTrue(fake.commands.isEmpty)
    }

    func testRejectsIOSUnavailableDevicesInvalidPackagesAndAppearanceBeforeExecution() {
        let fake = AndroidExecutor(), c = controller(fake)
        XCTAssertThrowsError(try c.execute(.screenshot, on: Device(id: "ios", name: "iPhone", runtime: "iOS", state: "Booted")))
        XCTAssertThrowsError(try c.execute(.screenshot, on: Device(id: "Pixel", name: "Pixel", runtime: "Android", state: "Shutdown", platform: .android)))
        XCTAssertThrowsError(try c.execute(.launch(bundleIdentifier: "com.example; id"), on: emulator))
        XCTAssertThrowsError(try c.execute(.setAppearance("invalid"), on: emulator))
        XCTAssertTrue(fake.commands.isEmpty)
    }

    func testBootStartsAVDInBackgroundReturnsADBSerialAndWaitsForReadiness() throws {
        let state = LifecycleState()
        let fake = AndroidExecutor { command in
            if command.mode == .background { state.started = true; return .init() }
            if command.arguments == ["devices", "-l"] { return .text(state.started ? "List of devices attached\nemulator-5554 device\n" : "List of devices attached\n") }
            if command.arguments == ["-list-avds"] { return .text("Pixel_API_35\n") }
            if command.arguments.suffix(3) == ["emu", "avd", "name"] { return .text("Pixel_API_35\nOK\n") }
            if command.arguments.last?.contains("sys.boot_completed") == true { return .text("1\n") }
            return .text("15\n")
        }
        let device = try controller(fake).boot(deviceID: "Pixel_API_35", timeout: 0)
        XCTAssertEqual(device.id, "emulator-5554")
        XCTAssertEqual(device.platform, .android)
        XCTAssertEqual(fake.commands.first { $0.mode == .background }?.arguments, ["-avd", "Pixel_API_35"])
        XCTAssertEqual(fake.commands.first { $0.mode == .background }?.executable, "/sdk/emulator/emulator")
    }

    func testInstallRejectsAFailureEvenWhenADBExitsWithZero() throws {
        let apk = FileManager.default.temporaryDirectory.appendingPathComponent("install-\(UUID().uuidString).apk")
        try Data().write(to: apk); defer { try? FileManager.default.removeItem(at: apk) }
        let failing = AndroidExecutor { _ in .text("Performing Streamed Install\nFailure [INSTALL_FAILED_OLDER_SDK]\n") }
        XCTAssertThrowsError(try controller(failing).installApp(apk.path, on: emulator)) { error in
            XCTAssertTrue("\(error)".contains("INSTALL_FAILED_OLDER_SDK"), "\(error)")
        }
        let working = AndroidExecutor { _ in .text("Performing Streamed Install\nSuccess\n") }
        XCTAssertNoThrow(try controller(working).installApp(apk.path, on: emulator))
        XCTAssertEqual(working.commands.last?.arguments, ["-s", "emulator-5554", "install", "-r", apk.path])
    }

    func testOnlyARunningAuthorizedAndroidIsUsable() {
        XCTAssertTrue(AndroidController.isUsable(emulator))
        XCTAssertTrue(AndroidController.isUsable(physical))
        for state in ["Shutdown", "offline", "unauthorized", "no permissions"] {
            XCTAssertFalse(AndroidController.isUsable(Device(id: "x", name: "x", runtime: "Android", state: state, platform: .android)), state)
        }
        XCTAssertFalse(AndroidController.isUsable(Device(id: "x", name: "x", runtime: "Android", state: "Booted", isAvailable: false, platform: .android)))
        XCTAssertFalse(AndroidController.isUsable(Device(id: "iPhone", name: "iPhone", runtime: "iOS 18", state: "Booted", platform: .ios)))
    }

    func testBootTimeoutIsBoundedAndDoesNotPassAVDNameToADB() {
        let fake = AndroidExecutor { command in .text(command.arguments == ["-list-avds"] ? "Pixel_API_35\n" : "List of devices attached\n") }
        XCTAssertThrowsError(try controller(fake).boot(deviceID: "Pixel_API_35", timeout: 0))
        XCTAssertFalse(fake.commands.contains { $0.arguments.starts(with: ["-s", "Pixel_API_35"]) })
        XCTAssertThrowsError(try controller(fake).boot(deviceID: "Pixel_API_35", timeout: .nan))
    }

    func testShutdownResolvesAVDNameAndRejectsPhysicalDevices() throws {
        let fake = AndroidExecutor { command in
            if command.arguments == ["devices", "-l"] { return .text("List of devices attached\nemulator-5554 device\nFAKE_USB_01 device\n") }
            if command.arguments == ["-list-avds"] { return .text("Pixel_API_35\nTablet_API_35\n") }
            if command.arguments.suffix(3) == ["emu", "avd", "name"] { return .text("Pixel_API_35\nOK\n") }
            return .text("0\n")
        }
        let c = controller(fake)
        try c.shutdown(deviceID: "Pixel_API_35")
        XCTAssertEqual(fake.commands.last?.arguments, ["-s", "emulator-5554", "emu", "kill"])
        XCTAssertThrowsError(try c.shutdown(deviceID: "FAKE_USB_01"))
        XCTAssertThrowsError(try c.boot(deviceID: "FAKE_USB_01", timeout: 0))
        try c.shutdown(deviceID: "Tablet_API_35")
        XCTAssertEqual(fake.commands.filter { $0.arguments.contains("kill") }.count, 1)
    }

    func testSharedAndPrivateFileOperationsUseCorrectChannelAndPreserveBinary() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let local = root.appendingPathComponent("file with spaces.bin").path
        let binary = Data([0, 255, 13, 10])
        try binary.write(to: URL(fileURLWithPath: local))
        let fake = AndroidExecutor { _ in .init(stdout: binary) }, c = controller(fake)
        _ = try c.execute(.getAppContainer(bundleIdentifier: "com.example.wallet", container: "data"), on: physical)
        XCTAssertEqual(fake.commands.last?.arguments.last, shell(["run-as", "com.example.wallet", "pwd"]))
        _ = try c.execute(.enumerateFiles("/data/user/0/com.example.wallet/files"), on: physical)
        XCTAssertEqual(fake.commands.last?.arguments.last, shell(["run-as", "com.example.wallet", "ls", "-1", "--", "files"]))
        _ = try c.execute(.downloadFile(source: "/data/data/com.example.wallet/files/demo.bin", destination: local), on: physical)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: local)), binary)
        XCTAssertEqual(fake.commands.last?.arguments, ["-s", physical.id, "shell", "-T", shell(["run-as", "com.example.wallet", "cat", "--", "files/demo.bin"])])
        _ = try c.execute(.uploadFile(source: local, destination: "/data/data/com.example.wallet/files/demo.bin"), on: physical)
        XCTAssertEqual(fake.commands.last?.inputFile, local)
        XCTAssertEqual(fake.commands.last?.arguments, ["-s", physical.id, "shell", "-T", shell(["run-as", "com.example.wallet", "sh", "-c", "cat > 'files/demo.bin'"])])
        _ = try c.execute(.downloadFile(source: "/sdcard/demo.bin", destination: local), on: physical)
        XCTAssertEqual(fake.commands.last?.arguments, ["-s", physical.id, "pull", "/sdcard/demo.bin", local])
        _ = try c.execute(.uploadFile(source: local, destination: "/sdcard/demo.bin"), on: physical)
        XCTAssertEqual(fake.commands.last?.arguments, ["-s", physical.id, "push", local, "/sdcard/demo.bin"])
        XCTAssertThrowsError(try c.execute(.enumerateFiles("/data/data/com.example.wallet/../other"), on: physical))
        XCTAssertThrowsError(try c.execute(.downloadFile(source: "-a", destination: local), on: physical))
        XCTAssertThrowsError(try c.execute(.getAppContainer(bundleIdentifier: "com.example.wallet", container: "groups"), on: physical))
    }

    func testRunAsFailureExplainsDebuggableAppRequirement() {
        let c = controller(AndroidExecutor { _ in .init(status: 1) })
        XCTAssertThrowsError(try c.execute(.getAppContainer(bundleIdentifier: "com.example.wallet", container: "data"), on: physical)) { error in
            XCTAssertTrue(error.localizedDescription.contains("depurable"))
        }
    }

    func testVideoUses180SecondLimitStopsOnlyItsProcessAndPullsBeforeRemovingRemoteFile() throws {
        let state = VideoState()
        let fake = videoExecutor(state)
        let c = controller(fake)
        _ = try c.execute(.startVideoRecording("/tmp/demo.mp4"), on: emulator)
        XCTAssertTrue(fake.commands.contains { $0.arguments.last?.contains("screenrecord --time-limit 180") == true })
        XCTAssertThrowsError(try c.execute(.startVideoRecording("/tmp/other.mp4"), on: emulator))
        _ = try c.execute(.stopVideoRecording, on: emulator)
        let commands = fake.commands.map(\.arguments)
        let signal = try XCTUnwrap(commands.firstIndex { $0.last == shell(["kill", "-2", "1234"]) })
        let pull = try XCTUnwrap(commands.firstIndex { $0.contains("pull") })
        let remove = try XCTUnwrap(commands.firstIndex { $0.last?.hasPrefix("'rm'") == true })
        XCTAssertLessThan(signal, pull); XCTAssertLessThan(pull, remove)
        XCTAssertEqual(commands[pull].last, "/tmp/demo.mp4")
        XCTAssertThrowsError(try c.execute(.stopVideoRecording, on: emulator))
    }

    func testVideoDoesNotSignalRecycledPIDAndKeepsRecordingForRetryAfterFailedPull() throws {
        let state = VideoState()
        // The first stop encounters another process at the same PID after auto completion.
        let recorder = videoExecutor(state)
        let c = controller(recorder)
        _ = try c.execute(.startVideoRecording("/tmp/demo.mp4"), on: emulator)
        state.recycled = true; state.failPull = true
        XCTAssertThrowsError(try c.execute(.stopVideoRecording, on: emulator))
        XCTAssertFalse(recorder.commands.contains { $0.arguments.last == shell(["kill", "-2", "1234"]) })
        XCTAssertFalse(recorder.commands.contains { $0.arguments.last?.hasPrefix("'rm'") == true })
        state.failPull = false
        _ = try c.execute(.stopVideoRecording, on: emulator)
        XCTAssertEqual(recorder.commands.filter { $0.arguments.contains("pull") }.count, 2)
    }

    func testNativeExecutorDrainsLargeStdoutAndStderrAndAcceptsBinaryStdin() throws {
        let large = try AndroidController.executeCommand(.init(executable: "/bin/sh", arguments: ["-c", "head -c 131072 /dev/zero >&2; head -c 131072 /dev/zero"]))
        XCTAssertEqual(large.status, 0)
        XCTAssertEqual(large.stdout.count, 131072)
        XCTAssertEqual(large.stderr.count, 131072)
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: path) }
        let bytes = Data([0, 255, 13, 10])
        try bytes.write(to: path)
        let cat = try AndroidController.executeCommand(.init(executable: "/bin/cat", arguments: [], inputFile: path.path))
        XCTAssertEqual(cat.stdout, bytes)
    }

    private func videoExecutor(_ state: VideoState) -> AndroidExecutor {
        AndroidExecutor { command in
            let remote = command.arguments.last ?? ""
            if remote.hasPrefix("nohup screenrecord") {
                state.path = remote.split(separator: "'").first { $0.hasPrefix("/sdcard/") }.map(String.init) ?? ""
                return .text("1234\n")
            }
            if remote.contains("/proc/1234/cmdline") {
                if state.recycled { return .text("other-process") }
                return .text(state.stopped ? "" : "screenrecord\0" + state.path)
            }
            if remote == "'kill' '-2' '1234'" { state.stopped = true; return .init() }
            if command.arguments.contains("pull") && state.failPull { return .init(status: 1) }
            return .init()
        }
    }

    func testNonzeroExitDoesNotExposeArgumentsOrProcessOutput() {
        let fake = AndroidExecutor { _ in .init(status: 1, stdout: Data("secret".utf8), stderr: Data("secret".utf8)) }
        XCTAssertThrowsError(try controller(fake).execute(.openURL("demo://secret"), on: emulator)) { error in
            XCTAssertFalse(error.localizedDescription.contains("secret"))
            XCTAssertTrue(error.localizedDescription.contains("exit 1"))
        }
    }
}

private enum FakeError: Error { case unexpected }
private final class AndroidExecutor: @unchecked Sendable {
    var commands: [AndroidController.Command] = []
    private let handler: @Sendable (AndroidController.Command) throws -> AndroidController.Output
    init(handler: @escaping @Sendable (AndroidController.Command) throws -> AndroidController.Output = { _ in .init() }) { self.handler = handler }
    func execute(_ command: AndroidController.Command) throws -> AndroidController.Output { commands.append(command); return try handler(command) }
}
private extension AndroidController.Output {
    static func text(_ string: String) -> Self { Self(stdout: Data(string.utf8)) }
}

private final class LifecycleState: @unchecked Sendable { var started = false }
private final class VideoState: @unchecked Sendable { var path = ""; var stopped = false; var recycled = false; var failPull = false }
