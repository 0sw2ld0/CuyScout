import Foundation

/// Additive `android` section of .cuyscout-project.json. Existing iOS keys are retained.
public struct AndroidProjectConfiguration: Codable, Sendable, Hashable {
    public var apk: String
    public var applicationId: String
    public var activity: String?
    public var driverId: String?
    public var deviceId: String?
    public var avd: String?
    public init(apk: String = "", applicationId: String, activity: String? = nil, driverId: String? = nil, deviceId: String? = nil, avd: String? = nil) {
        self.apk = apk; self.applicationId = applicationId; self.activity = activity
        self.driverId = driverId; self.deviceId = deviceId; self.avd = avd
    }
    public func validate() throws {
        guard applicationId.range(of: #"^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$"#, options: .regularExpression) != nil else { throw ScoutError.invalidRequest("Android requiere un applicationId/package válido") }
        guard apk.isEmpty || apk.lowercased().hasSuffix(".apk") else { throw ScoutError.invalidRequest("El instalador Android debe ser .apk") }
        guard driverId == nil || ["android-emulator", "android-device"].contains(driverId!) else { throw ScoutError.invalidRequest("Android requiere android-emulator o android-device") }
        guard avd == nil || driverId != "android-device" else { throw ScoutError.invalidRequest("avd requiere android-emulator") }
    }
}
