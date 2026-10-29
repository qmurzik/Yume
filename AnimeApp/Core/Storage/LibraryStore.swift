import Combine
import Foundation

/// Favorites, history and per-episode progress, stored as one JSON file in Application Support.
///
/// Why JSON and not SwiftData/Core Data: the app targets iOS 16, where SwiftData is unavailable,
/// and supporting two stores would double the code. The data is small (hundreds of records),
/// has no relations or queries beyond lookups by id, and a Codable file is trivial to test and migrate.
@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var data: LibraryData

    private let fileURL: URL?
    private var saveTask: Task<Void, Never>?
    static let historyLimit = 200

    init(fileURL: URL? = LibraryStore.defaultFileURL) {
        self.fileURL = fileURL
        if let fileURL, let raw = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(LibraryData.self, from: raw) {
            data = decoded
        } else {
            data = LibraryData()
        }
    }

    nonisolated static var defaultFileURL: URL? {
        guard let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return directory.appendingPathComponent("library.json")
    }

    // MARK: Favorites

    var favorites: [FavoriteEntry] { data.favorites.sorted { $0.addedAt > $1.addedAt } }

    func isFavorite(_ id: Int) -> Bool {
        data.favorites.contains { $0.anime.id == id }
    }

    func toggleFavorite(_ anime: SavedAnime) {
        if let index = data.favorites.firstIndex(where: { $0.anime.id == anime.id }) {
            data.favorites.remove(at: index)
        } else {
            data.favorites.append(FavoriteEntry(anime: anime, addedAt: Date()))
        }
        scheduleSave()
    }

    // MARK: History & progress

    var history: [WatchRecord] { data.history.sorted { $0.updatedAt > $1.updatedAt } }

    /// Most recently watched titles; the card resumes the episode or offers the next one.
    var continueWatching: [WatchRecord] {
        Array(history.prefix(15))
    }

    func record(for animeID: Int) -> WatchRecord? {
        data.history.first { $0.anime.id == animeID }
    }

    func progress(animeID: Int, episode: Double) -> EpisodeProgress? {
        data.progress[String(animeID)]?[LibraryData.episodeKey(episode)]
    }

    func progress(animeID: Int) -> [String: EpisodeProgress] {
        data.progress[String(animeID)] ?? [:]
    }

    func preferredVoice(animeID: Int) -> String? { data.lastVoice[String(animeID)] }
    func preferredPlayer(animeID: Int) -> String? { data.lastPlayer?[String(animeID)] }

    func rememberPlayer(animeID: Int, player: String?) {
        var players = data.lastPlayer ?? [:]
        players[String(animeID)] = player
        data.lastPlayer = players
        scheduleSave()
    }
    func preferredSource(animeID: Int) -> SourceID? { data.lastSource[String(animeID)] }

    func rememberChoice(animeID: Int, source: SourceID, voice: String) {
        data.lastSource[String(animeID)] = source
        data.lastVoice[String(animeID)] = voice
        scheduleSave()
    }

    func updateProgress(anime: SavedAnime, episode: SourceEpisode, position: Double, duration: Double?, now: Date = Date()) {
        let key = String(anime.id)
        let progress = EpisodeProgress(episodeNumber: episode.number, position: max(0, position), duration: duration, updatedAt: now)
        data.progress[key, default: [:]][LibraryData.episodeKey(episode.number)] = progress
        data.lastSource[key] = episode.source
        data.lastVoice[key] = episode.voice

        let record = WatchRecord(
            anime: anime,
            source: episode.source,
            voice: episode.voice,
            episodeNumber: episode.number,
            episodeTitle: episode.displayTitle,
            position: progress.position,
            duration: duration,
            updatedAt: now
        )
        data.history.removeAll { $0.anime.id == anime.id }
        data.history.append(record)
        if data.history.count > Self.historyLimit {
            data.history = Array(data.history.sorted { $0.updatedAt > $1.updatedAt }.prefix(Self.historyLimit))
        }
        scheduleSave()
    }

    func markWatched(_ watched: Bool, anime: SavedAnime, episode: SourceEpisode) {
        if watched {
            let duration = episode.duration ?? 1
            updateProgress(anime: anime, episode: episode, position: duration, duration: duration)
        } else {
            data.progress[String(anime.id)]?[LibraryData.episodeKey(episode.number)] = nil
            scheduleSave()
        }
    }

    func removeFromHistory(_ animeID: Int) {
        data.history.removeAll { $0.anime.id == animeID }
        scheduleSave()
    }

    func clearHistory() {
        data.history.removeAll()
        data.progress.removeAll()
        scheduleSave()
    }

    // MARK: Stats

    var watchedEpisodesCount: Int {
        data.progress.values.reduce(0) { $0 + $1.values.filter(\.isWatched).count }
    }

    /// Total watch time in seconds: full duration for finished episodes, position for the rest.
    var watchedSeconds: Double {
        data.progress.values.reduce(0) { total, episodes in
            total + episodes.values.reduce(0) { $0 + ($1.isWatched ? ($1.duration ?? $1.position) : $1.position) }
        }
    }

    // MARK: Persistence

    /// Progress is updated every few seconds while playing, so writes are coalesced.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoded = try JSONEncoder().encode(data)
            try encoded.write(to: fileURL, options: .atomic)
        } catch {
            assertionFailure("Library save failed: \(error)")
        }
    }
}
