import Foundation
import Security

/// Equipo de Apple con el que se puede firmar el runner de un iPhone físico.
public struct SigningTeam: Codable, Sendable, Equatable, Hashable {
    public let id: String
    public let name: String
    /// Cuenta gratuita (Personal Team): los perfiles caducan cada 7 días.
    public let isFree: Bool
    /// Hay un certificado de desarrollo válido con su clave privada en el llavero.
    public let hasCertificate: Bool
    /// Es el último equipo elegido en Xcode.
    public let isXcodeSelected: Bool

    public init(id: String, name: String, isFree: Bool, hasCertificate: Bool, isXcodeSelected: Bool) {
        self.id = id; self.name = name; self.isFree = isFree
        self.hasCertificate = hasCertificate; self.isXcodeSelected = isXcodeSelected
    }

    public var label: String {
        var parts = [name.isEmpty ? id : "\(name) (\(id))"]
        if isFree { parts.append("gratuito") }
        if !hasCertificate { parts.append("sin certificado aún") }
        return parts.joined(separator: " · ")
    }
}

/// Detecta los equipos de firma de esta Mac: las cuentas iniciadas en Xcode y los
/// certificados de desarrollo del llavero. No guarda ni envía nada fuera de la Mac.
public enum SigningTeams {
    public static let environmentKey = "CUYSCOUT_DEVELOPMENT_TEAM"

    /// Team ID explícito (variable de entorno) o, si no hay, el que se detecta en la Mac.
    public static func resolve(environment: [String: String] = ProcessInfo.processInfo.environment,
                               detect: () -> [SigningTeam] = { SigningTeams.detect() }) -> String? {
        if let explicit = environment[environmentKey]?.trimmingCharacters(in: .whitespaces), !explicit.isEmpty { return explicit }
        return preferred(in: detect())?.id
    }

    /// El equipo a usar sin preguntar: el único disponible, o el elegido en Xcode si tiene certificado.
    public static func preferred(in teams: [SigningTeam]) -> SigningTeam? {
        let usable = teams.filter(\.hasCertificate)
        if usable.count == 1 { return usable[0] }
        if let selected = usable.first(where: \.isXcodeSelected) { return selected }
        if usable.isEmpty, teams.count == 1 { return teams[0] }
        return nil
    }

    public static func detect() -> [SigningTeam] {
        let plist = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/com.apple.dt.Xcode.plist")
        let xcode = (try? Data(contentsOf: plist)).flatMap(xcodeTeams(fromPreferences:)) ?? (teams: [], selected: nil)
        return merge(xcode: xcode.teams, selected: xcode.selected, certificates: certificateTeams())
    }

    /// Une los equipos de Xcode con los de los certificados; primero los que pueden firmar ya.
    static func merge(xcode: [(id: String, name: String, isFree: Bool)], selected: String?,
                      certificates: [(id: String, name: String)]) -> [SigningTeam] {
        let certified = Set(certificates.map(\.id))
        var names: [String: String] = [:]
        var free: [String: Bool] = [:]
        var order: [String] = []
        for team in xcode where !team.id.isEmpty {
            if names[team.id] == nil { order.append(team.id) }
            if names[team.id]?.isEmpty != false { names[team.id] = team.name }
            free[team.id] = team.isFree
        }
        for certificate in certificates where !certificate.id.isEmpty {
            if names[certificate.id] == nil { order.append(certificate.id); names[certificate.id] = certificate.name }
            else if names[certificate.id]?.isEmpty == true { names[certificate.id] = certificate.name }
        }
        let teams = order.map { id in
            SigningTeam(id: id, name: names[id] ?? "", isFree: free[id] ?? false,
                        hasCertificate: certified.contains(id), isXcodeSelected: id == selected)
        }
        return teams.enumerated().sorted { lhs, rhs in
            if lhs.element.hasCertificate != rhs.element.hasCertificate { return lhs.element.hasCertificate }
            if lhs.element.isXcodeSelected != rhs.element.isXcodeSelected { return lhs.element.isXcodeSelected }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    /// Lee `IDEProvisioningTeamByIdentifier` (cuentas de Xcode → equipos) y el último equipo elegido.
    static func xcodeTeams(fromPreferences data: Data) -> (teams: [(id: String, name: String, isFree: Bool)], selected: String?)? {
        guard let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        var teams: [(id: String, name: String, isFree: Bool)] = []
        let accounts = root["IDEProvisioningTeamByIdentifier"] as? [String: Any] ?? root["IDEProvisioningTeams"] as? [String: Any] ?? [:]
        for key in accounts.keys.sorted() {
            for entry in accounts[key] as? [[String: Any]] ?? [] {
                guard let id = entry["teamID"] as? String else { continue }
                let isFree = (entry["isFreeProvisioningTeam"] as? Bool) ?? ((entry["isFreeProvisioningTeam"] as? Int) == 1)
                teams.append((id, entry["teamName"] as? String ?? "", isFree))
            }
        }
        return (teams, root["IDEProvisioningTeamManagerLastSelectedTeamID"] as? String)
    }

    /// Equipos de los certificados de desarrollo vigentes que tienen su clave privada (identidades).
    static func certificateTeams() -> [(id: String, name: String)] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecMatchValidOnDate as String: Date(),
            kSecReturnRef as String: true
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let identities = result as? [SecIdentity] else { return [] }
        var teams: [(id: String, name: String)] = []
        for identity in identities {
            var certificate: SecCertificate?
            guard SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess, let certificate,
                  let summary = SecCertificateCopySubjectSummary(certificate) as String?,
                  isDevelopmentCertificate(summary),
                  let subject = subjectFields(of: certificate), let id = subject.organizationalUnit,
                  !teams.contains(where: { $0.id == id }) else { continue }
            teams.append((id, subject.organization ?? ""))
        }
        return teams
    }

    static func isDevelopmentCertificate(_ commonName: String) -> Bool {
        ["Apple Development:", "iPhone Developer:"].contains { commonName.hasPrefix($0) }
    }

    private static func subjectFields(of certificate: SecCertificate) -> (organizationalUnit: String?, organization: String?)? {
        let keys = [kSecOIDX509V1SubjectName] as CFArray
        guard let values = SecCertificateCopyValues(certificate, keys, nil) as? [CFString: Any],
              let subject = values[kSecOIDX509V1SubjectName] as? [CFString: Any],
              let fields = subject[kSecPropertyKeyValue] as? [[CFString: Any]] else { return nil }
        func field(_ oid: CFString) -> String? {
            fields.first { ($0[kSecPropertyKeyLabel] as? String) == oid as String }?[kSecPropertyKeyValue] as? String
        }
        return (field(kSecOIDOrganizationalUnitName), field(kSecOIDOrganizationName))
    }
}
