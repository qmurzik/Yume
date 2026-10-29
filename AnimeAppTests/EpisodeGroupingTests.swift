import XCTest
@testable import AnimeApp

final class EpisodeGroupingTests: XCTestCase {
    private func episodes() throws -> [SourceEpisode] {
        try YummyParser.episodes(from: Fixture.data("yummy_videos"))
    }

    func testOneVoiceForAllPlayers() throws {
        let all = try episodes()
        XCTAssertEqual(EpisodeGrouping.voices(all), ["AniLibria"])
        XCTAssertEqual(EpisodeGrouping.episodeCounts(all)["AniLibria"], 3)
        XCTAssertEqual(EpisodeGrouping.players(all, voice: "AniLibria"), ["Aksor", "Kodik"])
    }

    func testMostCompletePlayerByDefault() throws {
        let list = EpisodeGrouping.episodes(try episodes(), voice: "AniLibria", preferredPlayer: nil)
        XCTAssertEqual(list.map(\.number), [1, 2, 3])
        XCTAssertEqual(list.map(\.player), ["Aksor", "Aksor", "Aksor"])
    }

    func testPreferredPlayerWithFallbackForGaps() throws {
        let list = EpisodeGrouping.episodes(try episodes(), voice: "AniLibria", preferredPlayer: "Kodik")
        XCTAssertEqual(list.map(\.number), [1, 2, 3])
        XCTAssertEqual(list.map(\.player), ["Kodik", "Kodik", "Aksor"], "episode 3 exists only in Aksor")
    }

    func testAlternativesPerEpisode() throws {
        let alternatives = EpisodeGrouping.alternatives(try episodes(), voice: "AniLibria", preferredPlayer: "Kodik")
        XCTAssertEqual(alternatives["1"]?.map(\.player), ["Kodik", "Aksor"])
        XCTAssertEqual(alternatives["3"]?.map(\.player), ["Aksor"])
    }

    func testSourcesWithoutPlayers() {
        let all = (1...3).map { SourceEpisode(source: .aniLibria, id: "\($0)", number: Double($0), title: nil, voice: "AniLibria") }
        XCTAssertEqual(EpisodeGrouping.players(all, voice: "AniLibria"), [])
        XCTAssertEqual(EpisodeGrouping.episodes(all, voice: "AniLibria", preferredPlayer: nil).count, 3)
    }
}
