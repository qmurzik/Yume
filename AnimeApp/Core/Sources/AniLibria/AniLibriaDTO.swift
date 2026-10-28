import Foundation

enum AniLibriaDTO {
    struct ValueDescription<V: Decodable>: Decodable {
        let value: V?
        let description: String?
    }

    struct Name: Decodable {
        let main: String?
        let english: String?
        let alternative: String?
    }

    struct ExternalID: Decodable {
        let id: Int?
    }

    struct Image: Decodable {
        struct Optimized: Decodable {
            let src: String?
            let preview: String?
            let thumbnail: String?
        }
        let src: String?
        let preview: String?
        let thumbnail: String?
        let optimized: Optimized?

        var best: String? { optimized?.src ?? src ?? preview }
        var small: String? { optimized?.preview ?? preview ?? thumbnail ?? src }
    }

    struct Timing: Decodable {
        let start: Double?
        let stop: Double?

        var range: TimeRange? {
            guard let start, let stop, stop > start else { return nil }
            return TimeRange(start: start, end: stop)
        }
    }

    struct Episode: Decodable {
        let id: String
        let name: String?
        let ordinal: Double?
        let opening: Timing?
        let ending: Timing?
        let preview: Image?
        let hls480: String?
        let hls720: String?
        let hls1080: String?
        let duration: Double?
        let sortOrder: Int?

        enum CodingKeys: String, CodingKey {
            case id, name, ordinal, opening, ending, preview, duration
            case hls480 = "hls_480", hls720 = "hls_720", hls1080 = "hls_1080", sortOrder = "sort_order"
        }

        var qualities: [StreamQuality] {
            [(1080, hls1080), (720, hls720), (480, hls480)].compactMap { height, link in
                link.flatMap(URL.init(string:)).map { StreamQuality(height: height, url: $0) }
            }
        }

        func model(base: URL) -> SourceEpisode {
            SourceEpisode(
                source: .aniLibria,
                id: id,
                number: ordinal ?? Double(sortOrder ?? 0),
                title: name,
                voice: "AniLibria",
                duration: duration,
                opening: opening?.range,
                ending: ending?.range,
                previewURL: TextCleaner.absoluteURL(preview?.small, base: base)
            )
        }
    }

    struct Release: Decodable {
        let id: Int
        let type: ValueDescription<String>?
        let year: Int?
        let name: Name?
        let alias: String?
        let season: ValueDescription<String>?
        let shikimori: ExternalID?
        let mal: ExternalID?
        let poster: Image?
        let isOngoing: Bool?
        let publishDay: ValueDescription<Int>?
        let description: String?
        let episodesTotal: Int?
        let episodes: [Episode]?

        enum CodingKeys: String, CodingKey {
            case id, type, year, name, alias, season, shikimori, mal, poster, description, episodes
            case isOngoing = "is_ongoing", publishDay = "publish_day", episodesTotal = "episodes_total"
        }

        func model(base: URL) -> SourceTitle {
            let alternatives = (name?.alternative ?? "")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            return SourceTitle(
                source: .aniLibria,
                id: String(id),
                title: name?.main ?? alias ?? String(id),
                originalTitle: name?.english,
                alternativeTitles: alternatives,
                year: year,
                shikimoriID: shikimori?.id,
                malID: mal?.id,
                posterURL: TextCleaner.absoluteURL(poster?.best, base: base)
            )
        }
    }

    struct EpisodeDetail: Decodable {
        let id: String
        let opening: Timing?
        let ending: Timing?
        let hls480: String?
        let hls720: String?
        let hls1080: String?

        enum CodingKeys: String, CodingKey {
            case id, opening, ending
            case hls480 = "hls_480", hls720 = "hls_720", hls1080 = "hls_1080"
        }

        var stream: StreamInfo {
            let qualities = [(1080, hls1080), (720, hls720), (480, hls480)].compactMap { height, link in
                link.flatMap(URL.init(string:)).map { StreamQuality(height: height, url: $0) }
            }
            return StreamInfo(kind: .hls(qualities), opening: opening?.range, ending: ending?.range)
        }
    }

    struct ScheduleItem: Decodable {
        let release: Release
        let nextReleaseEpisodeNumber: Int?

        enum CodingKeys: String, CodingKey {
            case release
            case nextReleaseEpisodeNumber = "next_release_episode_number"
        }
    }
}

enum AniLibriaParser {
    static let decoder = JSONDecoder()

    static func releases(from data: Data, base: URL = AppConfig.aniLibriaBaseURL) throws -> [SourceTitle] {
        try decoder.decodeAPI([AniLibriaDTO.Release].self, from: data).map { $0.model(base: base) }
    }

    static func episodes(from data: Data, base: URL = AppConfig.aniLibriaBaseURL) throws -> [SourceEpisode] {
        let release = try decoder.decodeAPI(AniLibriaDTO.Release.self, from: data)
        return (release.episodes ?? [])
            .sorted { ($0.sortOrder ?? 0, $0.ordinal ?? 0) < ($1.sortOrder ?? 0, $1.ordinal ?? 0) }
            .map { $0.model(base: base) }
    }

    static func stream(from data: Data) throws -> StreamInfo {
        let info = try decoder.decodeAPI(AniLibriaDTO.EpisodeDetail.self, from: data).stream
        guard !info.qualities.isEmpty else { throw APIError.server("Для этой серии нет видеопотока.") }
        return info
    }

    static func schedule(from data: Data, base: URL = AppConfig.aniLibriaBaseURL) throws -> [ScheduleEntry] {
        try decoder.decodeAPI([AniLibriaDTO.ScheduleItem].self, from: data).compactMap { item in
            guard let day = item.release.publishDay?.value, (1...7).contains(day) else { return nil }
            return ScheduleEntry(
                title: item.release.model(base: base),
                weekday: day,
                nextEpisode: item.nextReleaseEpisodeNumber,
                isOngoing: item.release.isOngoing ?? false
            )
        }
    }
}
