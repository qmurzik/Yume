import Combine
import Foundation

@MainActor
final class AnimeDetailViewModel: ObservableObject {
    let animeID: Int
    @Published private(set) var anime: Loadable<Anime>
    @Published private(set) var similar: Loadable<[Anime]> = .idle
    @Published private(set) var sourceID: SourceID?
    @Published private(set) var episodesState: Loadable<[SourceEpisode]> = .idle
    @Published var voice: String? {
        didSet { if voice != oldValue { player = nil } }
    }
    /// Preferred embedded player for the voice; nil means "most complete".
    @Published var player: String?

    @Published private(set) var availableSources: [SourceID]
    /// Sources switched off, e.g. YummyAnime until the user signs in.
    @Published private(set) var disabledSources: [SourceID]
    /// Sources already checked that don't have this title.
    @Published private(set) var missingIn: [SourceID] = []
    private let services: AppServices
    /// While false, a source without the title is skipped automatically.
    private var userPickedSource: Bool
    private var cache: [SourceID: [SourceEpisode]] = [:]
    private var preferredVoice: String?
    private var sourceTask: Task<Void, Never>?

    private var preferredPlayer: String?

    init(route: AnimeRoute, preferredSource: SourceID?, preferredVoice: String?, preferredPlayer: String? = nil,
         services: AppServices = .live) {
        self.preferredPlayer = preferredPlayer
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

    /// Distinct episodes per voice, for the voice chips.
    var voiceCounts: [String: Int] { EpisodeGrouping.episodeCounts(episodesState.value ?? []) }

    /// Voices sorted by how many episodes they have, most complete first.
    var voices: [String] { EpisodeGrouping.voices(episodesState.value ?? []) }

    private var selectedVoice: String? { voice ?? voices.first }

    /// Embedded players offering the selected voice (YummyAnime), most complete first.
    var players: [String] {
        guard let voice = selectedVoice else { return [] }
        return EpisodeGrouping.players(episodesState.value ?? [], voice: voice)
    }

    /// One copy per episode: the chosen player, filling gaps from the others.
    var episodes: [SourceEpisode] {
        guard let all = episodesState.value, let voice = selectedVoice else { return [] }
        return EpisodeGrouping.episodes(all, voice: voice, preferredPlayer: player)
    }

    var alternatives: [String: [SourceEpisode]] {
        guard let all = episodesState.value, let voice = selectedVoice else { return [:] }
        return EpisodeGrouping.alternatives(all, voice: voice, preferredPlayer: player)
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

    /// Picks up sources enabled meanwhile (signing in to YummyAnime) and retries if nothing was found.
    func refreshSources() {
        let available = services.sources.available.map(\.id)
        guard available != availableSources else { return }
        let added = available.filter { !availableSources.contains($0) }
        availableSources = available
        disabledSources = services.sources.sources.filter { !$0.isAvailable }.map(\.id)
        if case .failed(let error) = episodesState, error.isNotFound, let first = added.first {
            sourceID = first
            sourceTask?.cancel()
            sourceTask = Task { await loadEpisodes() }
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
        if let preferredPlayer, players.contains(preferredPlayer) { player = preferredPlayer }
    }
}
