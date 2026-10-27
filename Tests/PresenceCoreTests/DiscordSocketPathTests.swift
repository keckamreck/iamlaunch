import XCTest
import PresenceCore

final class DiscordSocketPathTests: XCTestCase {
    func testMacOSTemporaryDirectoryComesBeforeTmp() {
        let paths = DiscordSocketPath.candidates(environment: ["TMPDIR": "/var/folders/ab/xyz/T/"])

        XCTAssertEqual(paths.count, 20)
        XCTAssertEqual(paths.first, "/var/folders/ab/xyz/T/discord-ipc-0")
        XCTAssertEqual(paths[9], "/var/folders/ab/xyz/T/discord-ipc-9")
        XCTAssertEqual(paths[10], "/tmp/discord-ipc-0")
    }

    func testFollowsDiscordsLookupOrderAndSkipsDuplicatesAndEmptyValues() {
        let paths = DiscordSocketPath.candidates(environment: [
            "TEMP": "/tmp",
            "TMP": "",
            "TMPDIR": "/private/tmp/",
            "XDG_RUNTIME_DIR": "/run/user/1000",
        ])

        let directories = stride(from: 0, to: paths.count, by: 10).map {
            String(paths[$0].dropLast("/discord-ipc-0".count))
        }
        XCTAssertEqual(directories, ["/run/user/1000", "/private/tmp", "/tmp"])
    }
}
