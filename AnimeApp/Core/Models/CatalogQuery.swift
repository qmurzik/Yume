import Foundation

enum AnimeSeason: String, CaseIterable, Codable, Sendable, Identifiable {
    case winter, spring, summer, fall

    var id: String { rawValue }

    var title: String {
        switch self {
        case .winter: return "Зима"
        case .spring: return "Весна"
        case .summer: return "Лето"
        case .fall: return "Осень"
        }
    }

    static func of(month: Int) -> AnimeSeason {
        switch month {
        case 1...3: return .winter
        case 4...6: return .spring
        case 7...9: return .summer
        default: return .fall
        }
    }
}

enum CatalogOrder: String, CaseIterable, Codable, Sendable, Identifiable {
    case popularity, ranked, airedOn = "aired_on", name, createdAt = "created_at_desc"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .popularity: return "По популярности"
        case .ranked: return "По рейтингу"
        case .airedOn: return "По дате выхода"
        case .name: return "По названию"
        case .createdAt: return "Недавно добавленные"
        }
    }
}

/// Catalog filters, mapped onto Shikimori `animes` query arguments.
struct CatalogQuery: Hashable, Codable, Sendable {
    var genreIDs: Set<Int> = []
    var year: Int?
    var season: AnimeSeason?
    var kind: AnimeKind?
    var status: AnimeStatus?
    var order: CatalogOrder = .popularity
    var search: String?

    var isFiltered: Bool {
        !genreIDs.isEmpty || year != nil || season != nil || kind != nil || status != nil
    }

    /// Shikimori's `season` argument: "2024", "summer_2024", or a season of the current year.
    func seasonArgument(currentYear: Int = Calendar.current.component(.year, from: Date())) -> String? {
        switch (season, year) {
        case let (season?, year?): return "\(season.rawValue)_\(year)"
        case let (season?, nil): return "\(season.rawValue)_\(currentYear)"
        case let (nil, year?): return String(year)
        case (nil, nil): return nil
        }
    }
}
