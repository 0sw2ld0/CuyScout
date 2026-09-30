import Foundation

/// Quién escucha en un puerto TCP y qué puerto libre usar. El 4723 de CuyScout es también
/// el puerto por defecto de Appium, así que en Macs de QA suele estar ocupado.
public enum PortInspector {
    public struct Listener: Sendable, Equatable {
        public let pid: Int32
        public let command: String
        public var isCuyScoutGateway: Bool { command.lowercased().hasPrefix("cuyscout") && !command.lowercased().contains("app") }
        public var label: String { "\(command) (pid \(pid))" }
    }

    /// Proceso que escucha en `port` (cualquier dirección), o nil si está libre.
    public static func listener(on port: Int) -> Listener? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN", "-Fpc"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return parse(String(decoding: data, as: UTF8.self))
    }

    /// Salida `-Fpc` de lsof: líneas `p<pid>` y `c<comando>`.
    static func parse(_ output: String) -> Listener? {
        var pid: Int32?
        var command: String?
        for line in output.split(separator: "\n") {
            if line.hasPrefix("p"), pid == nil { pid = Int32(line.dropFirst()) }
            if line.hasPrefix("c"), command == nil { command = String(line.dropFirst()) }
        }
        guard let pid, let command else { return nil }
        return Listener(pid: pid, command: command)
    }

    /// Primer puerto de `range` sin nadie escuchando.
    public static func firstFreePort(in range: ClosedRange<Int>, isFree: (Int) -> Bool = { listener(on: $0) == nil }) -> Int? {
        range.first(where: isFree)
    }
}
