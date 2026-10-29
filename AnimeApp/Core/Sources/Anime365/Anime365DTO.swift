import Foundation

enum Anime365DTO {
    struct Envelope<T: Decodable>: Decodable {
        let data: T?
        let error: ErrorBody?
    }

    struct ErrorBody: Decodable {
        let code: Int?
        let message: String?
    }

    /// The API mixes numbers and numeric strings for the same fields.
    struct FlexibleInt: Decodable, Hashable {
        let value: Int

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let int = try? container.decode(Int.self) {
                value = int
            } else if let string = try? container.decode(String.self), let int = Int(string) {
                value = int
            } else if let double = try? container.decode(Double.self) {
                value = Int(double)
            } else {
                throw DecodingError.typeMismatch(Int.self, .init(codingPath: decoder.codingPath, debugDescription: "not a number"))
            }
        }
    }

    struct FlexibleDouble: Decodable, Hashable {
        let value: Double

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let double = try? container.decode(Double.self) {
                value = double
            } else if let string = try? container.decode(String.self), let double = Double(string) {
                value = double
            } else {
                throw DecodingError.typeMismatch(Double.self, .init(codingPath: decoder.codingPath, debugDescription: "not a number"))
            }
        }
    }

    struct Titles: Decodable {
        let ru: String?
        let romaji: String?
        let en: String?
        let ja: String?
    }

    struct Episode: Decodable {
        let id: FlexibleInt
        let episodeInt: FlexibleDouble?
        let episodeTitle: String?
        let episodeType: String?
        let isActive: FlexibleInt?
    }

    struct Series: Decodable {
        let id: FlexibleInt
        let myAnimeListId: FlexibleInt?
        let year: FlexibleInt?
        let type: String?
        let titles: Titles?
        let url: String?
        let posterUrlSmall: String?
        let episodes: [Episode]?

        var model: SourceTitle {
            SourceTitle(
                source: .anime365,
                id: String(id.value),
                title: titles?.ru ?? titles?.romaji ?? String(id.value),
                originalTitle: titles?.romaji,
                alternativeTitles: [titles?.en, titles?.ja].compactMap { $0 },
                year: year?.value,
                shikimoriID: nil,
                malID: myAnimeListId.flatMap { $0.value > 0 ? $0.value : nil },
                posterURL: posterUrlSmall.flatMap(URL.init(string:)),
                webURL: url.flatMap(URL.init(string:))
            )
        }
    }

    struct Translation: Decodable {
        let id: FlexibleInt
        let episodeId: FlexibleInt
        let typeKind: String?
        let typeLang: String?
        let authorsSummary: String?
        let qualityType: String?
        let height: FlexibleInt?
        let isActive: FlexibleInt?
        let duration: FlexibleDouble?
    }

    struct Stream: Decodable {
        let height: FlexibleInt?
        let urls: [String]?
    }

    struct Embed: Decodable {
        let stream: [Stream]?
        let subtitlesUrl: String?
    }

    struct Me: Decodable {
        let isLogined: Bool?
        let name: String?
        let isPremium: Bool?
        let premiumUntil: String?
    }
}

enum Anime365Parser {
    static let decoder = JSONDecoder()

    /// Episode kinds that are actual episodes (trailers and previews are skipped).
    static let playableTypes: Set<String> = ["tv", "ova", "ona", "special", "movie"]

    private static func unwrap<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        let envelope = try decoder.decodeAPI(Anime365DTO.Envelope<T>.self, from: data)
        if let value = envelope.data { return value }
        if envelope.error?.code == 403 {
            throw APIError.server("Войдите в Anime365 в настройках (нужен аккаунт с подпиской).")
        }
        if envelope.error?.code == 404 { throw APIError.notFound }
        throw APIError.server(envelope.error?.message ?? "Пустой ответ Anime365.")
    }

    static func seriesList(from data: Data) throws -> [SourceTitle] {
        try unwrap([Anime365DTO.Series].self, data).map(\.model)
    }

    static func series(from data: Data) throws -> Anime365DTO.Series {
        try unwrap(Anime365DTO.Series.self, data)
    }

    /// Russian voice-overs per episode. Subtitled copies are left out: Anime365 ships them as
    /// external ASS files, which AVPlayer can't render.
    static func episodes(series: Anime365DTO.Series, translationsData: Data) throws -> [SourceEpisode] {
        let translations = try unwrap([Anime365DTO.Translation].self, translationsData)
        let episodes = Dictionary(
            (series.episodes ?? [])
                .filter { playableTypes.contains($0.episodeType ?? "") && ($0.isActive?.value ?? 1) == 1 }
                .map { ($0.id.value, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return translations.compactMap { translation -> SourceEpisode? in
            guard translation.typeKind == "voice", translation.typeLang == "ru",
                  (translation.isActive?.value ?? 1) == 1,
                  let episode = episodes[translation.episodeId.value] else { return nil }
            let author = translation.authorsSummary?.trimmingCharacters(in: .whitespaces)
            let title = episode.episodeTitle?.trimmingCharacters(in: .whitespaces)
            return SourceEpisode(
                source: .anime365,
                id: String(translation.id.value),
                number: episode.episodeInt?.value ?? 0,
                title: title?.isEmpty == false ? title : nil,
                voice: author?.isEmpty == false ? author! : "Без названия",
                duration: translation.duration?.value,
                player: qualityLabel(translation)
            )
        }
        .sorted { ($0.voice, $0.number) < ($1.voice, $1.number) }
    }

    /// One voice-over often has TV and BD copies; they're grouped like players.
    static func qualityLabel(_ translation: Anime365DTO.Translation) -> String {
        let kind = (translation.qualityType ?? "").uppercased()
        let height = translation.height.map { "\($0.value)p" }
        return [kind.isEmpty ? nil : kind, height].compactMap { $0 }.joined(separator: " ")
    }

    static func stream(from data: Data) throws -> StreamInfo {
        let embed = try unwrap(Anime365DTO.Embed.self, data)
        let qualities = (embed.stream ?? []).compactMap { stream -> StreamQuality? in
            guard let height = stream.height?.value, let link = stream.urls?.first,
                  let url = TextCleaner.absoluteURL(link, base: AppConfig.anime365BaseURL) else { return nil }
            return StreamQuality(height: height, url: url)
        }
        guard !qualities.isEmpty else {
            throw APIError.server("Anime365 не дал ссылку на видео. Ссылки выдаются только аккаунтам с активной подпиской.")
        }
        return StreamInfo(kind: .native(qualities), opening: nil, ending: nil)
    }

    static func me(from data: Data) throws -> Anime365DTO.Me {
        try unwrap(Anime365DTO.Me.self, data)
    }
}
