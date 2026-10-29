import Foundation

enum YummyDTO {
    struct Envelope<T: Decodable>: Decodable {
        let response: T?
        let error: ErrorBody?
    }

    struct ErrorBody: Decodable {
        let title: String?
        let message: String?
    }

    struct Poster: Decodable {
        let small: String?
        let medium: String?
        let big: String?
        let fullsize: String?
    }

    struct RemoteIDs: Decodable {
        let shikimoriId: Int?
        let myanimelistId: Int?
    }

    struct AnimeItem: Decodable {
        let animeId: Int
        let animeUrl: String?
        let title: String
        let original: String?
        let otherTitles: [String]?
        let year: Int?
        let poster: Poster?
        let remoteIds: RemoteIDs?

        var model: SourceTitle {
            SourceTitle(
                source: .yummy,
                id: String(animeId),
                title: title,
                originalTitle: original,
                alternativeTitles: otherTitles ?? [],
                year: year,
                shikimoriID: remoteIds?.shikimoriId.flatMap { $0 > 0 ? $0 : nil },
                malID: remoteIds?.myanimelistId.flatMap { $0 > 0 ? $0 : nil },
                posterURL: TextCleaner.absoluteURL(poster?.big ?? poster?.medium ?? poster?.fullsize, base: AppConfig.yummyBaseURL),
                webURL: animeUrl.flatMap { $0.isEmpty ? nil : AppConfig.yummySiteURL.appendingPathComponent("catalog/item/\($0)") }
            )
        }
    }

    struct Skip: Decodable {
        let time: Double?
        let length: Double?

        var range: TimeRange? {
            guard let time, let length, length > 0 else { return nil }
            return TimeRange(start: time, end: time + length)
        }
    }

    struct Video: Decodable {
        struct Info: Decodable {
            let dubbing: String?
            let player: String?
        }
        struct Skips: Decodable {
            let opening: Skip?
            let ending: Skip?
        }

        let videoId: Int
        let iframeUrl: String
        let data: Info?
        let number: String?
        let index: Int?
        let skips: Skips?
        let duration: Double?

        var voice: String {
            let dubbing = (data?.dubbing ?? "Без названия")
                .replacingOccurrences(of: "Озвучка ", with: "")
                .trimmingCharacters(in: .whitespaces)
            return dubbing.isEmpty ? "Без названия" : dubbing
        }

        var player: String? {
            let name = (data?.player ?? "").replacingOccurrences(of: "Плеер ", with: "").trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? nil : name
        }

        var model: SourceEpisode? {
            guard let url = TextCleaner.absoluteURL(iframeUrl, base: AppConfig.yummyBaseURL) else { return nil }
            let number = Double(number?.replacingOccurrences(of: ",", with: ".") ?? "") ?? Double(index ?? 0)
            return SourceEpisode(
                source: .yummy,
                id: url.absoluteString,
                number: number,
                title: nil,
                voice: voice,
                duration: duration.flatMap { $0 > 0 ? $0 : nil },
                opening: skips?.opening?.range,
                ending: skips?.ending?.range,
                previewURL: nil,
                player: player
            )
        }
    }
}

enum YummyParser {
    static let decoder = JSONDecoder.api

    private static func unwrap<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        let envelope = try decoder.decodeAPI(YummyDTO.Envelope<T>.self, from: data)
        if let response = envelope.response { return response }
        throw APIError.server(envelope.error?.message ?? envelope.error?.title ?? "Пустой ответ YummyAnime.")
    }

    static func animes(from data: Data) throws -> [SourceTitle] {
        try unwrap([YummyDTO.AnimeItem].self, data).map(\.model)
    }

    static func episodes(from data: Data) throws -> [SourceEpisode] {
        try unwrap([YummyDTO.Video].self, data)
            .compactMap(\.model)
            .sorted { ($0.voice, $0.number, $0.player ?? "") < ($1.voice, $1.number, $1.player ?? "") }
    }
}
