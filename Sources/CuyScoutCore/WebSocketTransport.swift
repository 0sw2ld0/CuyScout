import Foundation
import CryptoKit

/// Codec RFC 6455 para el canal WebSocket BiDi de eventos de CuyScout.
///
/// Implementa el handshake (`Sec-WebSocket-Accept` con SHA-1 + base64), la
/// codificación de frames de servidor (texto, pong, close) y la decodificación
/// tolerante de frames de cliente enmascarados, incluidos frames parciales.
public enum WebSocketTransport {
    public static let magicGUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

    /// Clave de aceptación derivada del `Sec-WebSocket-Key` del cliente.
    public static func acceptKey(for key: String) -> String {
        Data(Insecure.SHA1.hash(data: Data((key + magicGUID).utf8))).base64EncodedString()
    }

    /// Respuesta HTTP 101 completa para completar el handshake del cliente.
    public static func handshakeResponse(key: String) -> String {
        "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: \(acceptKey(for: key))\r\n\r\n"
    }

    public enum ClientOpcode: UInt8, Sendable, Equatable {
        case continuation = 0x0, text = 0x1, binary = 0x2, close = 0x8, ping = 0x9, pong = 0xA
    }

    public struct ClientFrame: Sendable, Equatable {
        public let opcode: ClientOpcode
        public let payload: Data
        public let fin: Bool
        public init(opcode: ClientOpcode, payload: Data, fin: Bool) { self.opcode = opcode; self.payload = payload; self.fin = fin }
    }

    /// Frames que el gateway envía al cliente: sin máscara, con longitud de 1, 2 o 8 bytes.
    public static func encodeFrame(opcode: UInt8, payload: Data) -> Data {
        var frame = Data([0x80 | opcode])
        let length = payload.count
        if length < 126 {
            frame.append(UInt8(length))
        } else if length <= 0xFFFF {
            frame.append(126)
            frame.append(UInt8((length >> 8) & 0xFF)); frame.append(UInt8(length & 0xFF))
        } else {
            frame.append(127)
            for shift in stride(from: 56, through: 0, by: -8) { frame.append(UInt8((length >> shift) & 0xFF)) }
        }
        frame.append(payload)
        return frame
    }

    public static func encodeTextFrame(_ payload: Data) -> Data { encodeFrame(opcode: 0x1, payload: payload) }
    public static func encodePongFrame(_ payload: Data) -> Data { encodeFrame(opcode: 0xA, payload: payload) }
    public static func encodeCloseFrame() -> Data { encodeFrame(opcode: 0x8, payload: Data()) }

    /// Decodifica los frames de cliente completos disponibles al inicio del buffer.
    /// Devuelve los frames parseados y cuántos bytes consumió; el remanente debe
    /// conservarse para concatenarlo con la siguiente lectura del socket.
    public static func decodeClientFrames(_ input: Data) -> (frames: [ClientFrame], consumedBytes: Int) {
        var frames: [ClientFrame] = []
        let bytes = [UInt8](input)
        var index = 0
        while bytes.count - index >= 2 {
            let first = bytes[index]; let second = bytes[index + 1]
            let fin = first & 0x80 != 0
            let opcode = ClientOpcode(rawValue: first & 0x0F) ?? .continuation
            let masked = second & 0x80 != 0
            var length = Int(second & 0x7F)
            var cursor = index + 2
            if length == 126 {
                guard bytes.count - cursor >= 2 else { return (frames, index) }
                length = Int(bytes[cursor]) << 8 | Int(bytes[cursor + 1]); cursor += 2
            } else if length == 127 {
                guard bytes.count - cursor >= 8 else { return (frames, index) }
                length = 0; for offset in 0..<8 { length = length << 8 | Int(bytes[cursor + offset]) }; cursor += 8
            }
            let maskKey: [UInt8]
            if masked {
                guard bytes.count - cursor >= 4 else { return (frames, index) }
                maskKey = Array(bytes[cursor..<cursor + 4]); cursor += 4
            } else { maskKey = [0, 0, 0, 0] }
            guard bytes.count - cursor >= length, length >= 0 else { return (frames, index) }
            var payload = Array(bytes[cursor..<cursor + length])
            if masked { for position in 0..<payload.count { payload[position] ^= maskKey[position % 4] } }
            frames.append(ClientFrame(opcode: opcode, payload: Data(payload), fin: fin))
            index = cursor + length
        }
        return (frames, index)
    }
}