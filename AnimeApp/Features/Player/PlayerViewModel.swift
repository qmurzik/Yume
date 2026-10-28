import AVFoundation
import AVKit
import Combine
import Foundation
import MediaPlayer

@MainActor
final class PlayerViewModel: NSObject, ObservableObject {
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

    // Playback state for the custom controls.
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var bufferedTime: Double = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var isBuffering = false
    @Published private(set) var rate: Float = 1
    @Published private(set) var isScrubbing = false
    @Published private(set) var scrubTime: Double = 0

    @Published private(set) var canSkipOpening = false
    @Published private(set) var isInEnding = false
    @Published private(set) var didFinish = false
    /// Seconds left before the next episode starts by itself; nil when no countdown runs.
    @Published private(set) var autoplayCountdown: Int?

    @Published private(set) var isPictureInPicturePossible = false
    @Published private(set) var isPictureInPictureActive = false

    let player = AVPlayer()
    let context: PlayerContext
    static let rates: [Float] = [0.75, 1, 1.25, 1.5, 2]

    private let library: LibraryStore
    private let source: (any AnimeSource)?
    private var stream: StreamInfo?
    private var pendingSeek: Double?
    private var failedQualities: Set<Int> = []
    private var lastSavedPosition: Double = 0
    private var loadTask: Task<Void, Never>?
    private var countdownTask: Task<Void, Never>?
    private var timeObserver: Any?
    private var playerObservation: NSKeyValueObservation?
    private var itemObservations: [NSKeyValueObservation] = []
    private var endObserver: NSObjectProtocol?
    private var pipController: AVPictureInPictureController?
    private var pipObservations: [NSKeyValueObservation] = []

    private static let qualityKey = "player.preferredQuality"
    private static let rateKey = "player.rate"
    private static let autoplayKey = "player.autoplayNext"
    private static let saveInterval: Double = 5

    init(context: PlayerContext, library: LibraryStore, services: AppServices = .live) {
        self.context = context
        self.library = library
        self.index = context.startIndex
        self.source = services.sources.source(context.source)
        super.init()
        let savedRate = UserDefaults.standard.float(forKey: Self.rateKey)
        rate = Self.rates.contains(savedRate) ? savedRate : 1
        player.allowsExternalPlayback = true
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor in self?.tick(time.seconds) }
        }
        playerObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            let status = player.timeControlStatus
            Task { @MainActor in
                self?.isPlaying = status != .paused
                self?.isBuffering = status == .waitingToPlayAtSpecifiedRate
                self?.updateNowPlaying()
            }
        }
        setUpRemoteCommands()
    }

    var episode: SourceEpisode { context.episodes[index] }
    var hasNext: Bool { index + 1 < context.episodes.count }
    var hasPrevious: Bool { index > 0 }
    var nextEpisode: SourceEpisode? { hasNext ? context.episodes[index + 1] : nil }
    var isNative: Bool { if case .native = phase { return true }; return false }

    var autoplayEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.autoplayKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.autoplayKey); objectWillChange.send() }
    }

    // MARK: Loading

    func start() {
        if case .loading = phase, loadTask == nil { load(index: index) }
    }

    func retry() { load(index: index) }

    func play(episodeAt newIndex: Int) {
        guard context.episodes.indices.contains(newIndex), newIndex != index else { return }
        saveProgress()
        load(index: newIndex)
    }

    func playNext() {
        guard hasNext else { return }
        if isNative, didFinish || isInEnding { saveProgress(markFinished: true) }
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
        cancelAutoplay()
        index = newIndex
        phase = .loading
        didFinish = false
        canSkipOpening = false
        isInEnding = false
        stream = nil
        qualities = []
        failedQualities = []
        currentTime = 0
        duration = episode.duration ?? 0
        bufferedTime = 0
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
        case .native(let list) where list.isEmpty:
            phase = .failed(APIError.server("Для этой серии нет видеопотока."))
        case .native:
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
        item.preferredForwardBufferDuration = 30
        pendingSeek = position > 0 ? position : nil
        itemObservations = [
            item.observe(\.status, options: [.new]) { [weak self] item, _ in
                Task { @MainActor in self?.statusChanged(item) }
            },
            item.observe(\.loadedTimeRanges, options: [.new]) { [weak self] item, _ in
                let end = item.loadedTimeRanges.last.map { CMTimeRangeGetEnd($0.timeRangeValue).seconds } ?? 0
                Task { @MainActor in self?.bufferedTime = end.isFinite ? end : 0 }
            },
        ]
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.finished() }
        }
        player.replaceCurrentItem(with: item)
        player.playImmediately(atRate: rate)
    }

    private func statusChanged(_ item: AVPlayerItem) {
        guard item === player.currentItem else { return }
        switch item.status {
        case .readyToPlay:
            let seconds = item.duration.seconds
            if seconds.isFinite, seconds > 0 { duration = seconds }
            if let seek = pendingSeek {
                pendingSeek = nil
                player.seek(to: CMTime(seconds: seek, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            }
            player.playImmediately(atRate: rate)
            updateNowPlaying()
        case .failed:
            if let current = quality { failedQualities.insert(current.height) }
            if let fallback = qualities.first(where: { !failedQualities.contains($0.height) }) {
                let position = pendingSeek ?? player.currentTime().seconds
                play(fallback, at: position.isFinite ? position : 0)
            } else {
                phase = .failed(APIError.transport(item.error?.localizedDescription ?? "не удалось воспроизвести поток"))
            }
        default:
            break
        }
    }

    // MARK: Controls

    func togglePlay() {
        if isPlaying {
            player.pause()
        } else {
            if didFinish { seek(to: 0) }
            player.playImmediately(atRate: rate)
        }
        cancelAutoplay()
    }

    func seek(to time: Double) {
        let target = max(0, min(time, duration > 0 ? duration - 0.5 : time))
        currentTime = target
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        if target < duration - 1 { didFinish = false }
    }

    func skip(by seconds: Double) {
        seek(to: (isScrubbing ? scrubTime : currentTime) + seconds)
    }

    func beginScrub() {
        isScrubbing = true
        scrubTime = currentTime
    }

    func updateScrub(fraction: Double) {
        guard duration > 0 else { return }
        scrubTime = max(0, min(1, fraction)) * duration
    }

    func endScrub() {
        seek(to: scrubTime)
        isScrubbing = false
    }

    func setRate(_ newRate: Float) {
        rate = newRate
        UserDefaults.standard.set(newRate, forKey: Self.rateKey)
        if isPlaying { player.rate = newRate }
    }

    func select(_ newQuality: StreamQuality) {
        guard newQuality != quality else { return }
        UserDefaults.standard.set(newQuality.height, forKey: Self.qualityKey)
        failedQualities.remove(newQuality.height)
        let position = player.currentTime().seconds
        play(newQuality, at: position.isFinite ? position : 0)
    }

    func skipOpening() {
        guard let opening = stream?.opening else { return }
        seek(to: opening.end)
        canSkipOpening = false
    }

    func stop() {
        loadTask?.cancel()
        cancelAutoplay()
        saveProgress()
        player.pause()
        library.saveNow()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: Next episode countdown

    func cancelAutoplay() {
        countdownTask?.cancel()
        countdownTask = nil
        autoplayCountdown = nil
    }

    private func startAutoplayCountdown() {
        guard hasNext, autoplayEnabled, countdownTask == nil else { return }
        countdownTask = Task { [weak self] in
            for remaining in stride(from: 8, through: 1, by: -1) {
                await MainActor.run { self?.autoplayCountdown = remaining }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
            }
            await MainActor.run {
                self?.countdownTask = nil
                self?.autoplayCountdown = nil
                self?.playNext()
            }
        }
    }

    // MARK: Picture in Picture

    func attach(layer: AVPlayerLayer) {
        guard AVPictureInPictureController.isPictureInPictureSupported(),
              pipController?.playerLayer !== layer else { return }
        let created: AVPictureInPictureController? = AVPictureInPictureController(playerLayer: layer)
        guard let controller = created else { return }
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.delegate = self
        pipController = controller
        pipObservations = [
            controller.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] controller, _ in
                let possible = controller.isPictureInPicturePossible
                Task { @MainActor in self?.isPictureInPicturePossible = possible }
            },
            controller.observe(\.isPictureInPictureActive, options: [.initial, .new]) { [weak self] controller, _ in
                let active = controller.isPictureInPictureActive
                Task { @MainActor in self?.isPictureInPictureActive = active }
            },
        ]
    }

    func togglePictureInPicture() {
        guard let pipController else { return }
        if pipController.isPictureInPictureActive {
            pipController.stopPictureInPicture()
        } else {
            pipController.startPictureInPicture()
        }
    }

    // MARK: Progress

    private func tick(_ time: Double) {
        guard time.isFinite, isNative else { return }
        if !isScrubbing { currentTime = time }
        if let seconds = player.currentItem?.duration.seconds, seconds.isFinite, seconds > 0 { duration = seconds }
        canSkipOpening = stream?.opening.map { $0.contains(time) && $0.end - time > 2 } ?? false
        let inEnding = stream?.ending?.contains(time) ?? false
        if inEnding != isInEnding {
            isInEnding = inEnding
            if inEnding { startAutoplayCountdown() }
        }
        if abs(time - lastSavedPosition) >= Self.saveInterval { saveProgress() }
    }

    private var currentDuration: Double? {
        duration > 0 ? duration : episode.duration
    }

    private func saveProgress(markFinished: Bool = false) {
        guard isNative, player.currentItem != nil else { return }
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
        startAutoplayCountdown()
    }

    // MARK: Lock screen & Control Center

    private func updateNowPlaying() {
        guard isNative else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: episode.displayTitle,
            MPMediaItemPropertyAlbumTitle: context.anime.title,
            MPMediaItemPropertyArtist: episode.voice,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(rate) : 0,
        ]
    }

    private func setUpRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.player.playImmediately(atRate: self?.rate ?? 1) }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.player.pause() }
            return .success
        }
        center.skipForwardCommand.preferredIntervals = [10]
        center.skipForwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skip(by: 10) }
            return .success
        }
        center.skipBackwardCommand.preferredIntervals = [10]
        center.skipBackwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skip(by: -10) }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.playNext() }
            return .success
        }
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        let center = MPRemoteCommandCenter.shared()
        [center.playCommand, center.pauseCommand, center.skipForwardCommand, center.skipBackwardCommand, center.nextTrackCommand]
            .forEach { $0.removeTarget(nil) }
    }
}

extension PlayerViewModel: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(true)
    }
}
