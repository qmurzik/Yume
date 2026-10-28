import XCTest
@testable import AnimeApp

final class AnimeVostParsingTests: XCTestCase {
    func testParsesSearch() throws {
        let titles = try AnimeVostParser.releases(from: Fixture.data("animevost_search"))
        XCTAssertEqual(titles.count, 2)
        let first = try XCTUnwrap(titles.first)
        XCTAssertEqual(first.source, .animeVost)
        XCTAssertEqual(first.id, "3044")
        XCTAssertEqual(first.title, "Провожающая в последний путь Фрирен")
        XCTAssertEqual(first.originalTitle, "Sousou no Frieren")
        XCTAssertEqual(first.year, 2023)
        XCTAssertEqual(titles[1].originalTitle, "Sousou no Frieren 2nd Season")
    }

    func testNothingFoundIsEmpty() throws {
        let data = Data(#"{"error":"Ничего не найдено"}"#.utf8)
        XCTAssertEqual(try AnimeVostParser.releases(from: data), [])
    }

    func testParsesPlaylist() throws {
        let episodes = try AnimeVostParser.episodes(from: Fixture.data("animevost_playlist"), releaseID: "3044")
        XCTAssertEqual(episodes.map(\.number), [1, 2, 3])
        let first = try XCTUnwrap(episodes.first)
        XCTAssertNil(first.title, "regular \"N серия\" names don't repeat as titles")
        XCTAssertEqual(first.voice, "AnimeVost")
        XCTAssertEqual(first.previewURL?.scheme, "https")
    }

    func testStreamCarriesBothQualitiesOverHTTPS() async throws {
        let episode = try XCTUnwrap(AnimeVostParser.episodes(from: Fixture.data("animevost_playlist"), releaseID: "3044").first)
        let stream = try await AnimeVostSource().stream(for: episode)
        XCTAssertEqual(stream.qualities.map(\.height), [720, 480])
        XCTAssertTrue(stream.qualities.allSatisfy { $0.url.scheme == "https" && $0.url.pathExtension == "mp4" })
        guard case .native = stream.kind else { return XCTFail("AnimeVost files play natively") }
    }

    func testOngoingTitleWithSeveralBrackets() {
        let release = AnimeVostDTO.Release(
            id: .init(value: "4058"),
            title: "Чёрный клевер (второй сезон) / Black Clover 2nd Season [1-4 из 12+] [5 серия - 31 октября]",
            year: .init(value: "2026"),
            type: "ТВ",
            urlImagePreview: nil
        )
        XCTAssertEqual(release.model.title, "Чёрный клевер (второй сезон)")
        XCTAssertEqual(release.model.originalTitle, "Black Clover 2nd Season")
        XCTAssertEqual(release.model.year, 2026)
    }

    func testSpecialEpisodeNames() {
        XCTAssertEqual(AnimeVostParser.episodeNumber("12 серия"), 12)
        XCTAssertEqual(AnimeVostParser.episodeNumber("6,5 серия"), 6.5)
        XCTAssertNil(AnimeVostParser.episodeNumber("OVA"))
    }

    func testMatchesShikimoriByOriginalTitleAndYear() throws {
        let titles = try AnimeVostParser.releases(from: Fixture.data("animevost_search"))
        var season2 = Anime(id: 59978, name: "Sousou no Frieren 2nd Season")
        season2.russian = "Провожающая в последний путь Фрирен 2"
        season2.year = 2026
        XCTAssertEqual(TitleMatcher.bestMatch(for: season2, in: titles)?.id, "3706")

        var season1 = Anime(id: 52991, name: "Sousou no Frieren")
        season1.year = 2023
        XCTAssertEqual(TitleMatcher.bestMatch(for: season1, in: titles)?.id, "3044")
    }
}
