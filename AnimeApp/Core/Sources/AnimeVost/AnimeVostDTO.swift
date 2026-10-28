import Foundation

enum AnimeVostDTO {
    /// The API returns the same fields as strings in one endpoint and numbers in another.
    struct FlexibleString: Decodable, Hashable {
        let value: String

        init(value: String) { self.value = value }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let string = try? container.decode(String.self) {
                value = string
            } else if let int = try? container.decode(Int.self) {
                value = String(int)
            } else {
                value = String(try container.decode(Double.self))
            }
        }
    }

    struct SearchResponse: Decodable {
        let data: [Release]?
        let error: String?
    }

    struct Release: Decodable {
        let id: FlexibleString
        let title: String
        let year: FlexibleString?
        let type: String?
        let urlImagePreview: String?

        /// "Русское название / Romaji [1-12 из 12]" split into its parts.
        var names: (russian: String, original: String?) {
            var text = title
            // Ongoings carry several groups: "[1-4 из 12+] [5 серия - 30 октября]".
            if let bracket = text.range(of: #"(\s*\[[^\]]*\])+\s*$"#, options: .regularExpression) {
                text.removeSubrange(bracket)
            }
            let parts = text.components(separatedBy: " / ").map { $0.trimmingCharacters(in: .whitespaces) }
            return (parts.first ?? text, parts.count > 1 ? parts.dropFirst().joined(separator: " / ") : nil)
        }

        var model: SourceTitle {
            let names = self.names
            return SourceTitle(
                source: .animeVost,
                id: id.value,
                title: names.russian,
                originalTitle: names.original,
                year: year.flatMap { Int($0.value.prefix(4)) },
                shikimoriID: nil,
                malID: nil,
                posterURL: urlImagePreview.flatMap(AnimeVostParser.secureURL)
            )
        }
    }

    struct PlaylistItem: Decodable {
        let name: String
        let hd: String?
        let std: String?
        let preview: String?
    }
}

enum AnimeVostParser {
    static func releases(from data: Data) throws -> [SourceTitle] {
        let response = try JSONDecoder().decodeAPI(AnimeVostDTO.SearchResponse.self, from: data)
        // "Ничего не найдено" comes back as an error object, not as an empty list.
        return (response.data ?? []).map(\.model)
    }

    static func episodes(from data: Data, releaseID: String) throws -> [SourceEpisode] {
        let items = try JSONDecoder().decodeAPI([AnimeVostDTO.PlaylistItem].self, from: data)
        return items.enumerated().compactMap { index, item -> SourceEpisode? in
            let qualities = streamQualities(item)
            guard !qualities.isEmpty else { return nil }
            let number = episodeNumber(item.name) ?? Double(index + 1)
            let isRegular = item.name.range(of: #"^\d+([.,]\d+)?\s+серия$"#, options: .regularExpression) != nil
            return SourceEpisode(
                source: .animeVost,
                id: encode(qualities),
                number: number,
                title: isRegular ? nil : item.name,
                voice: "AnimeVost",
                duration: nil,
                opening: nil,
                ending: nil,
                previewURL: item.preview.flatMap(secureURL)
            )
        }
        .sorted { $0.number < $1.number }
    }

    static func streamQualities(_ item: AnimeVostDTO.PlaylistItem) -> [StreamQuality] {
        [(720, item.hd), (480, item.std)].compactMap { height, link in
            link.flatMap(secureURL).map { StreamQuality(height: height, url: $0) }
        }
    }

    static func episodeNumber(_ name: String) -> Double? {
        guard let range = name.range(of: #"\d+([.,]\d+)?"#, options: .regularExpression) else { return nil }
        return Double(name[range].replacingOccurrences(of: ",", with: "."))
    }

    /// The CDN serves the same files over HTTPS; App Transport Security requires it.
    static func secureURL(_ string: String) -> URL? {
        guard !string.isEmpty else { return nil }
        if string.hasPrefix("http://") { return URL(string: "https://" + string.dropFirst("http://".count)) }
        return TextCleaner.absoluteURL(string, base: AppConfig.animeVostBaseURL)
    }

    /// The playlist has no per-episode endpoint, so the episode id carries its file links.
    static func encode(_ qualities: [StreamQuality]) -> String {
        qualities.map { "\($0.height)|\($0.url.absoluteString)" }.joined(separator: "\n")
    }

    static func decode(_ id: String) -> [StreamQuality] {
        id.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "|", maxSplits: 1)
            guard parts.count == 2, let height = Int(parts[0]), let url = URL(string: String(parts[1])) else { return nil }
            return StreamQuality(height: height, url: url)
        }
    }
}
