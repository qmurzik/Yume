import Foundation

/// Raw Shikimori GraphQL / REST payloads and their conversion into domain models.
enum ShikimoriDTO {
    struct GraphQLResponse<T: Decodable>: Decodable {
        let data: T?
        let errors: [GraphQLError]?
    }

    struct GraphQLError: Decodable {
        let message: String
    }

    struct AnimesData: Decodable {
        let animes: [AnimeNode]
    }

    struct GenresData: Decodable {
        let genres: [GenreNode]
    }

    struct IncompleteDate: Decodable {
        let year: Int?
        let month: Int?
        let day: Int?
        let date: String?
    }

    struct Poster: Decodable {
        let originalUrl: String?
        let mainUrl: String?
        let main2xUrl: String?
        let previewUrl: String?
        let preview2xUrl: String?
    }

    struct GenreNode: Decodable {
        let id: String
        let name: String
        let russian: String?
        let kind: String?

        var model: Genre? {
            guard let id = Int(id) else { return nil }
            return Genre(id: id, name: name, russian: russian ?? "", kind: kind)
        }
    }

    struct StudioNode: Decodable {
        let id: String?
        let name: String
    }

    struct RelatedNode: Decodable {
        let relationText: String?
        let anime: AnimeNode?
    }

    final class AnimeNode: Decodable {
        let id: String
        let malId: String?
        let name: String
        let russian: String?
        let english: String?
        let japanese: String?
        let synonyms: [String]?
        let kind: String?
        let score: Double?
        let status: String?
        let episodes: Int?
        let episodesAired: Int?
        let duration: Int?
        let airedOn: IncompleteDate?
        let season: String?
        let nextEpisodeAt: String?
        let rating: String?
        let poster: Poster?
        let genres: [GenreNode]?
        let studios: [StudioNode]?
        let description: String?
        let related: [RelatedNode]?

        var model: Anime? {
            guard let id = Int(id) else { return nil }
            var anime = Anime(id: id, name: name)
            anime.malID = malId.flatMap(Int.init)
            anime.russian = russian
            anime.english = english
            anime.japanese = japanese
            anime.synonyms = synonyms ?? []
            anime.kind = kind.flatMap(AnimeKind.init(rawValue:))
            anime.score = score.flatMap { $0 > 0 ? $0 : nil }
            anime.status = status.flatMap(AnimeStatus.init(rawValue:))
            anime.episodes = episodes
            anime.episodesAired = episodesAired
            anime.duration = duration
            anime.year = airedOn?.year
            anime.airedOn = airedOn?.date
            anime.season = season
            anime.nextEpisodeAt = nextEpisodeAt.flatMap(ShikimoriDTO.parseDate)
            anime.rating = rating
            anime.posterURL = (poster?.main2xUrl ?? poster?.mainUrl ?? poster?.originalUrl).flatMap(URL.init(string:))
            anime.posterPreviewURL = (poster?.preview2xUrl ?? poster?.previewUrl ?? poster?.mainUrl).flatMap(URL.init(string:))
            anime.genres = (genres ?? []).compactMap(\.model)
            anime.studios = (studios ?? []).map(\.name)
            anime.description = description.map(TextCleaner.stripBBCode).flatMap { $0.isEmpty ? nil : $0 }
            anime.related = (related ?? []).compactMap { node in
                guard let related = node.anime?.model else { return nil }
                return RelatedAnime(relation: node.relationText ?? "", anime: related)
            }
            return anime
        }
    }

    /// Item of REST `GET /api/animes/:id/similar`; only ids are used, posters come from GraphQL.
    struct RESTAnime: Decodable {
        let id: Int
    }

    static func parseDate(_ string: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: string) { return date }
        return ISO8601DateFormatter().date(from: string)
    }
}

enum ShikimoriParser {
    static func animes(from data: Data) throws -> [Anime] {
        try unwrap(JSONDecoder().decodeAPI(ShikimoriDTO.GraphQLResponse<ShikimoriDTO.AnimesData>.self, from: data))
            .animes.compactMap(\.model)
    }

    static func genres(from data: Data) throws -> [Genre] {
        try unwrap(JSONDecoder().decodeAPI(ShikimoriDTO.GraphQLResponse<ShikimoriDTO.GenresData>.self, from: data))
            .genres.compactMap(\.model)
    }

    static func similarIDs(from data: Data) throws -> [Int] {
        try JSONDecoder().decodeAPI([ShikimoriDTO.RESTAnime].self, from: data).map(\.id)
    }

    private static func unwrap<T>(_ response: ShikimoriDTO.GraphQLResponse<T>) throws -> T {
        if let data = response.data { return data }
        throw APIError.server(response.errors?.first?.message ?? "Пустой ответ Shikimori.")
    }
}
