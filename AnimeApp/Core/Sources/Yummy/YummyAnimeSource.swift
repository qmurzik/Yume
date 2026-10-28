import Foundation

/// YummyAnime API (https://api.yani.tv/swagger): many voice-overs, played through the
/// providers' official embeddable players. Needs a public application token (X-Application) from
/// the build config or from signing in on the Settings screen; without it the source stays off.
struct YummyAnimeSource: AnimeSource {
    /// Read on every request, so signing in or out in Settings applies immediately.
    private let tokenProvider: @Sendable () -> String?
    var baseURL = AppConfig.yummyBaseURL

    init() {
        tokenProvider = { YummyCredentials.shared.appToken }
    }

    /// Fixed key, for tests.
    init(token: String?) {
        tokenProvider = { token }
    }

    var token: String? { tokenProvider() }

    let id = SourceID.yummy
    var isAvailable: Bool { token != nil }

    private var http: HTTPClient {
        HTTPClient(defaultHeaders: [
            "X-Application": token ?? "",
            "Accept": "application/json, image/avif, image/webp",
            "Lang": "ru",
        ])
    }

    private func requireToken() throws {
        guard isAvailable else { throw APIError.sourceUnavailable(id.title) }
    }

    func search(_ query: String) async throws -> [SourceTitle] {
        try requireToken()
        let data = try await http.get(baseURL.appendingPathComponent("search"), query: [
            URLQueryItem(name: "q", value: query), URLQueryItem(name: "limit", value: "20"),
        ])
        return try YummyParser.animes(from: data)
    }

    func findTitle(for anime: Anime) async throws -> SourceTitle? {
        try requireToken()
        let data = try await http.get(baseURL.appendingPathComponent("anime"), query: [
            URLQueryItem(name: "shikimori_ids", value: String(anime.id)), URLQueryItem(name: "limit", value: "1"),
        ])
        if let direct = try YummyParser.animes(from: data).first(where: { TitleMatcher.isSame(anime, $0) }) {
            return direct
        }
        return try await matchBySearch(anime, queries: [anime.russian, anime.name].compactMap { $0 })
    }

    func episodes(for title: SourceTitle) async throws -> [SourceEpisode] {
        try requireToken()
        let data = try await http.get(baseURL.appendingPathComponent("anime/\(title.id)/videos"))
        return try YummyParser.episodes(from: data)
    }

    func stream(for episode: SourceEpisode) async throws -> StreamInfo {
        guard let url = URL(string: episode.id) else { throw APIError.invalidURL }
        return StreamInfo(kind: .embed(url), opening: episode.opening, ending: episode.ending)
    }
}
