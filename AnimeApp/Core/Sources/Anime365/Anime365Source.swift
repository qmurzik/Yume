import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Anime365 (smotret-anime.org) public API: the catalogue and translations are open, and direct
/// video links are given to signed-in accounts with an active subscription — the user signs in on
/// the site inside the app and requests go with that session's cookies.
struct Anime365Source: AnimeSource {
    var http = HTTPClient()
    var baseURL = AppConfig.anime365BaseURL
    private let signedIn: @Sendable () -> Bool

    init(signedIn: @escaping @Sendable () -> Bool = { Anime365Account.shared.isSignedIn }) {
        self.signedIn = signedIn
    }

    let id = SourceID.anime365
    var isAvailable: Bool { signedIn() }

    private func api(_ path: String) -> URL {
        baseURL.appendingPathComponent("api").appendingPathComponent(path)
    }

    private static let seriesFields = "id,myAnimeListId,year,type,titles,url,posterUrlSmall"

    func search(_ query: String) async throws -> [SourceTitle] {
        let data = try await http.get(api("series"), query: [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "limit", value: "20"),
            URLQueryItem(name: "fields", value: Self.seriesFields),
        ])
        return try Anime365Parser.seriesList(from: data)
    }

    func findTitle(for anime: Anime) async throws -> SourceTitle? {
        if let mal = anime.malID {
            let data = try await http.get(api("series"), query: [
                URLQueryItem(name: "myAnimeListId", value: String(mal)),
                URLQueryItem(name: "fields", value: Self.seriesFields),
            ])
            if let match = try Anime365Parser.seriesList(from: data).first(where: { TitleMatcher.isSame(anime, $0) }) {
                return match
            }
        }
        return try await matchBySearch(anime, queries: [anime.name, anime.russian].compactMap { $0 })
    }

    func episodes(for title: SourceTitle) async throws -> [SourceEpisode] {
        async let seriesData = http.get(api("series/\(title.id)"), query: [
            URLQueryItem(name: "fields", value: "id,episodes"),
        ])
        async let translationsData = http.get(api("translations"), query: [
            URLQueryItem(name: "seriesId", value: title.id),
            URLQueryItem(name: "limit", value: "5000"),
            URLQueryItem(name: "fields", value: "id,episodeId,typeKind,typeLang,authorsSummary,qualityType,height,isActive,duration"),
        ])
        let series = try Anime365Parser.series(from: try await seriesData)
        return try Anime365Parser.episodes(series: series, translationsData: try await translationsData)
    }

    func stream(for episode: SourceEpisode) async throws -> StreamInfo {
        try Anime365Parser.stream(from: try await http.get(api("translations/embed/\(episode.id)")))
    }

    /// Who is signed in, using the stored session cookies.
    func me() async throws -> Anime365DTO.Me {
        try Anime365Parser.me(from: try await http.get(api("me")))
    }
}

/// Signed-in state of the Anime365 web session (its cookies live in the shared cookie storage).
final class Anime365Account: @unchecked Sendable {
    static let shared = Anime365Account()
    static let didChange = Notification.Name("Anime365AccountDidChange")

    private let defaults = UserDefaults.standard
    private let nameKey = "anime365.name"
    private let premiumKey = "anime365.premiumUntil"

    var isSignedIn: Bool { defaults.string(forKey: nameKey) != nil }
    var name: String? { defaults.string(forKey: nameKey) }
    var premiumUntil: String? { defaults.string(forKey: premiumKey) }

    func save(name: String, premiumUntil: String?) {
        defaults.set(name, forKey: nameKey)
        defaults.set(premiumUntil, forKey: premiumKey)
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    func signOut() {
        defaults.removeObject(forKey: nameKey)
        defaults.removeObject(forKey: premiumKey)
        if let cookies = HTTPCookieStorage.shared.cookies {
            for cookie in cookies where Self.isAnime365(domain: cookie.domain) {
                HTTPCookieStorage.shared.deleteCookie(cookie)
            }
        }
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    static func isAnime365(domain: String) -> Bool {
        let host = domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        return ["smotret-anime.org", "smotret-anime.co", "smotret-anime.ru", "anime365.ru"].contains { host == $0 || host.hasSuffix("." + $0) }
    }
}
