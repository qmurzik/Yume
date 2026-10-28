import Combine
import Foundation

@MainActor
final class AnimeDetailViewModel: ObservableObject {
    let animeID: Int
    @Published private(set) var anime: Loadable<Anime>
    @Published private(set) var similar: Loadable<[Anime]> = .idle
    @Published private(set) var sourceID: SourceID?
    @Published private(set) var episodesState: Loadable<[SourceEpisode]> = .idle
    @Published var voice: String?

    let availableSources: [SourceID]
    /// Sources switched off in this build, e.g. YummyAnime without an application key.
    let disabledSources: [SourceID]
    /// Sources already checked that don't have this title.
    @Published private(set) var missingIn: [SourceID] = []
    private let services: AppServices
    /// While false, a source without the title is skipped automatically.
    private var userPickedSource: Bool
    private var cache: [SourceID: [SourceEpisode]] = [:]
    private var preferredVoice: String?
    private var sourceTask: Task<Void, Never>?

    init(route: AnimeRoute, preferredSource: SourceID?, preferredVoice: String?, services: AppServices = .live) {
        animeID = route.id
        anime = route.preview.map(Loadable.loaded) ?? .idle
        self.services = services
        self.preferredVoice = preferredVoice
        availableSources = services.sources.available.map(\.id)
        disabledSources = services.sources.sources.filter { !$0.isAvailable }.map(\.id)
        let preferred = preferredSource.flatMap { services.sources.available.map(\.id).contains($0) ? $0 : nil }
        userPickedSource = preferred != nil
        sourceID = preferred ?? availableSources.first
    }

    var hasDetails: Bool { anime.value?.studios.isEmpty == false || anime.value?.description != nil }

    /// Episodes per voice, for the voice chips.
    var voiceCounts: [String: Int] {
        Dictionary(grouping: episodesState.value ?? [], by: \.voice).mapValues(\.count)
    }

    /// Voices sorted by how many episodes they have, most complete first.
    var voices: [String] {
        let all = episodesState.value ?? []
        let counts = Dictionary(grouping: all, by: \.voice).mapValues(\.count)
        return counts.keys.sorted { (counts[$0] ?? 0, $1) > (counts[$1] ?? 0, $0) }
    }

    var episodes: [SourceEpisode] {
        guard let all = episodesState.value else { return [] }
        let selected = voice ?? voices.first
        return all.filter { $0.voice == selected }.sorted { $0.number < $1.number }
    }

    func load() async {
        if !hasDetails { await loadAnime() }
        guard anime.value != nil else { return }
        async let similarLoad: Void = loadSimilar()
        async let sourceLoad: Void = loadEpisodes()
        _ = await (similarLoad, sourceLoad)
    }

    func reloadAll() async {
        cache = [:]
        await loadAnime()
        guard anime.value != nil else { return }
        async let similarLoad: Void = loadSimilar()
        async let sourceLoad: Void = loadEpisodes(force: true)
        _ = await (similarLoad, sourceLoad)
    }

    func loadAnime() async {
        let hadPreview = anime.value != nil
        if !hadPreview { anime = .loading }
        do {
            anime = .loaded(try await services.shikimori.anime(id: animeID))
        } catch is CancellationError {
        } catch {
            // A preview from the list is still useful; only show the error when there's nothing.
            if !hadPreview { anime = .failed(error) }
        }
    }

    func loadSimilar() async {
        guard similar.isIdle || { if case .failed = similar { return true }; return false }() else { return }
        similar = .loading
        do {
            similar = .loaded(try await services.shikimori.similar(to: animeID))
        } catch is CancellationError {
            similar = .idle
        } catch {
            similar = .failed(error)
        }
    }

    func selectSource(_ id: SourceID) {
        guard id != sourceID else { return }
        userPickedSource = true
        sourceID = id
        voice = nil
        sourceTask?.cancel()
        sourceTask = Task { await loadEpisodes() }
    }

    func loadEpisodes(force: Bool = false) async {
        guard let sourceID, services.sources.source(sourceID) != nil, anime.value != nil else {
            episodesState = .failed(APIError.sourceUnavailable(self.sourceID?.title ?? "—"))
            return
        }
        if !force, let cached = cache[sourceID] {
            setEpisodes(cached)
            return
        }
        if force { missingIn = [] }
        episodesState = .loading
        var candidate: SourceID? = sourceID
        while let current = candidate {
            if let cached = cache[current] {
                setEpisodes(cached)
                return
            }
            do {
                let list = try await fetchEpisodes(from: current)
                guard self.sourceID == current else { return }
                cache[current] = list
                setEpisodes(list)
                return
            } catch is CancellationError {
                return
            } catch where error.isNotFound && !userPickedSource {
                // Not in this source: move on to the next one the user hasn't ruled out.
                if !missingIn.contains(current) { missingIn.append(current) }
                candidate = availableSources.first { !missingIn.contains($0) }
                if let next = candidate { self.sourceID = next }
            } catch {
                guard self.sourceID == current else { return }
                if error.isNotFound, !missingIn.contains(current) { missingIn.append(current) }
                episodesState = .failed(error)
                return
            }
        }
        // No source has the title; show the first one's "not found" state.
        self.sourceID = availableSources.first
        episodesState = .failed(APIError.notFound)
    }

    private func fetchEpisodes(from id: SourceID) async throws -> [SourceEpisode] {
        guard let source = services.sources.source(id), let anime = anime.value else {
            throw APIError.sourceUnavailable(id.title)
        }
        guard let title = try await source.findTitle(for: anime) else { throw APIError.notFound }
        let list = try await source.episodes(for: title)
        if list.isEmpty { throw APIError.notFound }
        return list
    }

    private func setEpisodes(_ list: [SourceEpisode]) {
        episodesState = .loaded(list)
        let options = voices
        if let current = voice, options.contains(current) { return }
        voice = preferredVoice.flatMap { options.contains($0) ? $0 : nil } ?? options.first
    }
}
