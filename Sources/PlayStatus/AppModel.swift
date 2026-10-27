import Combine
import Foundation
import PresenceCore

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    enum CatalogState: Equatable {
        case loading
        case ready
        case failed(String)
    }

    @Published private(set) var catalogState: CatalogState = .loading
    @Published private(set) var index = GameIndex(games: [])
    @Published var query = ""
    @Published private(set) var activeGame: Game?
    @Published private(set) var activeSince: Date?
    @Published private(set) var status: PresenceStatus = .idle

    private let store = GameCatalogStore()
    private var session: PresenceSession!

    var results: [Game] {
        index.search(query)
    }

    private init() {
        session = PresenceSession(onStatusChange: { [weak self] status in
            Task { @MainActor [weak self] in self?.status = status }
        })
        loadCatalog()
    }

    /// Shows the cached catalog right away, then replaces it with a fresh download.
    func loadCatalog() {
        if index.games.isEmpty {
            catalogState = .loading
        }
        let store = self.store
        Task {
            if index.games.isEmpty, let cached = await Self.cachedIndex(store) {
                apply(cached)
            }
            do {
                apply(try await Self.downloadedIndex(store))
            } catch {
                if index.games.isEmpty {
                    catalogState = .failed(error.localizedDescription)
                }
            }
        }
    }

    func show(_ game: Game) {
        let start = Date()
        activeGame = game
        activeSince = start
        session.show(applicationID: game.id, activity: Activity(startDate: start))
    }

    func stop() {
        activeGame = nil
        activeSince = nil
        session.stop()
    }

    func shutdown() {
        session.shutdown()
    }

    private func apply(_ newIndex: GameIndex) {
        index = newIndex
        catalogState = .ready
    }

    // Decoding and indexing thousands of games takes a moment, so it runs off the main thread.

    private nonisolated static func cachedIndex(_ store: GameCatalogStore) async -> GameIndex? {
        store.loadCached().map { GameIndex(games: $0) }
    }

    private nonisolated static func downloadedIndex(_ store: GameCatalogStore) async throws -> GameIndex {
        GameIndex(games: try await store.fetch())
    }
}
