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
print("CuyScout escuchando en \(scheme)://\(bindAddress):\(port)")
try server.start()
