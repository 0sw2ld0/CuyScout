import XCTest
@testable import CuyScoutCore

final class AndroidDriverTests: XCTestCase {
    private let emulator = Device(id: "emulator-5554", name: "Pixel", runtime: "Android 15", state: "Booted", platform: .android)
    private let physical = Device(id: "FAKE_USB_01", name: "Demo Phone", runtime: "Android 15", state: "Booted", kind: .physical, platform: .android)

    private func controller(_ fake: DriverExecutor = DriverExecutor(), tools: Set<String> = ["adb", "emulator", "avdmanager"]) -> AndroidController {
        AndroidController(environment: ["ANDROID_HOME": "/sdk"], homeDirectory: "/fake-home", isExecutable: { tools.contains(URL(fileURLWithPath: $0).lastPathComponent) }, executor: fake.execute)
    }

    func testEngineRegistersBothAndroidDriversAlongsideUnchangedIOSDescriptors() throws {
        let engine = ScoutEngine(androidController: controller())
        XCTAssertEqual(engine.drivers().map(\.id), ["android-device", "android-emulator", "ios-device", "ios-simulator"])
        XCTAssertEqual(engine.drivers().first { $0.id == "ios-device" }, PhysicalDeviceDriverAdapter().descriptor)
        XCTAssertEqual(engine.drivers().first { $0.id == "ios-simulator" }, SimulatorDriverAdapter().descriptor)
        let android = engine.drivers().filter { $0.platform == .android }
        XCTAssertEqual(android.map(\.platforms), [["Android"], ["Android"]])
        XCTAssertEqual(android.first { $0.id == "android-device" }?.deviceKind, .physical)
        XCTAssertEqual(android.first { $0.id == "android-emulator" }?.deviceKind, .simulator)
        for descriptor in android {
            XCTAssertEqual(try JSONDecoder().decode(DriverDescriptor.self, from: JSONEncoder().encode(descriptor)), descriptor)
            XCTAssertTrue(descriptor.supportedCapabilities.contains("appium:udid"))
            XCTAssertFalse(descriptor.supportedCapabilities.contains("appium:xcodeOrgId"))
        }
    }

    func testBothDriversCanBeConstructedThroughProtocolInitializer() {
        let types: [any CuyScoutDriver.Type] = [AndroidEmulatorDriverAdapter.self, AndroidDeviceDriverAdapter.self]
        XCTAssertEqual(types.map { $0.init().descriptor.id }, ["android-emulator", "android-device"])
    }

    func testAdaptersDelegateToInjectedControllerWithCorrectSerial() throws {
        let fake = DriverExecutor(), host = controller(fake)
        let adapters: [(any CuyScoutDriver, Device)] = [(AndroidEmulatorDriverAdapter(controller: host), emulator), (AndroidDeviceDriverAdapter(controller: host), physical)]
        for (adapter, device) in adapters {
            XCTAssertNil(try adapter.execute(.terminate(bundleIdentifier: "com.example.wallet"), on: device))
            XCTAssertEqual(fake.commands.last?.arguments, ["-s", device.id, "shell", "'am' 'force-stop' '--user' '0' 'com.example.wallet'"])
        }
        XCTAssertEqual(fake.commands.count, 2)
    }

    func testAdaptersPreserveScreenshotBytes() throws {
        let bytes = Data([0x89, 0x50, 0x4e, 0x47, 13, 10, 0x1a, 10, 0, 255])
        let host = controller(DriverExecutor { _ in .init(stdout: bytes) })
        XCTAssertEqual(try AndroidEmulatorDriverAdapter(controller: host).execute(.screenshot, on: emulator), bytes)
        XCTAssertEqual(try AndroidDeviceDriverAdapter(controller: host).execute(.screenshot, on: physical), bytes)
    }

    func testAdaptersRejectWrongPlatformAndKindBeforeInvokingADB() {
        let fake = DriverExecutor(), host = controller(fake)
        let ios = Device(id: "ios", name: "iPhone", runtime: "iOS", state: "Booted")
        for (driver, wrongDevices) in [
            (AndroidEmulatorDriverAdapter(controller: host) as any CuyScoutDriver, [ios, physical]),
            (AndroidDeviceDriverAdapter(controller: host) as any CuyScoutDriver, [ios, emulator])
        ] {
            for wrong in wrongDevices {
                XCTAssertThrowsError(try driver.execute(.screenshot, on: wrong)) { error in
                    guard case ScoutError.invalidRequest(let message) = error else { return XCTFail("Unexpected error: \(error)") }
                    XCTAssertTrue(message.contains(driver.descriptor.id))
                }
            }
        }
        XCTAssertTrue(fake.commands.isEmpty)
    }

    func testAdaptersPreserveUnsupportedAndProcessFailureErrors() {
        let fake = DriverExecutor { _ in .init(status: 1) }, host = controller(fake)
        let driver = AndroidDeviceDriverAdapter(controller: host)
        XCTAssertThrowsError(try driver.execute(.icloudSync, on: physical)) { error in
            guard case ScoutError.unsupported = error else { return XCTFail("Unexpected error: \(error)") }
        }
        XCTAssertTrue(fake.commands.isEmpty)
        XCTAssertThrowsError(try driver.execute(.terminate(bundleIdentifier: "com.example.wallet"), on: physical)) { error in
            guard case ScoutError.commandFailed = error else { return XCTFail("Unexpected error: \(error)") }
        }
        XCTAssertEqual(fake.commands.count, 1)
    }

    func testHealthyHostReportsADBAndSDKPathsForBothDrivers() {
        let fake = DriverExecutor(), host = controller(fake)
        for driver in [AndroidEmulatorDriverAdapter(controller: host) as any CuyScoutDriver, AndroidDeviceDriverAdapter(controller: host)] {
            let health = driver.health()
            XCTAssertTrue(health.healthy)
            XCTAssertTrue(health.message.contains("android_adb: /sdk/platform-tools/adb"))
            XCTAssertTrue(health.message.contains("android_sdk: /sdk"))
        }
        XCTAssertTrue(fake.commands.allSatisfy { $0.arguments == ["devices", "-l"] })
    }

    func testEmulatorHealthRequiresEmulatorWhilePhysicalOnlyRequiresADB() {
        let host = controller(tools: ["adb"])
        let emulatorHealth = AndroidEmulatorDriverAdapter(controller: host).health()
        let physicalHealth = AndroidDeviceDriverAdapter(controller: host).health()
        XCTAssertFalse(emulatorHealth.healthy)
        XCTAssertTrue(emulatorHealth.message.contains("sdkmanager \"emulator\""))
        XCTAssertTrue(physicalHealth.healthy)
        XCTAssertTrue(physicalHealth.message.contains("android_sdk"))
    }

    func testPhysicalDriverAcceptsStandaloneADBFromPATHAndReportsMissingFullSDK() {
        let fake = DriverExecutor()
        let host = AndroidController(environment: ["PATH": "/tools"], homeDirectory: "/fake-home", isExecutable: { $0 == "/tools/adb" }, executor: fake.execute)
        let health = AndroidDeviceDriverAdapter(controller: host).health()
        XCTAssertTrue(health.healthy)
        XCTAssertTrue(health.message.contains("android_adb: /tools/adb"))
        XCTAssertTrue(health.message.contains("SDK completo no localizado"))
        XCTAssertFalse(AndroidEmulatorDriverAdapter(controller: host).health().healthy)
    }

    func testMissingADBIsUnhealthyForBothDriversAndDoesNotLaunchProcesses() {
        let fake = DriverExecutor(), host = controller(fake, tools: [])
        for driver in [AndroidEmulatorDriverAdapter(controller: host) as any CuyScoutDriver, AndroidDeviceDriverAdapter(controller: host)] {
            let health = driver.health()
            XCTAssertFalse(health.healthy)
            XCTAssertTrue(health.message.contains("sdkmanager \"platform-tools\""))
        }
        XCTAssertTrue(fake.commands.isEmpty)
    }

    func testADBServerFailuresAreUnhealthyAndDoNotExposeDeviceOutput() {
        let fake = DriverExecutor { _ in .init(status: 1, stderr: Data("private data".utf8)) }, host = controller(fake)
        for driver in [AndroidEmulatorDriverAdapter(controller: host) as any CuyScoutDriver, AndroidDeviceDriverAdapter(controller: host)] {
            let health = driver.health()
            XCTAssertFalse(health.healthy)
            XCTAssertTrue(health.message.contains("adb start-server"))
            XCTAssertFalse(health.message.contains("private data"))
        }
    }

    func testUnauthorizedAndOfflineDevicesProduceActionableHealth() {
        for (state, hint) in [("unauthorized", "RSA"), ("offline", "adb reconnect offline")] {
            let host = controller(DriverExecutor { _ in .init(stdout: Data("List of devices attached\nFAKE_USB_01 \(state)\n".utf8)) })
            let health = AndroidDeviceDriverAdapter(controller: host).health()
            XCTAssertFalse(health.healthy)
            XCTAssertTrue(health.message.contains(hint))
        }
    }

    func testEngineUsesInjectedAndroidControllerForRegisteredDriversHealth() {
        let fake = DriverExecutor(), host = controller(fake, tools: ["adb"])
        let engine = ScoutEngine(androidController: host)
        let health = engine.driverHealth()
        XCTAssertEqual(health["android-device"]?.healthy, true)
        XCTAssertEqual(health["android-emulator"]?.healthy, false)
        XCTAssertEqual(fake.commands.count, 2)
        XCTAssertEqual(health.keys.sorted(), engine.drivers().map(\.id))
    }

    func testEngineDoctorAddsAndroidDiagnosticsWhenSDKIsMissing() {
        let fake = DriverExecutor()
        let engine = ScoutEngine(androidController: controller(fake, tools: []))
        let report = engine.doctor()
        XCTAssertEqual(report.ready, SimulatorController().doctor().ready)
        XCTAssertTrue(report.checks.contains { $0.name == "xcrun" })
        XCTAssertTrue(report.checks.contains { $0.name == "android_adb" && !$0.available })
        XCTAssertTrue(report.checks.contains { $0.name == "android_sdk" && !$0.available })
        XCTAssertTrue(report.recommendations.contains { $0.hasPrefix("Android (opcional para iOS):") && $0.contains("sdkmanager") })
        XCTAssertTrue(fake.commands.isEmpty)
    }

    func testCombinedDoctorReportPreservesIOSReadinessAndExistingChecksInEveryCase() {
        for iosReady in [false, true] {
            for androidReady in [false, true] {
                let ios = DoctorReport(ready: iosReady, checks: [.init(name: "xcrun", available: iosReady, detail: "iOS")], recommendations: ["Existing iOS remedy"])
                let android = DoctorReport(ready: androidReady, checks: [.init(name: "android_adb", available: androidReady, detail: "Android")], recommendations: ["sdkmanager"])
                let combined = ScoutEngine.combinedDoctorReport(ios: ios, android: android)
                XCTAssertEqual(combined.ready, iosReady)
                XCTAssertEqual(combined.checks, ios.checks + android.checks)
                XCTAssertEqual(combined.recommendations, ["Existing iOS remedy", "Android (opcional para iOS): sdkmanager"])
                XCTAssertEqual(Set(combined.checks.map(\.name)).count, combined.checks.count)
            }
        }
    }

    func testReplayDriverMappingStaysWithinRecordedPlatform() {
        let engine = ScoutEngine(androidController: controller())
        XCTAssertEqual(engine.driverID("android-emulator", for: .physical), "android-device")
        XCTAssertEqual(engine.driverID("android-device", for: .simulator), "android-emulator")
        XCTAssertEqual(engine.driverID("android-emulator", for: .simulator), "android-emulator")
        XCTAssertEqual(engine.driverID("ios-device", for: .simulator), "ios-simulator")
    }
}

private final class DriverExecutor: @unchecked Sendable {
    var commands: [AndroidController.Command] = []
    private let handler: @Sendable (AndroidController.Command) throws -> AndroidController.Output
    init(handler: @escaping @Sendable (AndroidController.Command) throws -> AndroidController.Output = { _ in .init(stdout: Data("List of devices attached\n".utf8)) }) { self.handler = handler }
    func execute(_ command: AndroidController.Command) throws -> AndroidController.Output { commands.append(command); return try handler(command) }
}
