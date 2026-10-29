import Foundation

/// Turns a source's flat episode list into voice-overs, players and one playable list per voice.
///
/// YummyAnime returns every voice-over once per embedded player (Aksor, Alloha, Kodik…), often
/// with gaps. The user picks a voice; each episode then comes from the preferred player, or from
/// the most complete other player when the preferred one lacks it.
enum EpisodeGrouping {
    /// Voices, most complete first (by distinct episode numbers), then by name.
    static func voices(_ all: [SourceEpisode]) -> [String] {
        let counts = Dictionary(grouping: all, by: \.voice).mapValues { Set($0.map(\.number)).count }
        return counts.keys.sorted { (counts[$0] ?? 0, $1) > (counts[$1] ?? 0, $0) }
    }

    /// Distinct episode numbers per voice.
    static func episodeCounts(_ all: [SourceEpisode]) -> [String: Int] {
        Dictionary(grouping: all, by: \.voice).mapValues { Set($0.map(\.number)).count }
    }

    /// Players whose embeds refuse to load outside their partner sites (Kodik answers
    /// "страницы не существует"); they are used only when no other player has the episode.
    static let restrictedPlayers: Set<String> = ["Kodik"]

    /// Players of a voice: working ones first, then most complete.
    static func players(_ all: [SourceEpisode], voice: String) -> [String] {
        let counts = Dictionary(grouping: all.filter { $0.voice == voice }, by: { $0.player ?? "" })
            .mapValues { Set($0.map(\.number)).count }
        func works(_ name: String) -> Int { restrictedPlayers.contains(name) ? 0 : 1 }
        return counts.keys.filter { !$0.isEmpty }.sorted {
            (works($0), counts[$0] ?? 0, $1) > (works($1), counts[$1] ?? 0, $0)
        }
    }

    /// One copy per episode number, sorted by number.
    static func episodes(_ all: [SourceEpisode], voice: String, preferredPlayer: String?) -> [SourceEpisode] {
        let ranking = rank(all, voice: voice, preferredPlayer: preferredPlayer)
        return Dictionary(grouping: all.filter { $0.voice == voice }, by: \.number)
            .compactMap { _, copies in copies.min { ranking($0) < ranking($1) } }
            .sorted { $0.number < $1.number }
    }

    /// Every copy of every episode of a voice, best first; keyed like `LibraryData.episodeKey`.
    static func alternatives(_ all: [SourceEpisode], voice: String, preferredPlayer: String?) -> [String: [SourceEpisode]] {
        let ranking = rank(all, voice: voice, preferredPlayer: preferredPlayer)
        return Dictionary(grouping: all.filter { $0.voice == voice }, by: { LibraryData.episodeKey($0.number) })
            .mapValues { $0.sorted { ranking($0) < ranking($1) } }
    }

    private static func rank(_ all: [SourceEpisode], voice: String, preferredPlayer: String?) -> (SourceEpisode) -> Int {
        var order = players(all, voice: voice)
        if let preferredPlayer, let index = order.firstIndex(of: preferredPlayer) {
            order.remove(at: index)
            order.insert(preferredPlayer, at: 0)
        }
        let positions = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) })
        return { episode in episode.player.flatMap { positions[$0] } ?? order.count }
    }
}
