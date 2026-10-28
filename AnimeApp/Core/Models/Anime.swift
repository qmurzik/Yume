import Foundation

/// A title as described by Shikimori, the app's metadata source.
struct Anime: Identifiable, Hashable, Codable, Sendable {
    let id: Int
    var malID: Int?
    var name: String
    var russian: String?
    var english: String?
    var japanese: String?
    var synonyms: [String] = []
    var kind: AnimeKind?
    var score: Double?
    var status: AnimeStatus?
    var episodes: Int?
    var episodesAired: Int?
    var duration: Int?
    var year: Int?
    var airedOn: String?
    var season: String?
    var nextEpisodeAt: Date?
    var rating: String?
    var posterURL: URL?
    var posterPreviewURL: URL?
    var genres: [Genre] = []
    var studios: [String] = []
    var description: String?
    var related: [RelatedAnime] = []

    /// Russian title first, as everything in the UI is in Russian.
    var title: String {
        if let russian, !russian.isEmpty { return russian }
        return name
    }

    var allTitles: [String] {
        ([russian, name, english, japanese] + synonyms.map(Optional.some)).compactMap { $0 }.filter { !$0.isEmpty }
    }

    var episodesText: String? {
        switch (episodesAired, episodes) {
        case let (aired?, total?) where status == .ongoing && total > 0:
            return "\(aired) из \(total) эп."
        case let (aired?, _) where status == .ongoing && aired > 0:
            return "\(aired) эп."
        case let (_, total?) where total > 0:
            return "\(total) эп."
        default:
            return nil
        }
    }

    var subtitle: String {
        [kind?.title, year.map(String.init), episodesText].compactMap { $0 }.joined(separator: " · ")
    }
}

struct Genre: Identifiable, Hashable, Codable, Sendable {
    let id: Int
    var name: String
    var russian: String
    var kind: String?

    var title: String { russian.isEmpty ? name : russian }
}

struct RelatedAnime: Hashable, Codable, Sendable {
    var relation: String
    var anime: Anime
}

enum AnimeKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case tv, movie, ova, ona, special
    case tvSpecial = "tv_special"
    case music, pv, cm

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tv: return "TV-сериал"
        case .movie: return "Фильм"
        case .ova: return "OVA"
        case .ona: return "ONA"
        case .special: return "Спешл"
        case .tvSpecial: return "TV-спешл"
        case .music: return "Клип"
        case .pv: return "Проморолик"
        case .cm: return "Реклама"
        }
    }

    /// Kinds offered in the catalog filter.
    static let filterable: [AnimeKind] = [.tv, .movie, .ova, .ona, .special, .tvSpecial]
}

enum AnimeStatus: String, CaseIterable, Codable, Sendable, Identifiable {
    case anons, ongoing, released

    var id: String { rawValue }

    var title: String {
        switch self {
        case .anons: return "Анонс"
        case .ongoing: return "Онгоинг"
        case .released: return "Вышел"
        }
    }
}
