import Foundation

/// AniLibria API v1 (https://aniliberty.top/api/docs/v1): releases, episodes with HLS in
/// 480/720/1080, opening/ending timecodes and the weekly schedule.
struct AniLibriaSource: AnimeSource {
    var http = HTTPClient()
    var baseURL = AppConfig.aniLibriaBaseURL

    let id = SourceID.aniLibria
    var isAvailable: Bool { true }

    private func api(_ path: String) -> URL {
        baseURL.appendingPathComponent("api/v1").appendingPathComponent(path)
    }

    func search(_ query: String) async throws -> [SourceTitle] {
        let data = try await http.get(api("app/search/releases"), query: [URLQueryItem(name: "query", value: query)])
        return try AniLibriaParser.releases(from: data, base: baseURL)
    }

    func findTitle(for anime: Anime) async throws -> SourceTitle? {
        // AniLibria's search exposes Shikimori and MAL ids, so the first query usually settles it.
        try await matchBySearch(anime, queries: [anime.name, anime.russian, anime.english].compactMap { $0 })
    }

    func episodes(for title: SourceTitle) async throws -> [SourceEpisode] {
        let data = try await http.get(api("anime/releases/\(title.id)"))
        return try AniLibriaParser.episodes(from: data, base: baseURL)
    }

    /// Re-requests the episode so stream links are always fresh.
    func stream(for episode: SourceEpisode) async throws -> StreamInfo {
        let data = try await http.get(api("anime/releases/episodes/\(episode.id)"))
        return try AniLibriaParser.stream(from: data)
    }

    func latest(limit: Int = 20) async throws -> [SourceTitle] {
        let data = try await http.get(api("anime/releases/latest"), query: [URLQueryItem(name: "limit", value: String(limit))])
        return try AniLibriaParser.releases(from: data, base: baseURL)
    }

    func weekSchedule() async throws -> [ScheduleEntry] {
        try AniLibriaParser.schedule(from: try await http.get(api("anime/schedule/week")), base: baseURL)
    }
}
