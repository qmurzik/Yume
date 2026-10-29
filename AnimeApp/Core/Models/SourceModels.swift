import Foundation

enum SourceID: String, Codable, Sendable, CaseIterable, Identifiable {
    case aniLibria = "anilibria"
    case animeVost = "animevost"
    case yummy = "yummyanime"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .aniLibria: return "AniLibria"
        case .animeVost: return "AnimeVost"
        case .yummy: return "YummyAnime"
        }
    }
}

/// A title as it exists inside one playback source.
struct SourceTitle: Hashable, Codable, Sendable {
    let source: SourceID
    let id: String
    var title: String
    var originalTitle: String?
    var alternativeTitles: [String] = []
    var year: Int?
    var shikimoriID: Int?
    var malID: Int?
    var posterURL: URL?
}

struct TimeRange: Hashable, Codable, Sendable {
    var start: Double
    var end: Double

    func contains(_ time: Double) -> Bool { time >= start && time < end }
}

/// One episode in one voice-over (or subtitles) of one source.
struct SourceEpisode: Identifiable, Hashable, Codable, Sendable {
    let source: SourceID
    /// Source-specific reference resolved by `AnimeSource.stream(for:)`.
    let id: String
    var number: Double
    var title: String?
    /// Voice-over team or "Субтитры".
    var voice: String
    var duration: Double?
    var opening: TimeRange?
    var ending: TimeRange?
    var previewURL: URL?
    /// Embedded player hosting this copy (YummyAnime offers one voice-over in several players).
    var player: String? = nil

    var numberText: String {
        number.rounded() == number ? String(Int(number)) : String(number)
    }

    var displayTitle: String {
        if let title, !title.isEmpty { return "\(numberText). \(title)" }
        return "\(numberText) серия"
    }
}

struct StreamQuality: Hashable, Codable, Sendable, Identifiable {
    var height: Int
    var url: URL

    var id: Int { height }
    var label: String { "\(height)p" }
}

struct StreamInfo: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        /// Direct HLS playlists or MP4 files, played with AVPlayer.
        case native([StreamQuality])
        /// The source's official embeddable web player.
        case embed(URL)
    }

    var kind: Kind
    var opening: TimeRange?
    var ending: TimeRange?

    /// Best quality first.
    var qualities: [StreamQuality] {
        if case .native(let list) = kind { return list.sorted { $0.height > $1.height } }
        return []
    }
}

struct ScheduleEntry: Identifiable, Hashable, Sendable {
    var id: String { "\(title.source.rawValue)-\(title.id)" }
    var title: SourceTitle
    /// ISO weekday 1 = Monday … 7 = Sunday.
    var weekday: Int
    var nextEpisode: Int?
    var isOngoing: Bool
}
