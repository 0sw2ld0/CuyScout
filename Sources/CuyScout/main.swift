import Foundation
import CuyScoutCore

// `cuyscout export-appium <artefacto.cuyscout.json> [ts|py] [salida]`: genera la prueba Appium
// con la versión actual del exportador (para CI o scripts), sin levantar el gateway.
if CommandLine.arguments.dropFirst().first == "export-appium" {
    let arguments = Array(CommandLine.arguments.dropFirst(2))
    guard let artifact = arguments.first else {
        FileHandle.standardError.write(Data("Uso: cuyscout export-appium <artefacto.cuyscout.json> [ts|py] [salida]\n".utf8)); exit(2)
    }
    let format: AppiumExportFormat = arguments.count > 1 && arguments[1] == "py" ? .python : .typescript
    do {
        let source = try format.source(fromArtifactData: Data(contentsOf: URL(fileURLWithPath: artifact)))
        if arguments.count > 2 { try source.write(toFile: arguments[2], atomically: true, encoding: .utf8) } else { print(source) }
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8)); exit(1)
    }
}
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
    "url": server.listenAddresses.map { "\(scheme)://\($0):\(port)" }.joined(separator: " "), "pid": ProcessInfo.processInfo.processIdentifier,
    "executable": CommandLine.arguments.first ?? "-", "compilacion": GatewayBuild.current ?? "-", "token": token?.isEmpty == false ? "sí" : "no",
    "modoIPhone": physical.enabled ? "sí" : "no", "deviceGatewayURL": physical.deviceGatewayURL ?? "-",
    "ipMac": physical.currentAddress ?? "-", "hotspot": physical.hotspot,
    "equipoFirma": SigningTeams.resolve() ?? "-", "equiposDetectados": teams.count,
    "macOS": ProcessInfo.processInfo.operatingSystemVersionString])
for issue in physical.enabled ? physical.issues : [] { ScoutLog.gateway.warning("startup", issue) }
print("CuyScout escuchando en " + server.listenAddresses.map { "\(scheme)://\($0):\(port)" }.joined(separator: " y "))
print("Logs: \(ScoutLog.gateway.fileURL.path)")
do { try server.start() } catch {
    let occupant = PortInspector.listener(on: Int(port))
    let reason = occupant.map { "el puerto \(port) ya lo usa \($0.label)" } ?? error.localizedDescription
    ScoutLog.gateway.error("startup", "El gateway no pudo arrancar", ["motivo": reason, "bind": bindAddress, "port": port])
    FileHandle.standardError.write(Data("CuyScout no pudo arrancar en \(bindAddress):\(port): \(reason). Cierra ese proceso o usa otro puerto (cuyscout <puerto>).\n".utf8))
    exit(1)
}
