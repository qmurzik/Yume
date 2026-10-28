import Foundation

enum TextCleaner {
    /// Removes Shikimori BB-codes such as `[character=1]Имя[/character]` while keeping their text.
    static func stripBBCode(_ text: String) -> String {
        var result = text.replacingOccurrences(of: #"\[/?[a-z_]+(=[^\]]*)?\]"#, with: "", options: [.regularExpression, .caseInsensitive])
        result = result.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Normalised form of a title used for cross-source matching.
    static func normalizeTitle(_ title: String) -> String {
        let folded = title
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "ru_RU"))
            .replacingOccurrences(of: "ё", with: "е")
        let mapped = folded.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }
        return String(mapped).split(separator: " ").joined(separator: " ")
    }

    /// Turns scheme-relative ("//host/x") and site-relative ("/x") paths into absolute URLs.
    static func absoluteURL(_ string: String?, base: URL) -> URL? {
        guard let string, !string.isEmpty else { return nil }
        if string.hasPrefix("//") { return URL(string: "https:" + string) }
        if string.hasPrefix("/") { return URL(string: string, relativeTo: base)?.absoluteURL }
        return URL(string: string)
    }
}
