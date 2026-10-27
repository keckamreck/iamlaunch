import Foundation

/// An open connection to Discord that can show one activity.
public protocol PresenceConnection: AnyObject {
    /// Shows `activity`, or clears the status when it is nil.
    func setActivity(_ activity: Activity?) throws
    /// Handles whatever Discord sends within `timeout` and throws once the connection is gone.
    func pollIncoming(timeout: TimeInterval) throws
    func close()
}

/// Talks to the Discord desktop app over its local IPC socket, the same
/// interface games use for Rich Presence. Not thread-safe: use one client
/// from one thread.
public final class DiscordIPCClient: PresenceConnection {
    public let clientID: String
    private let socket: UnixSocket
    private let responseTimeout: TimeInterval
    private let pid = ProcessInfo.processInfo.processIdentifier
    private var buffer = Data()

    private init(clientID: String, socket: UnixSocket, responseTimeout: TimeInterval) {
        self.clientID = clientID
        self.socket = socket
        self.responseTimeout = responseTimeout
    }

    /// Connects as the Discord application `clientID`. Discord shows that
    /// application's name and icon as the game being played.
    public static func connect(
        clientID: String,
        socketPaths: [String] = DiscordSocketPath.candidates(),
        timeout: TimeInterval = 5
    ) throws -> DiscordIPCClient {
        var lastError: Error = IPCError.socketNotFound
        for path in socketPaths {
            guard let socket = try? UnixSocket.connect(path: path) else { continue }
            let client = DiscordIPCClient(clientID: clientID, socket: socket, responseTimeout: timeout)
            do {
                try client.handshake()
                return client
            } catch {
                client.close()
                // Discord itself refused, so another socket would refuse too.
                if case IPCError.discordError = error { throw error }
                lastError = error
            }
        }
        throw lastError
    }

    public func setActivity(_ activity: Activity?) throws {
        let nonce = UUID().uuidString
        try socket.write(IPCMessage.setActivity(activity, pid: pid, nonce: nonce).encoded())
        let deadline = Date().addingTimeInterval(responseTimeout)
        while true {
            switch try nextResponse(until: deadline) {
            case .activitySet(let replyNonce) where replyNonce == nonce:
                return
            case let .error(code, message):
                throw IPCError.discordError(code: code, message: message)
            case .closed:
                throw IPCError.connectionClosed
            default:
                continue
            }
        }
    }

    public func pollIncoming(timeout: TimeInterval) throws {
        let deadline = Date().addingTimeInterval(timeout)
        do {
            while true {
                if case .closed = try nextResponse(until: deadline) {
                    throw IPCError.connectionClosed
                }
            }
        } catch IPCError.timeout {
            return
        }
    }

    public func close() {
        socket.close()
    }

    private func handshake() throws {
        try socket.write(IPCMessage.handshake(clientID: clientID).encoded())
        let deadline = Date().addingTimeInterval(responseTimeout)
        while true {
            switch try nextResponse(until: deadline) {
            case .ready:
                return
            case let .error(code, message), let .closed(code, message):
                throw IPCError.discordError(code: code, message: message)
            default:
                continue
            }
        }
    }

    /// Returns the next frame from Discord, answering pings along the way.
    private func nextResponse(until deadline: Date) throws -> IPCResponse {
        while true {
            if let frame = try IPCFrame.decode(from: &buffer) {
                let response = IPCResponse(frame: frame)
                if case .ping(let payload) = response {
                    try socket.write(IPCMessage.pong(payload: payload).encoded())
                    continue
                }
                return response
            }
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0, try socket.waitUntilReadable(timeout: remaining) else {
                throw IPCError.timeout
            }
            let chunk = try socket.read()
            guard !chunk.isEmpty else { throw IPCError.connectionClosed }
            buffer.append(chunk)
        }
    }
}
