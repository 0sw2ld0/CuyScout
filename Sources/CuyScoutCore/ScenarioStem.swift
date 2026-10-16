import Foundation

/// Nombre de los archivos de salida de un escenario. En un proyecto con iOS y Android se
/// graba una prueba por plataforma: `<escenario>.ios` y `<escenario>.android`. Un proyecto
/// de una sola plataforma conserva `<escenario>`, así que lo ya grabado sigue valiendo.
public enum ScenarioStem {
    public static func split(_ stem: String) -> (base: String, platform: Device.Platform?) {
        for platform in [Device.Platform.ios, .android] {
            let suffix = "." + platform.rawValue
            if stem.hasSuffix(suffix), stem.count > suffix.count { return (String(stem.dropLast(suffix.count)), platform) }
        }
        return (stem, nil)
    }

    public static func stem(base: String, platform: Device.Platform, multiPlatform: Bool) -> String {
        guard multiPlatform, split(base).platform == nil else { return base }
        return base + "." + platform.rawValue
    }

    /// Escenarios que muestra la app. Si `transferencia` tiene pruebas por plataforma
    /// (`transferencia.ios`, `transferencia.android`), su fila sin prueba propia sobra: los
    /// escenarios son las variantes, y su `.feature` es el mismo.
    public static func displayNames(artifacts: Set<String>, features: Set<String>, lastRuns: Set<String>) -> [String] {
        let all = artifacts.union(features).union(lastRuns)
        let withPlatformVariant = Set(all.compactMap { name -> String? in
            let parts = split(name); return parts.platform == nil ? nil : parts.base
        })
        return all.filter { !(withPlatformVariant.contains($0) && !artifacts.contains($0) && !lastRuns.contains($0)) }.sorted()
    }
}
