import Foundation

/// Matches titles across sources: ids first, then normalised names plus air year.
enum TitleMatcher {
    static func isSame(_ anime: Anime, _ candidate: SourceTitle) -> Bool {
        score(anime, candidate) != nil
    }

    static func bestMatch(for anime: Anime, in candidates: [SourceTitle]) -> SourceTitle? {
        candidates
            .compactMap { candidate in score(anime, candidate).map { (candidate, $0) } }
            .max { $0.1 < $1.1 }?
            .0
    }

    /// Higher is better; nil means "not the same title".
    static func score(_ anime: Anime, _ candidate: SourceTitle) -> Int? {
        if let id = candidate.shikimoriID { return id == anime.id ? 1000 : nil }
        if let mal = candidate.malID, let animeMal = anime.malID { return mal == animeMal ? 900 : nil }

        let yearScore: Int
        switch (anime.year, candidate.year) {
        case let (a?, b?) where a == b: yearScore = 50
        case let (a?, b?) where abs(a - b) == 1: yearScore = 10
        case (_?, _?): return nil
        default: yearScore = 0
        }

        let animeNames = Set(anime.allTitles.map(TextCleaner.normalizeTitle).filter { !$0.isEmpty })
        let candidateNames = Set(([candidate.title, candidate.originalTitle] + candidate.alternativeTitles.map(Optional.some))
            .compactMap { $0 }.map(TextCleaner.normalizeTitle).filter { !$0.isEmpty })

        if !animeNames.isDisjoint(with: candidateNames) { return 500 + yearScore }

        // Fuzzy: most words shared, e.g. punctuation or a "TV" suffix differs. Requires a known year.
        guard yearScore > 0 else { return nil }
        var best = 0.0
        for a in animeNames {
            for b in candidateNames { best = max(best, similarity(a, b)) }
        }
        return best >= 0.8 ? 100 + Int(best * 100) + yearScore : nil
    }

    /// Jaccard similarity of word sets.
    static func similarity(_ a: String, _ b: String) -> Double {
        let left = Set(a.split(separator: " ")), right = Set(b.split(separator: " "))
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        return Double(left.intersection(right).count) / Double(left.union(right).count)
    }
}
