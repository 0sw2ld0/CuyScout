import AppKit
import CuyScoutCore

/// Resumen para diagnosticar problemas en otra Mac: configuración, red, equipos de firma,
/// estado del modo iPhone y las últimas líneas de los logs. Nunca incluye tokens.
enum DiagnosticsReport {
    static func text() -> String {
        let info = ProcessInfo.processInfo
        let physical = PhysicalGatewayStatus.evaluate(probe: { _ in true })
        let profile = LocalGatewayProfile.load()
        let interfaces: String = LocalNetwork.ipv4Interfaces().map { "\($0.name)=\($0.address)" }.joined(separator: ", ")
        let preferred: String = LocalNetwork.primaryIPv4() ?? "ninguna"
        let teams: String = SigningTeams.detect().map(\.label).joined(separator: "; ")
        let phones: String = SimulatorController().physicalDevices()
            .map { device -> String in "\(device.name) (\(device.isAvailable ? "disponible" : "no disponible"))" }
            .joined(separator: ", ")
        var lines: [String] = []
        lines.append("# Diagnóstico de CuyScout")
        lines.append("Fecha: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("macOS: \(info.operatingSystemVersionString)")
        lines.append("App: \(Bundle.main.bundleURL.path)")
        lines.append("Gateway del perfil: \(profile?.url ?? "sin perfil") (token: \(profile == nil ? "no" : "sí"))")
        lines.append("Interfaces: \(interfaces)")
        lines.append("IP preferida: \(preferred)\(physical.hotspot ? " (hotspot del iPhone)" : "")")
        lines.append("Equipos de firma: \(teams.isEmpty ? "ninguno" : teams)")
        lines.append("iPhones conectados: \(phones.isEmpty ? "ninguno" : phones)")
        lines.append("")
        lines.append("## app.log (últimas 60 líneas)")
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
