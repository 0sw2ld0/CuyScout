import Foundation
import Darwin

/// Connection information shared by the desktop app and the local MCP bridge.
/// This is a per-user file, never part of a generated project or test artifact.
public struct LocalGatewayProfile: Codable, Equatable, Sendable {
    public let url: String
    public let token: String

    public init(url: String, token: String) {
        self.url = url
        self.token = token
    }

    public static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("CuyScout", isDirectory: true)
            .appendingPathComponent("gateway-connection.json")
    }

    public static func load(from url: URL = fileURL) -> LocalGatewayProfile? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let mode = attributes[.posixPermissions] as? NSNumber,
              mode.intValue & 0o077 == 0,
              let data = try? Data(contentsOf: url),
              let profile = try? JSONDecoder().decode(Self.self, from: data),
              let parsed = URL(string: profile.url),
              ["http", "https"].contains(parsed.scheme?.lowercased() ?? ""),
              parsed.host != nil,
              !profile.token.isEmpty else { return nil }
        return profile
    }

    public func save(to url: URL = fileURL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(self)
        let staging = url.deletingLastPathComponent().appendingPathComponent(".gateway-\(UUID().uuidString).tmp")
        guard fm.createFile(atPath: staging.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        do {
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: staging.path)
            let result = staging.path.withCString { source in
                url.path.withCString { destination in Darwin.rename(source, destination) }
            }
            if result != 0 { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        } catch {
            try? fm.removeItem(at: staging)
            throw error
        }
    }
}
