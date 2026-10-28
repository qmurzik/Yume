import XCTest
@testable import AnimeApp

final class YummyParsingTests: XCTestCase {
    func testParsesAnimeList() throws {
        let titles = try YummyParser.animes(from: Fixture.data("yummy_anime_list"))
        let frieren = try XCTUnwrap(titles.first)
        XCTAssertEqual(frieren.source, .yummy)
        XCTAssertEqual(frieren.id, "10661")
        XCTAssertEqual(frieren.shikimoriID, 52991)
        XCTAssertEqual(frieren.malID, 52991)
        XCTAssertEqual(frieren.posterURL?.scheme, "https")
    }

    func testParsesSearch() throws {
        let titles = try YummyParser.animes(from: Fixture.data("yummy_search"))
        XCTAssertFalse(titles.isEmpty)
    }

    func testParsesVideos() throws {
        let episodes = try YummyParser.episodes(from: Fixture.data("yummy_videos"))
        XCTAssertEqual(episodes.count, 5)
        let aksor = episodes.filter { $0.voice == "AniLibria · Aksor" }
        XCTAssertEqual(aksor.map(\.number), [1, 2, 3])
        XCTAssertEqual(aksor[1].opening, TimeRange(start: 0, end: 89))
        XCTAssertEqual(aksor[0].ending, TimeRange(start: 1456, end: 1545))
        XCTAssertNil(aksor[0].opening)
        XCTAssertTrue(episodes.allSatisfy { $0.id.hasPrefix("https://") })
    }

    func testStreamIsEmbed() async throws {
        let episode = try XCTUnwrap(YummyParser.episodes(from: Fixture.data("yummy_videos")).first)
        let stream = try await YummyAnimeSource(token: "test").stream(for: episode)
        guard case .embed(let url) = stream.kind else { return XCTFail("YummyAnime gives embeds") }
        XCTAssertEqual(url.absoluteString, episode.id)
    }

    func testUnavailableWithoutToken() async {
        let source = YummyAnimeSource(token: nil)
        XCTAssertFalse(source.isAvailable)
        do {
            _ = try await source.search("frieren")
            XCTFail("Must not hit the API without a token")
        } catch {
            XCTAssertEqual(error as? APIError, .sourceUnavailable("YummyAnime"))
        }
    }

    func testErrorEnvelope() {
        let data = Data(#"{"error":{"title":"Unauthorized","message":"Bad application token"}}"#.utf8)
        XCTAssertThrowsError(try YummyParser.animes(from: data)) { error in
            XCTAssertEqual(error as? APIError, .server("Bad application token"))
        }
    }
}
