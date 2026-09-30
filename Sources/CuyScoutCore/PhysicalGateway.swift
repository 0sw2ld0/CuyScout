import Foundation

/// ¿Puede un iPhone físico hablar con este gateway? El runner corre dentro del iPhone y se
/// conecta a la Mac por la red: el gateway debe escuchar en una IP de la red local
/// (`CUYSCOUT_BIND_ADDRESS`) y anunciarla al runner (`CUYSCOUT_DEVICE_GATEWAY_URL`).
public struct PhysicalGatewayStatus: Codable, Sendable, Equatable {
    public let enabled: Bool
    public let deviceGatewayURL: String?
    public let bindAddress: String
    public let currentAddress: String?
    public let hotspot: Bool
    public let issues: [String]
    /// Un runner de iPhone ya pidió comandos a este gateway: el iPhone sí lo alcanza.
    public let runnerConnected: Bool

    public var ready: Bool { enabled && issues.isEmpty }

    nonisolated(unsafe) private static var lastRunnerContact: Date?
    private static let contactLock = NSLock()

    /// Lo llama el motor cuando el runner de un iPhone se conecta por primera vez.
    public static func recordRunnerContact(at date: Date = Date()) {
        contactLock.lock(); lastRunnerContact = date; contactLock.unlock()
    }
    public static var runnerContact: Date? {
        contactLock.lock(); defer { contactLock.unlock() }; return lastRunnerContact
    }

    public static func evaluate(environment: [String: String] = ProcessInfo.processInfo.environment,
                                interfaces: [LocalNetwork.Interface] = LocalNetwork.ipv4Interfaces(),
                                runnerContact: Date? = PhysicalGatewayStatus.runnerContact,
                                probe: (URL) -> Bool = PhysicalGatewayStatus.respondsToStatus) -> PhysicalGatewayStatus {
        let bind = environment["CUYSCOUT_BIND_ADDRESS"] ?? "127.0.0.1"
        let deviceURL = environment["CUYSCOUT_DEVICE_GATEWAY_URL"].flatMap { $0.isEmpty ? nil : $0 }
        let current = LocalNetwork.primaryIPv4(from: interfaces)
        let host = deviceURL.flatMap { URL(string: $0)?.host }
        let loopback = ["127.0.0.1", "localhost", "0.0.0.0"]
        var issues: [String] = []
        let enabled = deviceURL != nil && host.map { !loopback.contains($0) } == true
        if !enabled {
            issues.append("El gateway corre en modo local (\(bind)): el iPhone no puede alcanzarlo. En CuyScout.app usa Grabar prueba → Automático (iPhone físico), o arranca con CUYSCOUT_BIND_ADDRESS y CUYSCOUT_DEVICE_GATEWAY_URL con la IP de esta Mac.")
        } else if let host {
            if !interfaces.contains(where: { $0.address == host }) {
                issues.append("La IP anunciada al iPhone (\(host)) ya no es de esta Mac\(current.map { "; ahora es \($0)" } ?? ""). ¿Cambiaste de red? Reinicia el modo iPhone físico en CuyScout.app.")
            } else if runnerContact == nil, let url = deviceURL.flatMap(URL.init(string:)), !probe(url) {
                // Con un runner ya conectado no se sondea: en Macs corporativas la Mac no puede
                // consultarse por su propia IP de red y el sondeo daba una falsa alarma.
                issues.append("El gateway no responde en \(url.absoluteString) desde esta Mac: revisa que escuche en esa IP (CUYSCOUT_BIND_ADDRESS). En una Mac corporativa, un firewall o agente de seguridad puede bloquear esa IP; conecta la Mac al hotspot del iPhone o pide la excepción para cuyscout.")
            }
            if environment["CUYSCOUT_TOKEN"]?.isEmpty != false {
                issues.append("Falta CUYSCOUT_TOKEN: es obligatorio cuando el gateway está expuesto a la red.")
            }
        }
        return PhysicalGatewayStatus(enabled: enabled, deviceGatewayURL: deviceURL, bindAddress: bind, currentAddress: current,
                                     hotspot: current.map(LocalNetwork.isIPhoneHotspot) ?? false, issues: issues,
                                     runnerConnected: enabled && runnerContact != nil)
    }

    /// `GET <url>/status` con timeout corto.
    public static func respondsToStatus(_ url: URL) -> Bool {
        var request = URLRequest(url: url.appendingPathComponent("status"))
        request.timeoutInterval = 2
        return LayaService.send(request, timeout: 2)?.0 == 200
    }

    /// Chequeo de `/doctor`. Es opcional: solo importa para probar en un iPhone físico.
    public func doctorCheck() -> DoctorCheck {
        if ready {
            let network = hotspot ? " (hotspot del iPhone)" : ""
            if runnerConnected {
                return DoctorCheck(name: "physical_gateway", available: true, detail: "Modo iPhone físico: el runner del iPhone ya se conectó a \(deviceGatewayURL ?? "")\(network).")
            }
            return DoctorCheck(name: "physical_gateway", available: true, detail: "Modo iPhone físico: el runner se conecta a \(deviceGatewayURL ?? "")\(network). Si el iPhone no llega (red corporativa que aísla dispositivos), conecta la Mac al hotspot del iPhone.")
        }
        return DoctorCheck(name: "physical_gateway", available: false, detail: issues.joined(separator: " "))
    }
}
