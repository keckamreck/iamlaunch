import XCTest
@testable import PresenceCore

final class IPCFrameTests: XCTestCase {
    func testEncodeWritesLittleEndianHeaderThenPayload() {
        let frame = IPCFrame(opcode: .frame, payload: Data("{}".utf8))

        XCTAssertEqual([UInt8](frame.encoded()), [1, 0, 0, 0, 2, 0, 0, 0, 0x7B, 0x7D])
    }

    func testDecodeTakesFramesOneByOneAndKeepsIncompleteRest() throws {
        let first = IPCFrame(opcode: .handshake, payload: Data(#"{"v":1}"#.utf8))
        let second = IPCFrame(opcode: .close, payload: Data(#"{"code":1}"#.utf8))
        let third = IPCFrame(opcode: .frame, payload: Data(#"{"cmd":"X"}"#.utf8)).encoded()
        var buffer = first.encoded() + second.encoded() + third.prefix(10)

        XCTAssertEqual(try IPCFrame.decode(from: &buffer), first)
        XCTAssertEqual(try IPCFrame.decode(from: &buffer), second)
        XCTAssertNil(try IPCFrame.decode(from: &buffer))
        XCTAssertEqual(buffer, third.prefix(10))

        buffer.append(third.dropFirst(10))
        XCTAssertEqual(try IPCFrame.decode(from: &buffer)?.payload, Data(#"{"cmd":"X"}"#.utf8))
        XCTAssertTrue(buffer.isEmpty)
    }

    func testDecodeWaitsForCompleteHeader() throws {
        var buffer = Data([1, 0, 0])

        XCTAssertNil(try IPCFrame.decode(from: &buffer))
        XCTAssertEqual(buffer.count, 3)
    }

    func testDecodeRejectsUnknownOpcode() {
        var buffer = Data([9, 0, 0, 0, 0, 0, 0, 0])

        XCTAssertThrowsError(try IPCFrame.decode(from: &buffer)) { error in
            guard case IPCError.protocolError = error else { return XCTFail("unexpected \(error)") }
        }
    }

    func testDecodeRejectsOversizedPayload() {
        var buffer = Data()
        buffer.appendLittleEndian(IPCOpcode.frame.rawValue)
        buffer.appendLittleEndian(UInt32(IPCFrame.maxPayloadSize + 1))

        XCTAssertThrowsError(try IPCFrame.decode(from: &buffer))
    }
}
