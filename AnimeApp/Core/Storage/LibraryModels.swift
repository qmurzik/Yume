import Foundation

/// Snapshot of a title kept locally, so the library works offline.
struct SavedAnime: Identifiable, Hashable, Codable, Sendable {
    let id: Int
    var title: String
    var subtitle: String
    var posterURL: URL?

    init(anime: Anime) {
        id = anime.id
        title = anime.title
        subtitle = anime.subtitle
        posterURL = anime.posterPreviewURL ?? anime.posterURL
    }

    init(id: Int, title: String, subtitle: String = "", posterURL: URL? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.posterURL = posterURL
    }
}

struct FavoriteEntry: Hashable, Codable, Sendable {
    var anime: SavedAnime
    var addedAt: Date
}

struct EpisodeProgress: Hashable, Codable, Sendable {
    var episodeNumber: Double
    var position: Double
    var duration: Double?
    var updatedAt: Date

    /// Considered watched near the end (credits) or when the source gives no duration.
    var isWatched: Bool {
        guard let duration, duration > 0 else { return position > 0 }
        return position / duration >= 0.9 || duration - position < 120
    }

    var fraction: Double {
        guard let duration, duration > 0 else { return isWatched ? 1 : 0 }
        return min(1, max(0, position / duration))
    }
}

/// Last watched episode of a title, shown in "Продолжить просмотр" and the history.
struct WatchRecord: Identifiable, Hashable, Codable, Sendable {
    var id: Int { anime.id }
    var anime: SavedAnime
    var source: SourceID
    var voice: String
    var episodeNumber: Double
    var episodeTitle: String
    var position: Double
    var duration: Double?
    var updatedAt: Date

    var progress: EpisodeProgress {
        EpisodeProgress(episodeNumber: episodeNumber, position: position, duration: duration, updatedAt: updatedAt)
    }
}

struct LibraryData: Codable, Sendable, Equatable {
    var favorites: [FavoriteEntry] = []
    var history: [WatchRecord] = []
    /// Per title, per episode number ("1", "12.5").
    var progress: [String: [String: EpisodeProgress]] = [:]
    var lastVoice: [String: String] = [:]
    /// Optional so libraries saved by older versions still decode.
    var lastPlayer: [String: String]?
    var lastSource: [String: SourceID] = [:]

    static func episodeKey(_ number: Double) -> String {
        number.rounded() == number ? String(Int(number)) : String(number)
    }
}
