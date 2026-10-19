import Foundation

/// Additive `android` section of .cuyscout-project.json. Existing iOS keys are retained.
public extension Sequence where Element == Device {
    /// El AVD apagado al que apunta una selección (su nombre o su id), si lo hay. Un AVD en
    /// marcha aparece con su serial de adb, así que no coincide con uno apagado.
    func stoppedAVD(matching selection: String) -> Device? {
        guard !selection.isEmpty else { return nil }
        return first { $0.platform == .android && $0.kind == .simulator && $0.state == "Shutdown" && ($0.id == selection || $0.name == selection) }
    }
}

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
    /// Cambia entre emulador y dispositivo físico. El destino elegido (AVD o serial) era de la
    /// opción anterior, así que se limpia. Es una sola mutación a propósito: la interfaz la aplica
    /// con una única asignación; varias escrituras seguidas por un Binding de SwiftUI se pisan
    /// entre sí y el cambio se perdía.
    public mutating func selectDriver(_ id: String) {
        driverId = id
        deviceId = nil
        avd = nil
    }

    public func validate() throws {
        guard applicationId.range(of: #"^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$"#, options: .regularExpression) != nil else { throw ScoutError.invalidRequest("Android requiere un applicationId/package válido") }
        guard apk.isEmpty || apk.lowercased().hasSuffix(".apk") else { throw ScoutError.invalidRequest("El instalador Android debe ser .apk") }
        guard driverId == nil || ["android-emulator", "android-device"].contains(driverId!) else { throw ScoutError.invalidRequest("Android requiere android-emulator o android-device") }
        guard avd == nil || driverId != "android-device" else { throw ScoutError.invalidRequest("avd requiere android-emulator") }
    }
}
