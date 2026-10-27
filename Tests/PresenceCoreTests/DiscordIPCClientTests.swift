import XCTest
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
@testable import PresenceCore

final class DiscordIPCClientTests: XCTestCase {
    private var server: FakeDiscordServer!

    override func setUpWithError() throws {
        server = try FakeDiscordServer()
    }

    override func tearDown() {
        server.stop()
    }

    func testHandshakeAndSetActivity() throws {
        server.handle { connection in
            let handshake = try connection.receive()
            XCTAssertEqual(handshake.opcode, .handshake)
            XCTAssertEqual(try connection.json(handshake)["client_id"] as? String, "356875570916753438")
            try connection.send(.frame, #"{"cmd":"DISPATCH","evt":"READY","data":{"v":1}}"#)

            let setActivity = try connection.json(try connection.receive())
            XCTAssertEqual(setActivity["cmd"] as? String, "SET_ACTIVITY")
            let args = setActivity["args"] as? [String: Any]
            XCTAssertEqual(args?["pid"] as? Int, Int(ProcessInfo.processInfo.processIdentifier))
            let nonce = setActivity["nonce"] as? String ?? ""
            try connection.send(.frame, #"{"cmd":"SET_ACTIVITY","evt":null,"nonce":"\#(nonce)","data":{}}"#)
        }

        let client = try DiscordIPCClient.connect(
            clientID: "356875570916753438",
            socketPaths: [server.directory + "/discord-ipc-9", server.path],
            timeout: 2
        )
        try client.setActivity(Activity(startDate: Date()))
        client.close()
        try server.waitUntilDone()
    }

    func testRefusedHandshakeReportsDiscordsReason() throws {
        server.handle { connection in
            _ = try connection.receive()
            try connection.send(.close, #"{"code":4000,"message":"Invalid Client ID"}"#)
        }

        XCTAssertThrowsError(try DiscordIPCClient.connect(clientID: "1", socketPaths: [server.path], timeout: 2)) {
            XCTAssertEqual($0 as? IPCError, .discordError(code: 4000, message: "Invalid Client ID"))
        }
        try server.waitUntilDone()
    }

    func testRejectedActivityReportsDiscordsReason() throws {
        server.handle { connection in
            _ = try connection.receive()
            try connection.send(.frame, #"{"cmd":"DISPATCH","evt":"READY"}"#)
            let nonce = try connection.json(try connection.receive())["nonce"] as? String ?? ""
            try connection.send(
                .frame,
                #"{"cmd":"SET_ACTIVITY","evt":"ERROR","nonce":"\#(nonce)","data":{"code":4000,"message":"child \"activity\" fails"}}"#
            )
        }

        let client = try DiscordIPCClient.connect(clientID: "1", socketPaths: [server.path], timeout: 2)
        XCTAssertThrowsError(try client.setActivity(Activity())) {
            XCTAssertEqual($0 as? IPCError, .discordError(code: 4000, message: #"child "activity" fails"#))
        }
        try server.waitUntilDone()
    }

    func testMissingSocketMeansDiscordIsNotRunning() {
        XCTAssertThrowsError(
            try DiscordIPCClient.connect(clientID: "1", socketPaths: [server.directory + "/discord-ipc-5"])
        ) {
            XCTAssertEqual($0 as? IPCError, .socketNotFound)
        }
    }

    func testPollAnswersPingsAndNoticesWhenDiscordGoesAway() throws {
        server.handle { connection in
            _ = try connection.receive()
            try connection.send(.frame, #"{"cmd":"DISPATCH","evt":"READY"}"#)
            try connection.send(.ping, #"{"n":7}"#)
            let pong = try connection.receive()
            XCTAssertEqual(pong.opcode, .pong)
            XCTAssertEqual(pong.payload, Data(#"{"n":7}"#.utf8))
            connection.close()
        }

        let client = try DiscordIPCClient.connect(clientID: "1", socketPaths: [server.path], timeout: 2)
        XCTAssertThrowsError(try client.pollIncoming(timeout: 2)) {
            XCTAssertEqual($0 as? IPCError, .connectionClosed)
        }
        try server.waitUntilDone()
    }

    func testPollReturnsQuietlyWhenNothingArrives() throws {
        server.handle { connection in
            _ = try connection.receive()
            try connection.send(.frame, #"{"cmd":"DISPATCH","evt":"READY"}"#)
            _ = try? connection.receive(timeout: 1)
        }

        let client = try DiscordIPCClient.connect(clientID: "1", socketPaths: [server.path], timeout: 2)
        XCTAssertNoThrow(try client.pollIncoming(timeout: 0.05))
        client.close()
        try server.waitUntilDone()
    }
}

/// Listens on a Unix socket like the Discord app and runs a scripted conversation
/// with the first client that connects.
final class FakeDiscordServer {
    let directory: String
    let path: String
    private var listener: Int32
    private let done = DispatchSemaphore(value: 0)
    private var failure: Error?

    final class Connection {
        private let socket: UnixSocket
        private var buffer = Data()

        init(socket: UnixSocket) {
            self.socket = socket
        }

        func receive(timeout: TimeInterval = 2) throws -> IPCFrame {
            let deadline = Date().addingTimeInterval(timeout)
            while true {
                if let frame = try IPCFrame.decode(from: &buffer) { return frame }
                guard try socket.waitUntilReadable(timeout: deadline.timeIntervalSinceNow) else {
                    throw IPCError.timeout
                }
                let chunk = try socket.read()
                guard !chunk.isEmpty else { throw IPCError.connectionClosed }
                buffer.append(chunk)
            }
        }

        func send(_ opcode: IPCOpcode, _ json: String) throws {
            try socket.write(IPCFrame(opcode: opcode, payload: Data(json.utf8)).encoded())
        }

        func json(_ frame: IPCFrame) throws -> [String: Any] {
            try XCTUnwrap(try JSONSerialization.jsonObject(with: frame.payload) as? [String: Any])
        }

        func close() {
            socket.close()
        }
    }

    init() throws {
        // Short directory name: socket paths are limited to about 100 bytes.
        directory = NSTemporaryDirectory() + "ipc-" + UUID().uuidString.prefix(8)
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        path = directory + "/discord-ipc-0"

        listener = socket(AF_UNIX, unixStreamSocketType, 0)
        var address = try UnixSocket.makeAddress(path: path)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard listener >= 0, bound == 0, listen(listener, 1) == 0 else {
            throw IPCError.system("fake server: \(errnoDescription())")
        }
    }

    /// Accepts one client in the background and runs `script` with it.
    func handle(_ script: @escaping (Connection) throws -> Void) {
        let listener = self.listener
        DispatchQueue.global().async {
            defer { self.done.signal() }
            let fd = accept(listener, nil, nil)
            guard fd >= 0 else { return }
            let connection = Connection(socket: UnixSocket(fileDescriptor: fd))
            do {
                try script(connection)
            } catch {
                self.failure = error
            }
            connection.close()
        }
    }

    func waitUntilDone() throws {
        XCTAssertEqual(done.wait(timeout: .now() + 5), .success, "fake server did not finish")
        if let failure { throw failure }
    }

    func stop() {
        if listener >= 0 {
            shutdown(listener, Int32(SHUT_RDWR))
            close(listener)
            listener = -1
        }
        try? FileManager.default.removeItem(atPath: directory)
    }
}
