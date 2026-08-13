import Foundation
import CuyScoutCore

try ScoutConfiguration.applyFromDefaultFile()
let port = ScoutConfiguration.configuredPort(arguments: CommandLine.arguments)
let token = ProcessInfo.processInfo.environment["CUYSCOUT_TOKEN"]
let bindAddress = ProcessInfo.processInfo.environment["CUYSCOUT_BIND_ADDRESS"] ?? "127.0.0.1"
let tlsCert = ProcessInfo.processInfo.environment["CUYSCOUT_TLS_CERT"]
let tlsKey = ProcessInfo.processInfo.environment["CUYSCOUT_TLS_KEY"]
let server = try ScoutHTTPServer(port: port, engine: ScoutEngine(), token: token, bindAddress: bindAddress, tlsCertPath: tlsCert, tlsKeyPath: tlsKey)
let scheme = tlsCert != nil ? "https" : "http"
print("CuyScout escuchando en \(scheme)://\(bindAddress):\(port)")
try server.start()
