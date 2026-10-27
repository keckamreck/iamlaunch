import Foundation

/// The Rich Presence activity shown in Discord. Discord takes the game's name
/// and icon from the application the connection was opened with, so the
/// activity itself only carries the elapsed-time counter.
public struct Activity: Equatable, Sendable {
    public var startDate: Date?

    public init(startDate: Date? = nil) {
        self.startDate = startDate
    }

    var jsonObject: [String: Any] {
        var object: [String: Any] = [:]
        if let startDate {
            // Seconds, like Discord's own RPC library sends them.
            object["timestamps"] = ["start": Int(startDate.timeIntervalSince1970)]
        }
        return object
    }
}

/// Builds the frames this app sends to Discord.
enum IPCMessage {
    static func handshake(clientID: String) -> IPCFrame {
        frame(.handshake, ["v": 1, "client_id": clientID])
    }

    /// Sets the activity, or clears it when `activity` is nil.
    static func setActivity(_ activity: Activity?, pid: Int32, nonce: String) -> IPCFrame {
        var args: [String: Any] = ["pid": Int(pid)]
        if let activity {
            args["activity"] = activity.jsonObject
        }
        return frame(.frame, ["cmd": "SET_ACTIVITY", "args": args, "nonce": nonce])
    }

    static func pong(payload: Data) -> IPCFrame {
        IPCFrame(opcode: .pong, payload: payload)
    }

    private static func frame(_ opcode: IPCOpcode, _ object: [String: Any]) -> IPCFrame {
        // Only ever called with strings, numbers and dictionaries of those,
        // which JSONSerialization always accepts.
        let payload = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return IPCFrame(opcode: opcode, payload: payload)
    }
}

/// What a frame received from Discord means for this app.
enum IPCResponse: Equatable {
    case ready
    case activitySet(nonce: String?)
    case error(code: Int?, message: String)
    case closed(code: Int?, message: String)
    case ping(Data)
    case other

    init(frame: IPCFrame) {
        switch frame.opcode {
        case .ping:
            self = .ping(frame.payload)
        case .close:
            let json = Self.jsonObject(frame.payload)
            self = .closed(
                code: json?["code"] as? Int,
                message: json?["message"] as? String ?? "Verbindung von Discord geschlossen"
            )
        case .frame:
            guard let json = Self.jsonObject(frame.payload) else {
                self = .other
                return
            }
            let command = json["cmd"] as? String
            let event = json["evt"] as? String
            if event == "ERROR" {
                let data = json["data"] as? [String: Any]
                self = .error(
                    code: data?["code"] as? Int,
                    message: data?["message"] as? String ?? "Unbekannter Fehler"
                )
            } else if command == "DISPATCH" && event == "READY" {
                self = .ready
            } else if command == "SET_ACTIVITY" {
                self = .activitySet(nonce: json["nonce"] as? String)
            } else {
                self = .other
            }
        case .handshake, .pong:
            self = .other
        }
    }

    private static func jsonObject(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
