import Foundation

public enum IPCError: Error, Equatable {
    /// No Discord IPC socket accepted a connection; Discord is most likely not running.
    case socketNotFound
    /// Discord closed the connection.
    case connectionClosed
    /// Discord did not answer in time.
    case timeout
    /// Discord sent something that does not follow the IPC protocol.
    case protocolError(String)
    /// Discord answered and refused the request, e.g. an unknown application ID.
    case discordError(code: Int?, message: String)
    /// A system call on the socket failed.
    case system(String)
}

extension IPCError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .socketNotFound:
            return "Discord-App nicht gefunden."
        case .connectionClosed:
            return "Discord hat die Verbindung getrennt."
        case .timeout:
            return "Discord antwortet nicht."
        case .protocolError(let message):
            return "Unerwartete Antwort von Discord: \(message)"
        case .discordError(_, let message):
            return message
        case .system(let message):
            return message
        }
    }
}
