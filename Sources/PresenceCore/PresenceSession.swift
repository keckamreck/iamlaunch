import Foundation

public enum PresenceStatus: Equatable, Sendable {
    /// No game is selected.
    case idle
    /// Connecting to Discord.
    case connecting
    /// Discord shows the selected game.
    case active
    /// Discord is not running or went away; retrying.
    case waitingForDiscord
    /// Discord refused the request. Not retried until another game is selected.
    case rejected(String)
}

/// Keeps the selected game visible in Discord. A background thread owns the
/// connection: it connects with the game's application ID, reconnects after
/// Discord restarts, and switches the connection when another game is selected.
public final class PresenceSession: @unchecked Sendable {
    public typealias Connector = @Sendable (_ applicationID: String) throws -> PresenceConnection

    private struct Request {
        var applicationID: String
        var activity: Activity
    }

    private let connector: Connector
    private let retryInterval: TimeInterval
    private let onStatusChange: @Sendable (PresenceStatus) -> Void

    // Guarded by `condition`; every change bumps `generation` so the worker notices it.
    private let condition = NSCondition()
    private var request: Request?
    private var generation = 0
    private var isRunning = true

    // Only touched by the worker thread.
    private var status: PresenceStatus = .idle
    private let finished = DispatchSemaphore(value: 0)

    /// `onStatusChange` is called on a background thread.
    public init(
        retryInterval: TimeInterval = 5,
        connector: @escaping Connector = { try DiscordIPCClient.connect(clientID: $0) },
        onStatusChange: @escaping @Sendable (PresenceStatus) -> Void
    ) {
        self.retryInterval = retryInterval
        self.connector = connector
        self.onStatusChange = onStatusChange
        let thread = Thread { [self] in run() }
        thread.name = "PresenceSession"
        thread.start()
    }

    public func show(applicationID: String, activity: Activity) {
        update { $0.request = Request(applicationID: applicationID, activity: activity) }
    }

    public func stop() {
        update { $0.request = nil }
    }

    /// Clears the status and ends the background thread.
    public func shutdown() {
        condition.lock()
        guard isRunning else {
            condition.unlock()
            return
        }
        isRunning = false
        condition.broadcast()
        condition.unlock()
        _ = finished.wait(timeout: .now() + 2)
    }

    private func update(_ change: (PresenceSession) -> Void) {
        condition.lock()
        change(self)
        generation += 1
        condition.broadcast()
        condition.unlock()
    }

    private func run() {
        var connection: PresenceConnection?
        var connectedID: String?
        var appliedGeneration: Int?
        var rejectedGeneration: Int?

        func disconnect(clearing: Bool) {
            if clearing {
                try? connection?.setActivity(nil)
            }
            connection?.close()
            connection = nil
            connectedID = nil
            appliedGeneration = nil
        }

        while true {
            condition.lock()
            let running = isRunning
            let request = self.request
            let generation = self.generation
            condition.unlock()

            guard running else {
                disconnect(clearing: true)
                break
            }
            guard let request else {
                if connection != nil { disconnect(clearing: true) }
                report(.idle)
                waitForChange(from: generation)
                continue
            }
            if rejectedGeneration == generation {
                waitForChange(from: generation)
                continue
            }
            if connection != nil && connectedID != request.applicationID {
                disconnect(clearing: true)
            }

            do {
                if connection == nil {
                    if status != .waitingForDiscord { report(.connecting) }
                    connection = try connector(request.applicationID)
                    connectedID = request.applicationID
                }
                if appliedGeneration != generation {
                    try connection?.setActivity(request.activity)
                    appliedGeneration = generation
                    report(.active)
                }
                // Short timeout so a newly selected game is picked up quickly.
                try connection?.pollIncoming(timeout: 0.25)
            } catch IPCError.discordError(_, let message) {
                disconnect(clearing: false)
                rejectedGeneration = generation
                report(.rejected(message))
            } catch {
                disconnect(clearing: false)
                report(.waitingForDiscord)
                waitForChange(from: generation, timeout: retryInterval)
            }
        }
        finished.signal()
    }

    private func report(_ newStatus: PresenceStatus) {
        guard newStatus != status else { return }
        status = newStatus
        onStatusChange(newStatus)
    }

    /// Blocks until `show`, `stop` or `shutdown` is called, or the timeout passes.
    private func waitForChange(from generation: Int, timeout: TimeInterval? = nil) {
        let deadline = timeout.map { Date().addingTimeInterval($0) }
        condition.lock()
        defer { condition.unlock() }
        while isRunning && self.generation == generation {
            if let deadline {
                if !condition.wait(until: deadline) { return }
            } else {
                condition.wait()
            }
        }
    }
}
