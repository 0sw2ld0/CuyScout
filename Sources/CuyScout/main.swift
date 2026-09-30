import Foundation
import CuyScoutCore

if CommandLine.arguments.dropFirst().first == "init" {
    do {
        try InitCommand.run(arguments: Array(CommandLine.arguments.dropFirst(2)))
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
        exit(1)
    }
}

try ScoutConfiguration.applyFromDefaultFile()
let port = ScoutConfiguration.configuredPort(arguments: CommandLine.arguments)
let token = ProcessInfo.processInfo.environment["CUYSCOUT_TOKEN"]
let bindAddress = ProcessInfo.processInfo.environment["CUYSCOUT_BIND_ADDRESS"] ?? "127.0.0.1"
let tlsCert = ProcessInfo.processInfo.environment["CUYSCOUT_TLS_CERT"]
let tlsKey = ProcessInfo.processInfo.environment["CUYSCOUT_TLS_KEY"]
let engine = ScoutEngine()
engine.gatewayBaseURL = ProcessInfo.processInfo.environment["CUYSCOUT_DEVICE_GATEWAY_URL"] ?? "http://\(bindAddress == "0.0.0.0" ? "127.0.0.1" : bindAddress):\(port)"
let server = try ScoutHTTPServer(port: port, engine: engine, token: token, bindAddress: bindAddress, tlsCertPath: tlsCert, tlsKeyPath: tlsKey)
let scheme = tlsCert != nil ? "https" : "http"
let physical = PhysicalGatewayStatus.evaluate(probe: { _ in true })
let teams = SigningTeams.detect()
ScoutLog.gateway.info("startup", "Gateway arrancando", [
    "url": "\(scheme)://\(bindAddress):\(port)", "pid": ProcessInfo.processInfo.processIdentifier,
    "executable": CommandLine.arguments.first ?? "-", "token": token?.isEmpty == false ? "sí" : "no",
    "modoIPhone": physical.enabled ? "sí" : "no", "deviceGatewayURL": physical.deviceGatewayURL ?? "-",
    "ipMac": physical.currentAddress ?? "-", "hotspot": physical.hotspot,
    "equipoFirma": SigningTeams.resolve() ?? "-", "equiposDetectados": teams.count,
    "macOS": ProcessInfo.processInfo.operatingSystemVersionString])
for issue in physical.enabled ? physical.issues : [] { ScoutLog.gateway.warning("startup", issue) }
print("CuyScout escuchando en \(scheme)://\(bindAddress):\(port)")
print("Logs: \(ScoutLog.gateway.fileURL.path)")
do { try server.start() } catch {
    let occupant = PortInspector.listener(on: Int(port))
    let reason = occupant.map { "el puerto \(port) ya lo usa \($0.label)" } ?? error.localizedDescription
    ScoutLog.gateway.error("startup", "El gateway no pudo arrancar", ["motivo": reason, "bind": bindAddress, "port": port])
    FileHandle.standardError.write(Data("CuyScout no pudo arrancar en \(bindAddress):\(port): \(reason). Cierra ese proceso o usa otro puerto (cuyscout <puerto>).\n".utf8))
    exit(1)
}
