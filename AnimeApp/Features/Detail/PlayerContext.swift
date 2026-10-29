import Foundation

/// Everything the player needs: the title, the episode list of one voice, and where to start.
struct PlayerContext: Identifiable {
    let id = UUID()
    let anime: SavedAnime
    let source: SourceID
    let episodes: [SourceEpisode]
    let startIndex: Int
    /// Other copies of each episode in the same voice (other embedded players), best first.
    var alternatives: [String: [SourceEpisode]] = [:]
    /// The title on the source's website (YummyAnime), offered when an embed won't load.
    var webURL: URL?
}
