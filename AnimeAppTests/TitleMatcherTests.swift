import XCTest
@testable import AnimeApp

final class TitleMatcherTests: XCTestCase {
    private var frieren: Anime {
        var anime = Anime(id: 52991, name: "Sousou no Frieren")
        anime.malID = 52991
        anime.russian = "Провожающая в последний путь Фрирен"
        anime.english = "Frieren: Beyond Journey's End"
        anime.year = 2023
        return anime
    }

    private func title(_ name: String, original: String? = nil, year: Int? = nil, shiki: Int? = nil, mal: Int? = nil) -> SourceTitle {
        SourceTitle(source: .aniLibria, id: UUID().uuidString, title: name, originalTitle: original, year: year, shikimoriID: shiki, malID: mal)
    }

    func testMatchesByShikimoriID() {
        XCTAssertTrue(TitleMatcher.isSame(frieren, title("Совсем другое имя", shiki: 52991)))
        XCTAssertFalse(TitleMatcher.isSame(frieren, title("Провожающая в последний путь Фрирен", year: 2023, shiki: 59978)))
    }

    func testMatchesByMALID() {
        XCTAssertTrue(TitleMatcher.isSame(frieren, title("Frieren", mal: 52991)))
        XCTAssertFalse(TitleMatcher.isSame(frieren, title("Sousou no Frieren", year: 2023, mal: 1)))
    }

    func testMatchesByNameAndYear() {
        XCTAssertTrue(TitleMatcher.isSame(frieren, title("ПРОВОЖАЮЩАЯ в последний путь Фрирен!", year: 2023)))
        XCTAssertTrue(TitleMatcher.isSame(frieren, title("Something", original: "Sousou no Frieren", year: 2023)))
        XCTAssertTrue(TitleMatcher.isSame(frieren, title("Sousou no Frieren", year: nil)))
    }

    func testRejectsDifferentYear() {
        XCTAssertFalse(TitleMatcher.isSame(frieren, title("Sousou no Frieren", year: 2026)))
    }

    func testFuzzyRequiresYear() {
        var anime = Anime(id: 1, name: "Shingeki no Kyojin Season 3 Part 2")
        anime.year = 2019
        XCTAssertFalse(TitleMatcher.isSame(anime, title("Shingeki no Kyojin Season 3 Part 2 TV", year: nil)))
        XCTAssertTrue(TitleMatcher.isSame(anime, title("Shingeki no Kyojin Season 3 Part 2 TV", year: 2019)))
    }

    func testYoAndCaseNormalization() {
        XCTAssertEqual(TextCleaner.normalizeTitle("Ёлка: Новый Год!"), TextCleaner.normalizeTitle("елка новый год"))
    }

    func testBestMatchPrefersID() throws {
        let candidates = [
            title("Sousou no Frieren", year: 2023),
            title("Провожающая в последний путь Фрирен", year: 2023, shiki: 52991),
            title("Sousou no Frieren 2nd Season", year: 2026, shiki: 59978),
        ]
        let best = try XCTUnwrap(TitleMatcher.bestMatch(for: frieren, in: candidates))
        XCTAssertEqual(best.shikimoriID, 52991)
    }

    func testMatchesRealFixtures() throws {
        let aniLibria = try AniLibriaParser.releases(from: Fixture.data("anilibria_search"))
        XCTAssertEqual(TitleMatcher.bestMatch(for: frieren, in: aniLibria)?.id, "9542")
        let yummy = try YummyParser.animes(from: Fixture.data("yummy_anime_list"))
        XCTAssertEqual(TitleMatcher.bestMatch(for: frieren, in: yummy)?.id, "10661")
    }
}
