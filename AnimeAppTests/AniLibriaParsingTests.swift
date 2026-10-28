import XCTest
@testable import AnimeApp

final class AniLibriaParsingTests: XCTestCase {
    func testParsesSearch() throws {
        let titles = try AniLibriaParser.releases(from: Fixture.data("anilibria_search"))
        let frieren = try XCTUnwrap(titles.first)
        XCTAssertEqual(frieren.source, .aniLibria)
        XCTAssertEqual(frieren.id, "9542")
        XCTAssertEqual(frieren.shikimoriID, 52991)
        XCTAssertEqual(frieren.malID, 52991)
        XCTAssertEqual(frieren.year, 2023)
        XCTAssertEqual(frieren.originalTitle, "Sousou no Frieren")
        XCTAssertEqual(frieren.posterURL?.host, "aniliberty.top")
    }

    func testParsesReleaseEpisodes() throws {
        let episodes = try AniLibriaParser.episodes(from: Fixture.data("anilibria_release"))
        XCTAssertEqual(episodes.count, 3)
        let first = try XCTUnwrap(episodes.first)
        XCTAssertEqual(first.number, 1)
        XCTAssertEqual(first.voice, "AniLibria")
        XCTAssertEqual(first.duration, 1560)
        XCTAssertEqual(first.id, "9a416b99-4487-4d8a-960a-461089d36cad")
        XCTAssertEqual(first.displayTitle, "1. «Конец приключений»")
        XCTAssertNotNil(first.previewURL)
    }

    func testParsesEpisodeStream() throws {
        let stream = try AniLibriaParser.stream(from: Fixture.data("anilibria_episode"))
        XCTAssertEqual(stream.qualities.map(\.height), [1080, 720, 480])
        XCTAssertTrue(stream.qualities.allSatisfy { $0.url.pathExtension == "m3u8" })
        guard case .native = stream.kind else { return XCTFail("AniLibria must give HLS for AVPlayer") }
    }

    func testOpeningTimecodes() throws {
        let json = #"{"id":"x","opening":{"start":5,"stop":95},"ending":{"start":null,"stop":null},"hls_720":"https://a.b/c.m3u8"}"#
        let stream = try AniLibriaParser.stream(from: Data(json.utf8))
        XCTAssertEqual(stream.opening, TimeRange(start: 5, end: 95))
        XCTAssertNil(stream.ending)
    }

    func testEpisodeWithoutStreamsFails() {
        let json = #"{"id":"x","hls_480":null,"hls_720":null,"hls_1080":null}"#
        XCTAssertThrowsError(try AniLibriaParser.stream(from: Data(json.utf8)))
    }

    func testParsesSchedule() throws {
        let entries = try AniLibriaParser.schedule(from: Fixture.data("anilibria_schedule"))
        XCTAssertFalse(entries.isEmpty)
        XCTAssertTrue(entries.allSatisfy { (1...7).contains($0.weekday) })
        XCTAssertEqual(entries.first?.title.shikimoriID, 269)
        XCTAssertEqual(entries.first?.nextEpisode, 358)
    }

    func testParsesLatest() throws {
        let titles = try AniLibriaParser.releases(from: Fixture.data("anilibria_latest"))
        XCTAssertEqual(titles.count, 2)
        XCTAssertTrue(titles.allSatisfy { !$0.title.isEmpty })
    }
}
