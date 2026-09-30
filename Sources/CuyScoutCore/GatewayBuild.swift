import Foundation

/// Identifica la compilación del ejecutable del gateway (fecha de modificación y tamaño).
/// La app lo compara con el gateway que ya corre: tras actualizar CuyScout, un gateway de
/// la versión anterior seguía respondiendo con su lógica vieja.
public enum GatewayBuild {
    public static func identifier(of executable: URL) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: executable.resolvingSymlinksInPath().path),
              let modified = attributes[.modificationDate] as? Date, let size = attributes[.size] as? NSNumber else { return nil }
        return "\(Int(modified.timeIntervalSince1970))-\(size.int64Value)"
    }

    /// El del proceso actual, calculado al arrancar: si luego se reemplaza el binario en
    /// disco, este gateway sigue informando la compilación con la que arrancó.
    public static let current: String? = identifier(of: Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments.first ?? "/"))

    /// El gateway que responde es de otra compilación que la que trae esta app. Un gateway
    /// sin el dato es anterior a este chequeo, y por tanto también viejo.
    public static func isOutdated(running: String?, bundled: String?) -> Bool {
        guard let bundled else { return false }
        return running != bundled
    }
}
