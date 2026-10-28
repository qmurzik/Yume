import Foundation

/// Shared API clients. Value types, so every view model can take its own copy.
struct AppServices: Sendable {
    var shikimori = ShikimoriAPI()
    var aniLibria = AniLibriaSource()
    var sources = SourceRegistry.live

    static let live = AppServices()
}
