import Foundation

/// A playback source: finds a title, lists its episodes and resolves stream links.
protocol AnimeSource: Sendable {
    var id: SourceID { get }
    /// False when the source cannot be used, e.g. its application key isn't configured.
    var isAvailable: Bool { get }

    func search(_ query: String) async throws -> [SourceTitle]
    /// Finds the source's entry for a Shikimori title: by Shikimori/MAL id when the API
    /// exposes it, otherwise by title and year.
    func findTitle(for anime: Anime) async throws -> SourceTitle?
    func episodes(for title: SourceTitle) async throws -> [SourceEpisode]
    func stream(for episode: SourceEpisode) async throws -> StreamInfo
}

extension AnimeSource {
    var displayName: String { id.title }

    /// Searches by every known name of the title until a match is found.
    func matchBySearch(_ anime: Anime, queries: [String]) async throws -> SourceTitle? {
        var seen = Set<String>()
        for query in queries where !query.isEmpty && seen.insert(TextCleaner.normalizeTitle(query)).inserted {
            let candidates = try await search(query)
            if let match = TitleMatcher.bestMatch(for: anime, in: candidates) { return match }
        }
        return nil
    }
}

/// All playback sources the app knows about, in the order they are offered.
struct SourceRegistry: Sendable {
    var sources: [any AnimeSource]

    static let live = SourceRegistry(sources: [AniLibriaSource(), AnimeVostSource(), Anime365Source(), YummyAnimeSource()])

    var available: [any AnimeSource] { sources.filter(\.isAvailable) }

    func source(_ id: SourceID) -> (any AnimeSource)? {
        available.first { $0.id == id }
    }
}
