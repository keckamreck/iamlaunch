import XCTest
import PresenceCore

final class PresenceSessionTests: XCTestCase {
    private let log = EventLog()
    private var session: PresenceSession?

    override func tearDown() {
        session?.shutdown()
    }

    func testShowConnectsAsTheGameAndSetsTheActivity() {
        let session = makeSession()

        session.show(applicationID: "minecraft", activity: Activity(startDate: Date()))

        waitFor { self.log.statuses.last == .active }
        XCTAssertEqual(log.events, ["connect minecraft", "set minecraft"])
        XCTAssertEqual(log.statuses, [.connecting, .active])
    }

    func testSwitchingGamesClearsTheOldConnectionFirst() {
        let session = makeSession()
        session.show(applicationID: "a", activity: Activity())
        waitFor { self.log.events.contains("set a") }

        session.show(applicationID: "b", activity: Activity())

        waitFor { self.log.events.contains("set b") }
        XCTAssertEqual(log.events, ["connect a", "set a", "clear a", "close a", "connect b", "set b"])
    }

    func testStopClearsTheStatus() {
        let session = makeSession()
        session.show(applicationID: "a", activity: Activity())
        waitFor { self.log.statuses.last == .active }

        session.stop()

        waitFor { self.log.statuses.last == .idle }
        XCTAssertEqual(log.events, ["connect a", "set a", "clear a", "close a"])
    }

    func testWaitsForDiscordAndRetries() {
        log.connectFailures = [IPCError.socketNotFound, IPCError.socketNotFound]
        let session = makeSession()

        session.show(applicationID: "a", activity: Activity())

        waitFor { self.log.statuses.last == .active }
        XCTAssertEqual(log.statuses, [.connecting, .waitingForDiscord, .active])
        XCTAssertEqual(log.events, ["connect a", "connect a", "connect a", "set a"])
    }

    func testReconnectsAfterDiscordRestartsAndKeepsTheStartTime() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        log.dropConnectionAfterPolls = 2
        let session = makeSession()

        session.show(applicationID: "a", activity: Activity(startDate: start))

        waitFor { self.log.events.filter { $0 == "set a" }.count == 2 }
        XCTAssertEqual(Array(log.events.prefix(4)), ["connect a", "set a", "close a", "connect a"])
        XCTAssertEqual(log.activities.compactMap { $0?.startDate }, [start, start])
    }

    func testRefusalIsReportedAndNotRetriedUntilAnotherGameIsChosen() {
        log.connectFailures = [IPCError.discordError(code: 4000, message: "Invalid Client ID")]
        let session = makeSession()

        session.show(applicationID: "bad", activity: Activity())
        waitFor { self.log.statuses.last == .rejected("Invalid Client ID") }
        Thread.sleep(forTimeInterval: 0.1)
        XCTAssertEqual(log.events, ["connect bad"])

        session.show(applicationID: "good", activity: Activity())
        waitFor { self.log.statuses.last == .active }
        XCTAssertEqual(log.events, ["connect bad", "connect good", "set good"])
    }

    func testShutdownClearsTheStatus() {
        let session = makeSession()
        session.show(applicationID: "a", activity: Activity())
        waitFor { self.log.statuses.last == .active }

        session.shutdown()

        XCTAssertEqual(log.events, ["connect a", "set a", "clear a", "close a"])
    }

    private func makeSession() -> PresenceSession {
        let log = self.log
        let session = PresenceSession(
            retryInterval: 0.02,
            connector: { id in try log.connect(id) },
            onStatusChange: { log.record($0) }
        )
        self.session = session
        return session
    }

    private func waitFor(_ condition: @escaping () -> Bool, file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(3)
        while !condition() {
            if Date() > deadline {
                XCTFail("timed out; events: \(log.events), statuses: \(log.statuses)", file: file, line: line)
                return
            }
            Thread.sleep(forTimeInterval: 0.005)
        }
    }
}

/// Records what the session does with its connections, and scripts failures.
private final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var _events: [String] = []
    private var _statuses: [PresenceStatus] = []
    private var _activities: [Activity?] = []
    var connectFailures: [Error] = []
    var dropConnectionAfterPolls: Int?

    var events: [String] { lock.synchronized { _events } }
    var statuses: [PresenceStatus] { lock.synchronized { _statuses } }
    var activities: [Activity?] { lock.synchronized { _activities } }

    func connect(_ id: String) throws -> PresenceConnection {
        let failure: Error? = lock.synchronized {
            _events.append("connect \(id)")
            return connectFailures.isEmpty ? nil : connectFailures.removeFirst()
        }
        if let failure { throw failure }
        let pollsBeforeDrop = lock.synchronized { () -> Int? in
            defer { dropConnectionAfterPolls = nil }
            return dropConnectionAfterPolls
        }
        return FakeConnection(id: id, log: self, pollsBeforeDrop: pollsBeforeDrop)
    }

    func record(_ status: PresenceStatus) {
        lock.synchronized { _statuses.append(status) }
    }

    func record(activity: Activity?, id: String) {
        lock.synchronized {
            _activities.append(activity)
            _events.append(activity == nil ? "clear \(id)" : "set \(id)")
        }
    }

    func record(event: String) {
        lock.synchronized { _events.append(event) }
    }
}

private final class FakeConnection: PresenceConnection {
    let id: String
    let log: EventLog
    var pollsBeforeDrop: Int?

    init(id: String, log: EventLog, pollsBeforeDrop: Int?) {
        self.id = id
        self.log = log
        self.pollsBeforeDrop = pollsBeforeDrop
    }

    func setActivity(_ activity: Activity?) throws {
        log.record(activity: activity, id: id)
    }

    func pollIncoming(timeout: TimeInterval) throws {
        if let remaining = pollsBeforeDrop {
            if remaining == 0 { throw IPCError.connectionClosed }
            pollsBeforeDrop = remaining - 1
        }
        Thread.sleep(forTimeInterval: min(timeout, 0.005))
    }

    func close() {
        log.record(event: "close \(id)")
    }
}

private extension NSLock {
    func synchronized<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
