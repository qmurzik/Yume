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

    func testRestrictedPlayerGoesLast() {
        func copy(_ number: Int, _ player: String) -> SourceEpisode {
            SourceEpisode(source: .yummy, id: "\(player)\(number)", number: Double(number), title: nil, voice: "AniDUB", player: player)
        }
        let all = (1...12).map { copy($0, "Kodik") } + (1...10).map { copy($0, "Alloha") }
        XCTAssertEqual(EpisodeGrouping.players(all, voice: "AniDUB"), ["Alloha", "Kodik"])
        let list = EpisodeGrouping.episodes(all, voice: "AniDUB", preferredPlayer: nil)
        XCTAssertEqual(list.count, 12)
        XCTAssertEqual(list.prefix(10).map(\.player), Array(repeating: "Alloha", count: 10))
        XCTAssertEqual(list.suffix(2).map(\.player), ["Kodik", "Kodik"], "only Kodik has 11 and 12")
    }

    func testSourcesWithoutPlayers() {
        let all = (1...3).map { SourceEpisode(source: .aniLibria, id: "\($0)", number: Double($0), title: nil, voice: "AniLibria") }
        XCTAssertEqual(EpisodeGrouping.players(all, voice: "AniLibria"), [])
        XCTAssertEqual(EpisodeGrouping.episodes(all, voice: "AniLibria", preferredPlayer: nil).count, 3)
    }
}

final class EmbedHealthTests: XCTestCase {
    func testRepeatedFailuresDeprioritizeForAWeek() {
        let defaults = UserDefaults(suiteName: "embed-health-\(UUID().uuidString)")!
        let health = EmbedHealth(defaults: defaults)
        let now = Date(timeIntervalSince1970: 1_000_000)
        health.recordFailure(player: "Aksor", now: now)
        XCTAssertFalse(health.deprioritized(now: now).contains("Aksor"), "one failure may be a fluke")
        health.recordFailure(player: "Aksor", now: now)
        XCTAssertTrue(health.deprioritized(now: now).contains("Aksor"))
        XCTAssertTrue(health.deprioritized(now: now).contains("Kodik"), "restricted players stay last")
        XCTAssertFalse(health.deprioritized(now: now.addingTimeInterval(8 * 24 * 3600)).contains("Aksor"))
    }
}
