import Foundation

public final class AndroidEmulatorDriverAdapter: CuyScoutDriver {
    public let descriptor = DriverDescriptor(
        id: "android-emulator", name: "CuyScout Android Emulator Driver", platforms: ["Android"],
        supportedCapabilities: AndroidDriverSupport.capabilities, platform: .android, deviceKind: .simulator)
    private let controller: AndroidController

    public init(controller: AndroidController) { self.controller = controller }
    public required convenience init() { self.init(controller: AndroidController()) }
    public func health() -> DriverHealth { AndroidDriverSupport.health(controller: controller, requiresEmulator: true) }
    public func execute(_ action: ScoutAction, on device: Device) throws -> Data? {
        try AndroidDriverSupport.validate(device, descriptor: descriptor)
        return try controller.execute(action, on: device)
    }
}

public final class AndroidDeviceDriverAdapter: CuyScoutDriver {
    public let descriptor = DriverDescriptor(
        id: "android-device", name: "CuyScout Android Physical Device Driver", platforms: ["Android"],
        supportedCapabilities: AndroidDriverSupport.capabilities, platform: .android, deviceKind: .physical)
    private let controller: AndroidController

    public init(controller: AndroidController) { self.controller = controller }
    public required convenience init() { self.init(controller: AndroidController()) }
    public func health() -> DriverHealth { AndroidDriverSupport.health(controller: controller, requiresEmulator: false) }
    public func execute(_ action: ScoutAction, on device: Device) throws -> Data? {
        try AndroidDriverSupport.validate(device, descriptor: descriptor)
        return try controller.execute(action, on: device)
    }
}

private enum AndroidDriverSupport {
    static let capabilities = ["appium:appPackage", "appium:appActivity", "appium:avd", "appium:app", "appium:noReset", "appium:fullReset", "appium:udid", "appium:deviceName", "appium:platformVersion", "appium:driverId", "platformName"]

    static func validate(_ device: Device, descriptor: DriverDescriptor) throws {
        guard descriptor.supports(device) else {
            throw ScoutError.invalidRequest("El driver \(descriptor.id) requiere Android y kind=\(descriptor.deviceKind?.rawValue ?? "compatible"); selecciona el driver correspondiente al dispositivo")
        }
    }

    static func health(controller: AndroidController, requiresEmulator: Bool) -> DriverHealth {
        let report = controller.doctor()
        let names = ["android_adb", "android_sdk"] + (requiresEmulator ? ["android_emulator"] : [])
        let details = names.compactMap { name in report.checks.first { $0.name == name } }.map { "\($0.name): \($0.detail)" }
        let emulatorAvailable = report.checks.first { $0.name == "android_emulator" }?.available == true
        let healthy = report.ready && (!requiresEmulator || emulatorAvailable)
        // A physical device only needs platform-tools, including adb installed through PATH.
        // Always include SDK details and remedies even when an optional SDK component is absent.
        return DriverHealth(healthy: healthy, message: (details + report.recommendations).joined(separator: "; "))
    }
}
