import Foundation

/// Endpoints and app-wide settings. Domains come from the current official API docs:
/// Shikimori moved to shikimori.io, AniLibria's API v1 is served from aniliberty.top.
enum AppConfig {
    static let shikimoriBaseURL = URL(string: "https://shikimori.io")!
    static let aniLibriaBaseURL = URL(string: "https://aniliberty.top")!
    static let anime365BaseURL = URL(string: "https://smotret-anime.org")!
    static let animeVostBaseURL = URL(string: "https://api.animevost.org")!
    static let yummySiteURL = URL(string: "https://ru.yummyani.me")!
    static let yummyBaseURL = URL(string: "https://api.yani.tv")!

    /// Shikimori requires the application name in User-Agent and forbids mimicking a browser.
    static let userAgent: String = {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        return "AnimeApp/\(version) (iOS; +https://github.com/qmurzik/Yume)"
    }()

    /// YummyAnime public application token (X-Application header). Comes from
    /// Config/Secrets.xcconfig through Info.plist; empty when it isn't configured.
    static var yummyAppToken: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "YummyAppToken") as? String else { return nil }
        let token = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty || token.hasPrefix("$(") ? nil : token
    }
}
