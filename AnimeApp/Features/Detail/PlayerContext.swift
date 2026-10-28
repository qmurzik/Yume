import Foundation

/// Everything the player needs: the title, the episode list of one voice, and where to start.
struct PlayerContext: Identifiable {
    let id = UUID()
    let anime: SavedAnime
    let source: SourceID
    let episodes: [SourceEpisode]
    let startIndex: Int
}
