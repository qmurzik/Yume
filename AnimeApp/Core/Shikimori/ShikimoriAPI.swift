import Foundation

/// Metadata provider: catalog, search, genres, details and similar titles.
/// Uses the GraphQL API recommended by Shikimori; every request goes through the shared rate limiter.
struct ShikimoriAPI: Sendable {
    var http = HTTPClient(rateLimiter: .shikimori)
    var baseURL = AppConfig.shikimoriBaseURL

    static let pageSize = 30

    private static let listFields = """
    id malId name russian english japanese synonyms kind score status episodes episodesAired duration
    airedOn { year month day date } season nextEpisodeAt rating
    poster { originalUrl mainUrl main2xUrl previewUrl preview2xUrl }
    genres { id name russian kind }
    """

    private static let detailFields = listFields + """
     studios { id name } description
    related { relationText anime { id name russian kind score status episodes episodesAired airedOn { year } poster { mainUrl main2xUrl previewUrl preview2xUrl } } }
    """

    private struct GraphQLBody: Encodable {
        let query: String
        let variables: [String: Variable]
    }

    enum Variable: Encodable, Hashable {
        case int(Int), string(String), bool(Bool)

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .int(let value): try container.encode(value)
            case .string(let value): try container.encode(value)
            case .bool(let value): try container.encode(value)
            }
        }
    }

    /// Builds the GraphQL request for the catalog; exposed for tests.
    static func animesRequest(query: CatalogQuery, page: Int, limit: Int, fields: String = listFields) -> (String, [String: Variable]) {
        var declarations = ["$page: PositiveInt", "$limit: PositiveInt", "$order: OrderEnum"]
        var arguments = ["page: $page", "limit: $limit", "order: $order"]
        var variables: [String: Variable] = [
            "page": .int(page), "limit": .int(limit), "order": .string(query.order.rawValue),
        ]
        func add(_ name: String, _ type: String, _ value: Variable) {
            declarations.append("$\(name): \(type)")
            arguments.append("\(name): $\(name)")
            variables[name] = value
        }
        if let search = query.search?.trimmingCharacters(in: .whitespacesAndNewlines), !search.isEmpty {
            add("search", "String", .string(search))
        }
        if !query.genreIDs.isEmpty {
            add("genre", "String", .string(query.genreIDs.sorted().map(String.init).joined(separator: ",")))
        }
        if let season = query.seasonArgument() { add("season", "SeasonString", .string(season)) }
        // Without an explicit kind, hide music clips, promos and adverts.
        add("kind", "AnimeKindString", .string(query.kind?.rawValue ?? "!music,!pv,!cm"))
        if let status = query.status { add("status", "AnimeStatusString", .string(status.rawValue)) }
        let text = "query(\(declarations.joined(separator: ", "))) { animes(\(arguments.joined(separator: ", "))) { \(fields) } }"
        return (text, variables)
    }

    private func graphQL(_ query: String, variables: [String: Variable] = [:]) async throws -> Data {
        try await http.postJSON(baseURL.appendingPathComponent("api/graphql"), body: GraphQLBody(query: query, variables: variables))
    }

    func animes(_ query: CatalogQuery, page: Int, limit: Int = pageSize) async throws -> [Anime] {
        let (text, variables) = Self.animesRequest(query: query, page: page, limit: limit)
        return try ShikimoriParser.animes(from: try await graphQL(text, variables: variables))
    }

    func search(_ text: String, page: Int = 1) async throws -> [Anime] {
        var query = CatalogQuery()
        query.search = text
        query.order = .ranked
        return try await animes(query, page: page)
    }

    func animes(ids: [Int]) async throws -> [Anime] {
        guard !ids.isEmpty else { return [] }
        let text = "query($ids: String, $limit: PositiveInt) { animes(ids: $ids, limit: $limit) { \(Self.listFields) } }"
        let result = try ShikimoriParser.animes(from: try await graphQL(text, variables: [
            "ids": .string(ids.map(String.init).joined(separator: ",")), "limit": .int(min(50, ids.count)),
        ]))
        // Keep the requested order.
        let byID = Dictionary(result.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { byID[$0] }
    }

    func anime(id: Int) async throws -> Anime {
        let text = "query($ids: String) { animes(ids: $ids, limit: 1) { \(Self.detailFields) } }"
        guard let anime = try ShikimoriParser.animes(from: try await graphQL(text, variables: ["ids": .string(String(id))])).first else {
            throw APIError.notFound
        }
        return anime
    }

    func genres() async throws -> [Genre] {
        let data = try await graphQL("{ genres(entryType: Anime) { id name russian kind } }")
        return try ShikimoriParser.genres(from: data)
            .filter { $0.kind == "genre" || $0.kind == "theme" || $0.kind == "demographic" }
            .sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
    }

    func similar(to id: Int, limit: Int = 15) async throws -> [Anime] {
        let data = try await http.get(baseURL.appendingPathComponent("api/animes/\(id)/similar"))
        return try await animes(ids: Array(try ShikimoriParser.similarIDs(from: data).prefix(limit)))
    }
}
