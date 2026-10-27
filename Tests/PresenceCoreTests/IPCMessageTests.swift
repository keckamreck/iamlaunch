import XCTest
@testable import PresenceCore

final class IPCMessageTests: XCTestCase {
    func testHandshakeSendsVersionAndClientID() {
        let frame = IPCMessage.handshake(clientID: "123")

        XCTAssertEqual(frame.opcode, .handshake)
        XCTAssertEqual(String(decoding: frame.payload, as: UTF8.self), #"{"client_id":"123","v":1}"#)
    }

    func testSetActivitySendsStartTimestampInSeconds() throws {
        let activity = Activity(startDate: Date(timeIntervalSince1970: 1_700_000_000.75))
        let frame = IPCMessage.setActivity(activity, pid: 42, nonce: "abc")

        XCTAssertEqual(frame.opcode, .frame)
        XCTAssertEqual(
            String(decoding: frame.payload, as: UTF8.self),
            #"{"args":{"activity":{"timestamps":{"start":1700000000}},"pid":42},"cmd":"SET_ACTIVITY","nonce":"abc"}"#
        )
    }

    func testClearingLeavesOutTheActivity() {
        let frame = IPCMessage.setActivity(nil, pid: 42, nonce: "abc")

        XCTAssertEqual(
            String(decoding: frame.payload, as: UTF8.self),
            #"{"args":{"pid":42},"cmd":"SET_ACTIVITY","nonce":"abc"}"#
        )
    }

    func testParsesReady() {
        let frame = Self.frame(.frame, #"{"cmd":"DISPATCH","evt":"READY","data":{"v":1}}"#)

        XCTAssertEqual(IPCResponse(frame: frame), .ready)
    }

    func testParsesActivityConfirmation() {
        let frame = Self.frame(.frame, #"{"cmd":"SET_ACTIVITY","evt":null,"nonce":"n1","data":{}}"#)

        XCTAssertEqual(IPCResponse(frame: frame), .activitySet(nonce: "n1"))
    }

    func testParsesError() {
        let frame = Self.frame(
            .frame,
            #"{"cmd":"SET_ACTIVITY","evt":"ERROR","nonce":"n1","data":{"code":4000,"message":"Bad activity"}}"#
        )

        XCTAssertEqual(IPCResponse(frame: frame), .error(code: 4000, message: "Bad activity"))
    }

    func testParsesClose() {
        let frame = Self.frame(.close, #"{"code":4000,"message":"Invalid Client ID"}"#)

        XCTAssertEqual(IPCResponse(frame: frame), .closed(code: 4000, message: "Invalid Client ID"))
    }

    func testParsesPingAndIgnoresUnknownFrames() {
        XCTAssertEqual(IPCResponse(frame: Self.frame(.ping, "{}")), .ping(Data("{}".utf8)))
        XCTAssertEqual(IPCResponse(frame: Self.frame(.frame, #"{"cmd":"SUBSCRIBE"}"#)), .other)
        XCTAssertEqual(IPCResponse(frame: Self.frame(.frame, "not json")), .other)
    }

    private static func frame(_ opcode: IPCOpcode, _ json: String) -> IPCFrame {
        IPCFrame(opcode: opcode, payload: Data(json.utf8))
    }
}
