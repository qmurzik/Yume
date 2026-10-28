import XCTest
@testable import AnimeApp

final class ShikimoriParsingTests: XCTestCase {
    func testParsesAnimeDetail() throws {
        let animes = try ShikimoriParser.animes(from: Fixture.data("shikimori_anime_detail"))
        let frieren = try XCTUnwrap(animes.first)

        XCTAssertEqual(frieren.id, 52991)
        XCTAssertEqual(frieren.malID, 52991)
        XCTAssertEqual(frieren.name, "Sousou no Frieren")
        XCTAssertEqual(frieren.title, "Провожающая в последний путь Фрирен")
        XCTAssertEqual(frieren.kind, .tv)
        XCTAssertEqual(frieren.status, .released)
        XCTAssertEqual(frieren.episodes, 28)
        XCTAssertEqual(frieren.year, 2023)
        XCTAssertEqual(frieren.score ?? 0, 9.25, accuracy: 0.01)
        XCTAssertEqual(frieren.studios, ["Madhouse"])
        XCTAssertTrue(frieren.genres.contains { $0.russian == "Фэнтези" })
        XCTAssertEqual(frieren.posterURL?.host, "shikimori.io")
        XCTAssertFalse(frieren.description?.contains("[character") ?? true, "BB-codes must be stripped")
        XCTAssertTrue(frieren.related.contains { $0.relation == "Продолжение" && $0.anime.id == 59978 })
        // Related entries without an anime (manga adaptations) are skipped.
        XCTAssertTrue(frieren.related.allSatisfy { $0.anime.id > 0 })
    }

    func testParsesCatalogPage() throws {
        let animes = try ShikimoriParser.animes(from: Fixture.data("shikimori_animes"))
        XCTAssertEqual(animes.count, 3)
        XCTAssertTrue(animes.allSatisfy { $0.status == .ongoing })
        XCTAssertTrue(animes.allSatisfy { $0.posterURL != nil })
    }

    func testParsesGenres() throws {
        let genres = try ShikimoriParser.genres(from: Fixture.data("shikimori_genres"))
        XCTAssertFalse(genres.isEmpty)
        XCTAssertTrue(genres.contains { $0.id == 10 && $0.title == "Фэнтези" })
    }

    func testParsesSimilarIDs() throws {
        let ids = try ShikimoriParser.similarIDs(from: Fixture.data("shikimori_similar"))
        XCTAssertEqual(ids.first, 33352)
        XCTAssertEqual(ids.count, 4)
    }

    func testGraphQLErrorsBecomeAPIError() {
        let data = Data(#"{"errors":[{"message":"Query has depth of 7"}]}"#.utf8)
        XCTAssertThrowsError(try ShikimoriParser.animes(from: data)) { error in
            XCTAssertEqual(error as? APIError, .server("Query has depth of 7"))
        }
    }

    func testCatalogRequestArguments() {
        var query = CatalogQuery()
        query.genreIDs = [10, 2]
        query.year = 2023
        query.season = .fall
        query.status = .released
        query.order = .ranked
        let (text, variables) = ShikimoriAPI.animesRequest(query: query, page: 2, limit: 30)

        XCTAssertTrue(text.contains("genre: $genre"))
        XCTAssertTrue(text.contains("$season: SeasonString"))
        XCTAssertEqual(variables["genre"], .string("2,10"))
        XCTAssertEqual(variables["season"], .string("fall_2023"))
        XCTAssertEqual(variables["status"], .string("released"))
        XCTAssertEqual(variables["order"], .string("ranked"))
        XCTAssertEqual(variables["page"], .int(2))
        XCTAssertEqual(variables["kind"], .string("!music,!pv,!cm"))
    }

    func testSeasonArgument() {
        XCTAssertNil(CatalogQuery().seasonArgument())
        XCTAssertEqual(CatalogQuery(year: 2020).seasonArgument(), "2020")
        XCTAssertEqual(CatalogQuery(season: .winter).seasonArgument(currentYear: 2026), "winter_2026")
    }

    func testStripBBCode() {
        let text = "Отряд [character=186854]Химмеля[/character] вернулся. [b]Жирный[/b] [url=https://x.y]ссылка[/url]"
        XCTAssertEqual(TextCleaner.stripBBCode(text), "Отряд Химмеля вернулся. Жирный ссылка")
    }
}
