import AppKit
import CuyScoutCore

/// Resumen para diagnosticar problemas en otra Mac: configuración, red, equipos de firma,
/// estado del modo iPhone y las últimas líneas de los logs. Nunca incluye tokens.
enum DiagnosticsReport {
    static func text() -> String {
        let info = ProcessInfo.processInfo
        let physical = PhysicalGatewayStatus.evaluate(probe: { _ in true })
        let profile = LocalGatewayProfile.load()
        var lines = [
            "# Diagnóstico de CuyScout",
            "Fecha: \(ISO8601DateFormatter().string(from: Date()))",
            "macOS: \(info.operatingSystemVersionString)",
            "App: \(Bundle.main.bundleURL.path)",
            "Gateway del perfil: \(profile?.url ?? "sin perfil") (token: \(profile == nil ? "no" : "sí"))",
            "Interfaces: " + LocalNetwork.ipv4Interfaces().map { "\($0.name)=\($0.address)" }.joined(separator: ", "),
            "IP preferida: \(LocalNetwork.primaryIPv4() ?? "ninguna")\(physical.hotspot ? " (hotspot del iPhone)" : "")",
            "Equipos de firma: " + (SigningTeams.detect().map(\.label).joined(separator: "; ").nonEmpty ?? "ninguno"),
            "iPhones conectados: " + (SimulatorController().physicalDevices().map { "\($0.name) (\($0.isAvailable ? "disponible" : "no disponible"))" }.joined(separator: ", ").nonEmpty ?? "ninguno"),
            "", "## app.log (últimas 60 líneas)"
        ]
        lines += ScoutLog.app.tail(lines: 60)
        lines += ["", "## gateway.log (últimas 120 líneas)"]
        lines += ScoutLog.gateway.tail(lines: 120)
        return lines.joined(separator: "\n")
    }

    static func copyToPasteboard() {
        let report = text()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        ScoutLog.app.info("app", "Diagnóstico copiado al portapapeles", ["caracteres": report.count])
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
