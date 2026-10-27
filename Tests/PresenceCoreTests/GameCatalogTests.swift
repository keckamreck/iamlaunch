import XCTest
@testable import PresenceCore

final class GameCatalogTests: XCTestCase {
    func testDecodeSkipsBrokenAndDuplicateEntriesAndSortsByName() throws {
        let json = """
        [
          {"id": "3", "name": "Valorant", "aliases": ["Valo"], "icon_hash": "abc", "executables": []},
          {"id": "1", "name": "  among us "},
          {"id": "2"},
          {"id": "3", "name": "Valorant (duplicate)"},
          {"id": "4", "name": "Game 10"},
          {"id": "5", "name": "Game 2", "icon": "def"},
          {"name": "No ID"}
        ]
        """

        let games = try GameCatalog.decode(Data(json.utf8))

        XCTAssertEqual(games.map(\.name), ["among us", "Game 2", "Game 10", "Valorant"])
        XCTAssertEqual(games[3].aliases, ["Valo"])
        XCTAssertEqual(games[0].aliases, [])
        XCTAssertEqual(games[3].iconURL?.absoluteString, "https://cdn.discordapp.com/app-icons/3/abc.png?size=64")
        XCTAssertEqual(games[1].iconHash, "def")
        XCTAssertNil(games[0].iconURL)
    }

    func testDecodeRejectsSomethingThatIsNotAList() {
        XCTAssertThrowsError(try GameCatalog.decode(Data(#"{"message":"429: Too Many Requests"}"#.utf8)))
    }

    func testSearchRanksExactThenPrefixThenWordThenSubstringThenAlias() {
        let index = GameIndex(games: [
            Game(id: "1", name: "Rust"),
            Game(id: "2", name: "Rusty Lake"),
            Game(id: "3", name: "Trust Me"),
            Game(id: "4", name: "Iron Rust"),
            Game(id: "5", name: "Unrelated", aliases: ["rustacean"]),
            Game(id: "6", name: "Minecraft"),
        ])

        XCTAssertEqual(index.search("rust").map(\.id), ["1", "2", "4", "3", "5"])
    }

    func testSearchIgnoresCaseAccentsAndSurroundingSpaces() {
        let index = GameIndex(games: [
            Game(id: "1", name: "Pokémon Legends"),
            Game(id: "2", name: "Counter-Strike 2"),
        ])

        XCTAssertEqual(index.search("  POKEMON ").map(\.id), ["1"])
        XCTAssertEqual(index.search("strike").map(\.id), ["2"])
        XCTAssertEqual(index.search("zelda"), [])
    }

    func testEmptySearchReturnsWholeCatalogInOrder() {
        let games = [Game(id: "1", name: "A"), Game(id: "2", name: "B")]

        XCTAssertEqual(GameIndex(games: games).search(""), games)
    }
}
