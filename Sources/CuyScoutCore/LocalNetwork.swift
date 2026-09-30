import Foundation

/// Direcciones de esta Mac que un iPhone puede alcanzar (Wi-Fi, Ethernet o el hotspot del
/// propio iPhone). Excluye loopback y autoasignadas (169.254.x.x).
public enum LocalNetwork {
    public struct Interface: Sendable, Equatable {
        public let name: String
        public let address: String
    }

    public static func ipv4Interfaces() -> [Interface] {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else { return [] }
        defer { freeifaddrs(first) }
        var result: [Interface] = []
        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let item = current {
            let value = item.pointee
            if let address = value.ifa_addr, address.pointee.sa_family == UInt8(AF_INET), value.ifa_flags & UInt32(IFF_UP) != 0 {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    let ip = String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
                    if !ip.hasPrefix("127.") && !ip.hasPrefix("169.254.") { result.append(Interface(name: String(cString: value.ifa_name), address: ip)) }
                }
            }
            current = value.ifa_next
        }
        return result
    }

    /// La dirección preferida: Wi-Fi (en0), luego Ethernet (en1…), luego el resto (VPN al final).
    public static func primaryIPv4(from interfaces: [Interface] = ipv4Interfaces()) -> String? {
        func rank(_ name: String) -> Int { name == "en0" ? 0 : name.hasPrefix("en") ? 1 : name.hasPrefix("bridge") ? 2 : name.hasPrefix("utun") ? 4 : 3 }
        return interfaces.sorted { rank($0.name) < rank($1.name) }.first?.address
    }

    /// `172.20.10.x` es la red del hotspot de un iPhone: la Mac está conectada a él.
    public static func isIPhoneHotspot(_ address: String) -> Bool { address.hasPrefix("172.20.10.") }
}
