import XCTest
@testable import AnimeApp

final class Anime365ParsingTests: XCTestCase {
    func testSeriesMatchesByMALID() throws {
        let series = try Anime365Parser.series(from: Fixture.data("anime365_series"))
        let title = series.model
        XCTAssertEqual(title.source, .anime365)
        XCTAssertEqual(title.id, "4036")
        XCTAssertEqual(title.malID, 16498)
        XCTAssertEqual(title.title, "Атака титанов")
        XCTAssertEqual(title.originalTitle, "Shingeki no Kyojin")
        XCTAssertNotNil(title.webURL)

        var anime = Anime(id: 16498, name: "Shingeki no Kyojin")
        anime.malID = 16498
        anime.year = 2013
        XCTAssertTrue(TitleMatcher.isSame(anime, title))
    }

    func testRussianVoicesOnlyAndPreviewsSkipped() throws {
        let series = try Anime365Parser.series(from: Fixture.data("anime365_series"))
        let episodes = try Anime365Parser.episodes(series: series, translationsData: Fixture.data("anime365_translations"))
        XCTAssertEqual(Set(episodes.map(\.voice)), ["AniLibria (Eladiel & Zendos)", "Wakanim"])
        XCTAssertEqual(EpisodeGrouping.episodes(episodes, voice: "Wakanim", preferredPlayer: nil).map(\.number), [1, 2, 3])
        XCTAssertTrue(episodes.allSatisfy { $0.player == "BD 1080p" })
        XCTAssertTrue(episodes.allSatisfy { Int($0.id) != nil })
    }

    func testEmbedStreams() throws {
        let json = #"{"data":{"stream":[{"height":720,"urls":["https://cdn.example/720.mp4"]},{"height":1080,"urls":["//cdn.example/1080.mp4"]}],"subtitlesUrl":null}}"#
        let stream = try Anime365Parser.stream(from: Data(json.utf8))
        XCTAssertEqual(stream.qualities.map(\.height), [1080, 720])
        XCTAssertEqual(stream.qualities.first?.url.scheme, "https")
    }

    func testEmbedWithoutLoginExplainsWhy() {
        let json = #"{"error":{"code":403,"message":"You should login first."}}"#
        XCTAssertThrowsError(try Anime365Parser.stream(from: Data(json.utf8))) { error in
            XCTAssertTrue(error.localizedDescription.contains("Anime365"))
        }
    }

    func testGuestProfile() throws {
        let json = #"{"data":{"isLogined":false,"id":0,"name":"Гость","isPremium":false,"premiumUntil":"2000-01-01 00:00:00"}}"#
        let me = try Anime365Parser.me(from: Data(json.utf8))
        XCTAssertEqual(me.isLogined, false)
        XCTAssertEqual(me.isPremium, false)
    }
}
