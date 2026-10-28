import AVFoundation
import Combine
import Foundation

@MainActor
final class PlayerViewModel: ObservableObject {
    enum Phase {
        case loading
        case failed(Error)
        case native
        case embed(URL)
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var index: Int
    @Published private(set) var qualities: [StreamQuality] = []
    @Published private(set) var quality: StreamQuality?
    @Published private(set) var canSkipOpening = false
    @Published private(set) var isInEnding = false
    @Published private(set) var didFinish = false

    let player = AVPlayer()
    let context: PlayerContext

    private let library: LibraryStore
    private let source: (any AnimeSource)?
    private var stream: StreamInfo?
    private var pendingSeek: Double?
    private var lastSavedPosition: Double = 0
    private var loadTask: Task<Void, Never>?
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?

    private static let qualityKey = "player.preferredQuality"
    private static let saveInterval: Double = 5

    init(context: PlayerContext, library: LibraryStore, services: AppServices = .live) {
        self.context = context
        self.library = library
        self.index = context.startIndex
        self.source = services.sources.source(context.source)
        player.allowsExternalPlayback = true
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor in self?.tick(time.seconds) }
        }
    }

    var episode: SourceEpisode { context.episodes[index] }
    var hasNext: Bool { index + 1 < context.episodes.count }
    var hasPrevious: Bool { index > 0 }

    // MARK: Loading

    func start() {
        if case .loading = phase, loadTask == nil { load(index: index) }
    }

    func retry() { load(index: index) }

    func playNext() {
        guard hasNext else { return }
        if case .native = phase { saveProgress(markFinished: true) }
        load(index: index + 1)
    }

    func playPrevious() {
        guard hasPrevious else { return }
        saveProgress()
        load(index: index - 1)
    }

    private func load(index newIndex: Int) {
        if newIndex != index { saveProgress() }
        loadTask?.cancel()
        index = newIndex
        phase = .loading
        didFinish = false
        canSkipOpening = false
        isInEnding = false
        stream = nil
        qualities = []
        player.pause()
        player.replaceCurrentItem(with: nil)

        let episode = self.episode
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                guard let source = self.source else { throw APIError.sourceUnavailable(self.context.source.title) }
                let info = try await source.stream(for: episode)
                try Task.checkCancellation()
                self.begin(info)
            } catch is CancellationError {
            } catch {
                self.phase = .failed(error)
            }
        }
    }

    private func begin(_ info: StreamInfo) {
        var info = info
        // Prefer timings from the stream, fall back to the episode list.
        info.opening = info.opening ?? episode.opening
        info.ending = info.ending ?? episode.ending
        stream = info

        switch info.kind {
        case .hls(let list) where list.isEmpty:
            phase = .failed(APIError.server("Для этой серии нет видеопотока."))
        case .hls:
            qualities = info.qualities
            let preferred = UserDefaults.standard.integer(forKey: Self.qualityKey)
            let chosen = qualities.first { $0.height == preferred }
                ?? qualities.first { $0.height <= max(preferred, 1080) }
                ?? qualities.first
            phase = .native
            if let chosen { play(chosen, at: resumePosition()) }
        case .embed(let url):
            phase = .embed(url)
            // The web player can't report its position; remember that the episode was opened.
            library.updateProgress(anime: context.anime, episode: episode, position: 0, duration: episode.duration)
        }
    }

    private func resumePosition() -> Double {
        guard let saved = library.progress(animeID: context.anime.id, episode: episode.number),
              !saved.isWatched, saved.position > 10 else { return 0 }
        return saved.position - 3
    }

    private func play(_ quality: StreamQuality, at position: Double) {
        self.quality = quality
        let item = AVPlayerItem(url: quality.url)
        pendingSeek = position > 0 ? position : nil
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in self?.statusChanged(item) }
        }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.finished() }
        }
        player.replaceCurrentItem(with: item)
        player.play()
    }

    private func statusChanged(_ item: AVPlayerItem) {
        guard item === player.currentItem else { return }
        switch item.status {
        case .readyToPlay:
            if let seek = pendingSeek {
                pendingSeek = nil
                player.seek(to: CMTime(seconds: seek, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            }
            player.play()
        case .failed:
            phase = .failed(APIError.transport(item.error?.localizedDescription ?? "не удалось воспроизвести поток"))
        default:
            break
        }
    }

    // MARK: Controls

    func select(_ newQuality: StreamQuality) {
        guard newQuality != quality else { return }
        UserDefaults.standard.set(newQuality.height, forKey: Self.qualityKey)
        let position = player.currentTime().seconds
        play(newQuality, at: position.isFinite ? position : 0)
    }

    func skipOpening() {
        guard let opening = stream?.opening else { return }
        player.seek(to: CMTime(seconds: opening.end, preferredTimescale: 600))
        canSkipOpening = false
    }

    func stop() {
        loadTask?.cancel()
        saveProgress()
        player.pause()
        library.saveNow()
    }

    // MARK: Progress

    private func tick(_ time: Double) {
        guard time.isFinite, case .native = phase else { return }
        canSkipOpening = stream?.opening.map { $0.contains(time) && $0.end - time > 2 } ?? false
        isInEnding = stream?.ending?.contains(time) ?? false
        if abs(time - lastSavedPosition) >= Self.saveInterval { saveProgress() }
    }

    private var currentDuration: Double? {
        let seconds = player.currentItem?.duration.seconds ?? .nan
        return seconds.isFinite && seconds > 0 ? seconds : episode.duration
    }

    private func saveProgress(markFinished: Bool = false) {
        guard case .native = phase, player.currentItem != nil else { return }
        let duration = currentDuration
        var position = player.currentTime().seconds
        if markFinished, let duration { position = duration }
        guard position.isFinite, position > 1 else { return }
        lastSavedPosition = position
        library.updateProgress(anime: context.anime, episode: episode, position: position, duration: duration)
    }

    private func finished() {
        saveProgress(markFinished: true)
        didFinish = true
        isInEnding = false
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    }
}
