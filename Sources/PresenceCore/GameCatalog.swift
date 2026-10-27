import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A game from Discord's list of detectable games. `id` is the game's
/// Discord application ID.
public struct Game: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let aliases: [String]
    public let iconHash: String?

    public init(id: String, name: String, aliases: [String] = [], iconHash: String? = nil) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.iconHash = iconHash
    }

    public var iconURL: URL? {
        guard let iconHash else { return nil }
        return URL(string: "https://cdn.discordapp.com/app-icons/\(id)/\(iconHash).png?size=64")
    }
}

extension Game: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, name, aliases, icon
        case iconHash = "icon_hash"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name).trimmingCharacters(in: .whitespacesAndNewlines)
        aliases = (try? container.decodeIfPresent([String].self, forKey: .aliases)) ?? []
        iconHash = (try? container.decodeIfPresent(String.self, forKey: .iconHash))
            ?? (try? container.decodeIfPresent(String.self, forKey: .icon))
    }
}

public enum CatalogError: Error, Equatable, LocalizedError {
    case badResponse(statusCode: Int?)
    case empty

    public var errorDescription: String? {
        switch self {
        case .badResponse(let statusCode?):
            return "Discord hat mit Fehler \(statusCode) geantwortet."
        case .badResponse(nil):
            return "Discord hat nicht geantwortet."
        case .empty:
            return "Der Spielekatalog ist leer."
        }
    }
}

public enum GameCatalog {
    public static let endpoint = URL(string: "https://discord.com/api/v9/applications/detectable")!

    /// Decodes Discord's response, skipping entries that don't fit (missing
    /// name, duplicate ID) instead of rejecting the whole list.
    public static func decode(_ data: Data) throws -> [Game] {
        let entries = try JSONDecoder().decode([LossyGame].self, from: data)
        var seen = Set<String>()
        return entries
            .compactMap(\.game)
            .filter { !$0.name.isEmpty && seen.insert($0.id).inserted }
            .sorted { $0.name.compare($1.name, options: [.caseInsensitive, .numeric]) == .orderedAscending }
    }

    private struct LossyGame: Decodable {
        let game: Game?

        init(from decoder: Decoder) throws {
            game = try? Game(from: decoder)
        }
    }
}

/// Searches a catalog by name and aliases, ignoring case and accents.
public struct GameIndex: Sendable {
    public let games: [Game]
    private let entries: [Entry]

    private struct Entry: Sendable {
        let name: String
        let words: [String]
        let aliases: [String]
    }

    /// `games` should already be sorted; results keep that order within each match quality.
    public init(games: [Game]) {
        self.games = games
        entries = games.map { game in
            let name = Self.normalize(game.name)
            return Entry(
                name: name,
                words: name.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init),
                aliases: game.aliases.map(Self.normalize)
            )
        }
    }

    /// Best matches first: exact name, name prefix, word prefix, name substring, alias substring.
    public func search(_ query: String) -> [Game] {
        let query = Self.normalize(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !query.isEmpty else { return games }
        return entries.indices
            .compactMap { index in Self.score(entries[index], query).map { (score: $0, index: index) } }
            .sorted { ($0.score, $0.index) < ($1.score, $1.index) }
            .map { games[$0.index] }
    }

    private static func score(_ entry: Entry, _ query: String) -> Int? {
        if entry.name == query { return 0 }
        if entry.name.hasPrefix(query) { return 1 }
        if entry.words.contains(where: { $0.hasPrefix(query) }) { return 2 }
        if entry.name.contains(query) { return 3 }
        if entry.aliases.contains(where: { $0.contains(query) }) { return 4 }
        return nil
    }

    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
    }
}

/// Downloads the catalog and keeps a copy on disk for offline starts.
public final class GameCatalogStore: @unchecked Sendable {
    public let cacheURL: URL
    private let session: URLSession

    public init(cacheURL: URL = GameCatalogStore.defaultCacheURL, session: URLSession = .shared) {
        self.cacheURL = cacheURL
        self.session = session
    }

    public static var defaultCacheURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PlayStatus", isDirectory: true)
            .appendingPathComponent("detectable.json")
    }

    /// The catalog from the last successful download, if there is one.
    public func loadCached() -> [Game]? {
        guard let data = try? Data(contentsOf: cacheURL),
              let games = try? GameCatalog.decode(data),
              !games.isEmpty
        else { return nil }
        return games
    }

    /// Downloads the current catalog and replaces the cached copy.
    public func fetch() async throws -> [Game] {
        var request = URLRequest(url: GameCatalog.endpoint)
        request.timeoutInterval = 30
        request.setValue("PlayStatus/1.0 (macOS)", forHTTPHeaderField: "User-Agent")
        let data = try await download(request)
        let games = try GameCatalog.decode(data)
        guard !games.isEmpty else { throw CatalogError.empty }
        try? FileManager.default.createDirectory(
            at: cacheURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: cacheURL, options: .atomic)
        return games
    }

    private func download(_ request: URLRequest) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            session.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let statusCode = (response as? HTTPURLResponse)?.statusCode
                guard let statusCode, (200..<300).contains(statusCode), let data else {
                    continuation.resume(throwing: CatalogError.badResponse(statusCode: statusCode))
                    return
                }
                continuation.resume(returning: data)
            }.resume()
        }
    }
}
