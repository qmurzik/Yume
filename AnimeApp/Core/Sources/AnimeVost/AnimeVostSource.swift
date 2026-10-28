import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// AnimeVost public API (api.animevost.org/v1): own voice-over, direct MP4 files in 480p and 720p,
/// played natively with AVPlayer. The API has no Shikimori/MAL ids, so titles are matched by name and year.
struct AnimeVostSource: AnimeSource {
    var http = HTTPClient()
    var baseURL = AppConfig.animeVostBaseURL

    let id = SourceID.animeVost
    var isAvailable: Bool { true }

    private func post(_ path: String, _ fields: [String: String]) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1").appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        var components = URLComponents()
        components.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        // URLComponents leaves "+" unescaped, which a form body would read as a space.
        request.httpBody = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
            .data(using: .utf8)
        return try await http.data(for: request)
    }

    func search(_ query: String) async throws -> [SourceTitle] {
        do {
            return try AnimeVostParser.releases(from: try await post("search", ["name": query]))
        } catch APIError.notFound {
            // "Nothing found" is answered with HTTP 404.
            return []
        }
    }

    func findTitle(for anime: Anime) async throws -> SourceTitle? {
        // The original (romaji) title is what AnimeVost stores after the slash, so try it first.
        try await matchBySearch(anime, queries: [anime.name, anime.russian, anime.english].compactMap { $0 })
    }

    func episodes(for title: SourceTitle) async throws -> [SourceEpisode] {
        try AnimeVostParser.episodes(from: try await post("playlist", ["id": title.id]), releaseID: title.id)
    }

    func stream(for episode: SourceEpisode) async throws -> StreamInfo {
        let qualities = AnimeVostParser.decode(episode.id)
        guard !qualities.isEmpty else { throw APIError.server("Для этой серии нет видео.") }
        return StreamInfo(kind: .native(qualities), opening: nil, ending: nil)
    }
}
