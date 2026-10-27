import Foundation

/// Opcodes of Discord's local IPC protocol.
public enum IPCOpcode: UInt32, Sendable {
    case handshake = 0
    case frame = 1
    case close = 2
    case ping = 3
    case pong = 4
}

/// One message on the Discord IPC socket: an 8-byte header (opcode and
/// payload length, both little-endian UInt32) followed by a JSON payload.
public struct IPCFrame: Equatable, Sendable {
    public static let headerSize = 8
    public static let maxPayloadSize = 1 << 20

    public var opcode: IPCOpcode
    public var payload: Data

    public init(opcode: IPCOpcode, payload: Data) {
        self.opcode = opcode
        self.payload = payload
    }

    public func encoded() -> Data {
        var data = Data(capacity: Self.headerSize + payload.count)
        data.appendLittleEndian(opcode.rawValue)
        data.appendLittleEndian(UInt32(payload.count))
        data.append(payload)
        return data
    }

    /// Removes the first complete frame from `buffer` and returns it, or
    /// returns nil (leaving `buffer` untouched) if no complete frame is there yet.
    public static func decode(from buffer: inout Data) throws -> IPCFrame? {
        guard buffer.count >= headerSize else { return nil }
        let start = buffer.startIndex
        let rawOpcode = buffer.littleEndianUInt32(at: start)
        let length = Int(buffer.littleEndianUInt32(at: start + 4))
        guard let opcode = IPCOpcode(rawValue: rawOpcode) else {
            throw IPCError.protocolError("unbekannter Opcode \(rawOpcode)")
        }
        guard length <= maxPayloadSize else {
            throw IPCError.protocolError("Nachricht zu groß (\(length) Bytes)")
        }
        let payloadStart = start + headerSize
        let payloadEnd = payloadStart + length
        guard buffer.endIndex >= payloadEnd else { return nil }
        let payload = Data(buffer[payloadStart..<payloadEnd])
        buffer = Data(buffer[payloadEnd...])
        return IPCFrame(opcode: opcode, payload: payload)
    }
}

extension Data {
    mutating func appendLittleEndian(_ value: UInt32) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    func littleEndianUInt32(at index: Index) -> UInt32 {
        var value: UInt32 = 0
        for offset in 0..<4 {
            value |= UInt32(self[index + offset]) << (8 * offset)
        }
        return value
    }
}
