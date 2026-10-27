import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import PresenceCore

final class GameCatalogStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        StubProtocol.response = nil
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testLoadCachedReturnsNilWithoutUsableFile() throws {
        let store = makeStore()
        XCTAssertNil(store.loadCached())

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("garbage".utf8).write(to: store.cacheURL)
        XCTAssertNil(store.loadCached())
    }

    func testFetchDecodesAndCachesTheResponse() async throws {
        StubProtocol.response = (200, Data(#"[{"id":"1","name":"Minecraft"}]"#.utf8))
        let store = makeStore()

        let games = try await store.fetch()

        XCTAssertEqual(games, [Game(id: "1", name: "Minecraft")])
        XCTAssertEqual(store.loadCached(), games)
    }

    func testFetchFailsOnHTTPErrorAndKeepsTheOldCache() async throws {
        StubProtocol.response = (200, Data(#"[{"id":"1","name":"Minecraft"}]"#.utf8))
        let store = makeStore()
        _ = try await store.fetch()

        StubProtocol.response = (429, Data(#"{"message":"rate limited"}"#.utf8))
        do {
            _ = try await store.fetch()
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? CatalogError, .badResponse(statusCode: 429))
        }
        XCTAssertEqual(store.loadCached()?.map(\.name), ["Minecraft"])
    }

    private func makeStore() -> GameCatalogStore {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return GameCatalogStore(
            cacheURL: directory.appendingPathComponent("detectable.json"),
            session: URLSession(configuration: configuration)
        )
    }
}

/// Answers every request with `response` instead of going to the network.
private final class StubProtocol: URLProtocol {
    static var response: (status: Int, body: Data)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let (status, body) = Self.response,
              let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
