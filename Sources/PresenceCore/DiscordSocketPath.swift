import Foundation

/// Where the Discord desktop app listens for local IPC connections.
public enum DiscordSocketPath {
    /// All socket paths to try, in order. Discord looks for its directory in
    /// XDG_RUNTIME_DIR, TMPDIR, TMP and TEMP, falling back to /tmp, and names
    /// the socket `discord-ipc-0` through `discord-ipc-9` (on macOS this is
    /// usually `$TMPDIR/discord-ipc-0`).
    public static func candidates(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String] {
        var directories: [String] = []
        for key in ["XDG_RUNTIME_DIR", "TMPDIR", "TMP", "TEMP"] {
            if let value = environment[key], !value.isEmpty {
                directories.append(value)
            }
        }
        directories.append("/tmp")

        var seen = Set<String>()
        let unique = directories.map(trimmingTrailingSlashes).filter { seen.insert($0).inserted }
        return unique.flatMap { directory in
            (0...9).map { "\(directory)/discord-ipc-\($0)" }
        }
    }

    private static func trimmingTrailingSlashes(_ path: String) -> String {
        var path = path
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }
}
