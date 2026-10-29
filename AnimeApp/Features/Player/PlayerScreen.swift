import SwiftUI

struct PlayerScreen: View {
    @StateObject private var model: PlayerViewModel
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss

    @State private var controlsVisible = true
    @State private var hideTask: Task<Void, Never>?
    @State private var showEpisodes = false
    @State private var seekBubble: SeekBubble?
    @State private var fillScreen = false
    @State private var isLandscape = false
    @State private var isLocked = false
    @State private var dragOffset: CGFloat = 0

    private struct SeekBubble: Equatable {
        let forward: Bool
        var seconds: Int
        let id = UUID()
    }

    /// Sizes of the overlay: compact on the 16:9 strip in portrait, roomy in fullscreen.
    private struct Metrics {
        let icon: CGFloat
        let play: CGFloat
        let playGlyph: CGFloat
        let skipGlyph: CGFloat
        let spacing: CGFloat
        let padding: CGFloat

        static let compact = Metrics(icon: 34, play: 58, playGlyph: 24, skipGlyph: 22, spacing: 30, padding: 10)
        static let full = Metrics(icon: 42, play: 76, playGlyph: 32, skipGlyph: 28, spacing: 44, padding: 24)
    }

    private var metrics: Metrics { isLandscape ? .full : .compact }

    init(context: PlayerContext, library: LibraryStore) {
        _model = StateObject(wrappedValue: PlayerViewModel(context: context, library: library))
    }

    var body: some View {
        GeometryReader { proxy in
            let landscape = proxy.size.width > proxy.size.height
            ZStack {
                Color.black.ignoresSafeArea()
                if landscape {
                    videoArea.ignoresSafeArea()
                } else {
                    VStack(spacing: 0) {
                        videoArea
                            .frame(width: proxy.size.width, height: proxy.size.width * 9 / 16)
                        PortraitPanel(model: model, progress: library.progress(animeID: model.context.anime.id))
                    }
                }
            }
            .onAppear { isLandscape = landscape }
            .onChange(of: landscape) { value in
                withAnimation(Motion.spring) { isLandscape = value }
                scheduleHide()
            }
        }
        .offset(y: dragOffset)
        .preferredColorScheme(.dark)
        .statusBarHidden(isLandscape)
        .persistentSystemOverlays(isLandscape ? .hidden : .automatic)
        .onAppear {
            model.start()
            scheduleHide()
        }
        .onDisappear {
            model.stop()
            if isLandscape { Orientation.set(landscape: false) }
        }
        .onChange(of: model.isPlaying) { _ in scheduleHide() }
        .sheet(isPresented: $showEpisodes) {
            EpisodesSheet(model: model, progress: library.progress(animeID: model.context.anime.id)) { index in
                showEpisodes = false
                model.play(episodeAt: index)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: Video area

    private var videoArea: some View {
        ZStack {
            Color.black
            switch model.phase {
            case .loading:
                VStack(spacing: 12) {
                    ProgressView().tint(.white).controlSize(.large)
                    if isLandscape {
                        Text(model.episode.displayTitle).font(.headline).foregroundStyle(.white)
                    }
                }
                closeOverlay
            case .failed(let error):
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.title2).foregroundStyle(.orange)
                    Text(error.localizedDescription)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(.horizontal, 24)
                    HStack(spacing: 10) {
                        Button("Повторить") { model.retry() }.buttonStyle(PrimaryButtonStyle())
                        if let other = model.alternatives.first(where: { $0.id != model.episode.id }) {
                            Button("Другой плеер") { model.switchPlayer(to: other) }.buttonStyle(GlassButtonStyle())
                        }
                    }
                }
                closeOverlay
            case .native:
                nativePlayer
            case .embed(let url):
                EmbedPlayerView(url: url)
                if isLandscape { closeOverlay }
            }
        }
        .clipped()
    }

    private var closeOverlay: some View {
        VStack {
            HStack {
                closeButton
                Spacer()
            }
            Spacer()
        }
        .padding(metrics.padding)
    }

    private var nativePlayer: some View {
        ZStack {
            PlayerLayerView(player: model.player, gravity: fillScreen && isLandscape ? .resizeAspectFill : .resizeAspect) { layer in
                model.attach(layer: layer)
            }

            gestureLayer

            if isLocked {
                lockedOverlay
            } else if controlsVisible {
                controls.transition(.opacity)
            }

            if let bubble = seekBubble {
                seekBubbleView(bubble)
            }

            if model.canSkipOpening && !isLocked {
                skipOpeningButton
            }

            if isLandscape, let next = model.nextEpisode, model.autoplayCountdown != nil || model.didFinish {
                nextEpisodeCard(next)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: controlsVisible)
        .animation(Motion.snappy, value: isLocked)
        .animation(Motion.spring, value: model.canSkipOpening)
        .animation(Motion.spring, value: model.autoplayCountdown != nil || model.didFinish)
    }

    /// Single tap toggles the controls, double tap on either half seeks 10 seconds.
    private var gestureLayer: some View {
        HStack(spacing: 0) {
            tapZone(forward: false)
            tapZone(forward: true)
        }
        .simultaneousGesture(dismissDrag)
    }

    private func tapZone(forward: Bool) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                TapGesture(count: 2)
                    .onEnded { if !isLocked { doubleTapSeek(forward: forward) } }
                    .exclusively(before: TapGesture().onEnded { if !isLocked { toggleControls() } })
            )
    }

    /// Swipe down closes the player (portrait); in landscape it leaves fullscreen first.
    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 24)
            .onChanged { value in
                guard !isLocked, value.translation.height > 0,
                      abs(value.translation.height) > abs(value.translation.width) else { return }
                if !isLandscape { dragOffset = value.translation.height }
            }
            .onEnded { value in
                let far = value.translation.height > 140 || value.predictedEndTranslation.height > 420
                if far, !isLocked {
                    Haptics.tap()
                    if isLandscape {
                        Orientation.set(landscape: false)
                    } else {
                        dismiss()
                    }
                }
                withAnimation(Motion.spring) { dragOffset = 0 }
            }
    }

    // MARK: Controls

    private var controls: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.7), location: 0),
                    .init(color: .black.opacity(0.15), location: 0.3),
                    .init(color: .black.opacity(0.15), location: 0.65),
                    .init(color: .black.opacity(0.8), location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                centerControls
                Spacer(minLength: 0)
                bottomBar
            }
            .padding(.horizontal, metrics.padding)
            .padding(.vertical, isLandscape ? 16 : 6)
        }
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: metrics.icon * 0.4, weight: .bold))
                .frame(width: metrics.icon, height: metrics.icon)
                .background(.ultraThinMaterial, in: Circle())
        }
        .foregroundStyle(.white)
        .accessibilityLabel("Закрыть плеер")
    }

    private var topBar: some View {
        HStack(spacing: isLandscape ? 12 : 8) {
            closeButton
            if isLandscape {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.context.anime.title).font(.subheadline.weight(.bold)).lineLimit(1)
                    Text(episodeSubtitle).font(.caption).foregroundStyle(Theme.secondaryText).lineLimit(1)
                }
                .foregroundStyle(.white)
            }
            Spacer(minLength: 4)
            iconButton("lock.fill", label: "Заблокировать управление") {
                Haptics.success()
                isLocked = true
                controlsVisible = false
            }
            AirPlayButton().frame(width: metrics.icon - 4, height: metrics.icon - 4)
            if model.isPictureInPicturePossible {
                iconButton(model.isPictureInPictureActive ? "pip.exit" : "pip.enter", label: "Картинка в картинке") {
                    model.togglePictureInPicture()
                }
            }
            settingsMenu
        }
    }

    private var episodeSubtitle: String {
        [model.episode.displayTitle, model.episode.voice, model.episode.player].compactMap { $0 }.joined(separator: " · ")
    }

    private var settingsMenu: some View {
        Menu {
            if model.qualities.count > 1 {
                Picker(selection: Binding(get: { model.quality ?? model.qualities[0] }, set: { model.select($0) })) {
                    ForEach(model.qualities) { quality in
                        Text(quality.label).tag(quality)
                    }
                } label: {
                    Label("Качество: \(model.quality?.label ?? "")", systemImage: "sparkles.tv")
                }
                .pickerStyle(.menu)
            }
            if model.alternatives.count > 1 {
                Picker(selection: Binding(get: { model.episode }, set: { model.switchPlayer(to: $0) })) {
                    ForEach(model.alternatives) { copy in
                        Text(copy.player ?? "Плеер").tag(copy)
                    }
                } label: {
                    Label("Плеер: \(model.episode.player ?? "")", systemImage: "play.rectangle.on.rectangle")
                }
                .pickerStyle(.menu)
            }
            Picker(selection: Binding(get: { model.rate }, set: { model.setRate($0) })) {
                ForEach(PlayerViewModel.rates, id: \.self) { rate in
                    Text(rate == 1 ? "Обычная" : String(format: "%gx", rate)).tag(rate)
                }
            } label: {
                Label("Скорость: \(model.rate == 1 ? "1x" : String(format: "%gx", model.rate))", systemImage: "speedometer")
            }
            .pickerStyle(.menu)
            Toggle(isOn: Binding(get: { model.autoplayEnabled }, set: { model.autoplayEnabled = $0 })) {
                Label("Автовоспроизведение", systemImage: "forward.end.alt")
            }
            if isLandscape {
                Toggle(isOn: $fillScreen) {
                    Label("Заполнить экран", systemImage: "arrow.up.left.and.arrow.down.right")
                }
            }
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: metrics.icon * 0.42, weight: .semibold))
                .frame(width: metrics.icon, height: metrics.icon)
                .background(.ultraThinMaterial, in: Circle())
                .foregroundStyle(.white)
        }
    }

    private func iconButton(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            scheduleHide()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: metrics.icon * 0.42, weight: .semibold))
                .frame(width: metrics.icon, height: metrics.icon)
                .background(.ultraThinMaterial, in: Circle())
        }
        .foregroundStyle(.white)
        .accessibilityLabel(label)
    }

    private var centerControls: some View {
        HStack(spacing: metrics.spacing) {
            if isLandscape {
                transportButton("backward.end.fill", size: 22, enabled: model.hasPrevious, label: "Предыдущая серия") { model.playPrevious() }
            }
            transportButton("gobackward.10", size: metrics.skipGlyph, label: "Назад на 10 секунд") { model.skip(by: -10) }
            Button {
                Haptics.tap()
                model.togglePlay()
                scheduleHide()
            } label: {
                ZStack {
                    Circle().fill(.ultraThinMaterial).frame(width: metrics.play, height: metrics.play)
                    if model.isBuffering {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: metrics.playGlyph, weight: .bold))
                            .offset(x: model.isPlaying ? 0 : 2)
                            .id(model.isPlaying)
                            .transition(.scale(scale: 0.5).combined(with: .opacity))
                    }
                }
            }
            .buttonStyle(PressableStyle(scale: 0.9))
            .foregroundStyle(.white)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: model.isPlaying)
            .animation(Motion.fade, value: model.isBuffering)
            .accessibilityLabel(model.isPlaying ? "Пауза" : "Смотреть")
            transportButton("goforward.10", size: metrics.skipGlyph, label: "Вперёд на 10 секунд") { model.skip(by: 10) }
            if isLandscape {
                transportButton("forward.end.fill", size: 22, enabled: model.hasNext, label: "Следующая серия") { model.playNext() }
            }
        }
    }

    private func transportButton(_ systemImage: String, size: CGFloat, enabled: Bool = true, label: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
            scheduleHide()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: size, weight: .semibold))
                .frame(width: size + 22, height: size + 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.85))
        .foregroundStyle(.white.opacity(enabled ? 1 : 0.3))
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private var shownTime: Double { model.isScrubbing ? model.scrubTime : model.currentTime }

    private var scrubber: some View {
        PlayerScrubber(
            current: shownTime,
            buffered: model.bufferedTime,
            duration: model.duration,
            opening: model.episode.opening,
            isScrubbing: model.isScrubbing,
            onBegin: {
                model.beginScrub()
                hideTask?.cancel()
            },
            onChange: { model.updateScrub(fraction: $0) },
            onEnd: {
                model.endScrub()
                scheduleHide()
            }
        )
    }

    @ViewBuilder
    private var bottomBar: some View {
        if isLandscape {
            VStack(spacing: 6) {
                HStack {
                    Text(TimeFormat.string(shownTime))
                    Spacer()
                    Text("-" + TimeFormat.string(max(0, model.duration - shownTime)))
                }
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
                scrubber
                HStack(spacing: 10) {
                    pillButton("Серии", systemImage: "list.bullet") { showEpisodes = true }
                    if model.hasNext {
                        pillButton("Следующая", systemImage: "forward.end.fill") { model.playNext() }
                    }
                    Spacer(minLength: 8)
                    if model.rate != 1 { Tag(text: String(format: "%gx", model.rate), color: Theme.pink) }
                    if let quality = model.quality { Tag(text: quality.label) }
                    iconButton("arrow.down.right.and.arrow.up.left", label: "Выйти из полноэкранного режима") {
                        Orientation.set(landscape: false)
                    }
                }
            }
        } else {
            HStack(spacing: 8) {
                Text(TimeFormat.string(shownTime))
                    .frame(minWidth: 38, alignment: .leading)
                scrubber
                Text(TimeFormat.string(model.duration))
                    .frame(minWidth: 38, alignment: .trailing)
                Button {
                    Haptics.tap()
                    Orientation.set(landscape: true)
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Во весь экран")
            }
            .font(.caption2.monospacedDigit().weight(.semibold))
            .foregroundStyle(.white.opacity(0.9))
        }
    }

    private func pillButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
            scheduleHide()
        } label: {
            Label(title, systemImage: systemImage)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(PressableStyle())
        .foregroundStyle(.white)
    }

    private var lockedOverlay: some View {
        VStack {
            Spacer()
            Button {
                Haptics.success()
                isLocked = false
                controlsVisible = true
                scheduleHide()
            } label: {
                Label("Разблокировать", systemImage: "lock.open.fill")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .foregroundStyle(.white)
            .padding(.bottom, isLandscape ? 36 : 12)
        }
        .transition(.opacity)
    }

    private var skipOpeningButton: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button {
                    Haptics.tap()
                    model.skipOpening()
                } label: {
                    Label("Пропустить опенинг", systemImage: "forward.fill")
                        .font(isLandscape ? .headline : .footnote.weight(.bold))
                        .padding(.horizontal, isLandscape ? 20 : 12)
                        .padding(.vertical, isLandscape ? 13 : 8)
                        .background(Theme.accentGradient, in: Capsule())
                        .foregroundStyle(.white)
                        .shadow(color: Theme.pink.opacity(0.4), radius: 10, y: 4)
                }
                .buttonStyle(PressableStyle())
            }
        }
        .padding(.horizontal, metrics.padding)
        .padding(.bottom, controlsVisible ? (isLandscape ? 120 : 44) : (isLandscape ? 32 : 12))
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    private func nextEpisodeCard(_ next: SourceEpisode) -> some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                NextEpisodeCard(next: next, countdown: model.autoplayCountdown,
                                onPlay: { model.playNext() }, onCancel: { model.cancelAutoplay() })
                    .frame(maxWidth: 340)
            }
        }
        .padding(.horizontal, metrics.padding)
        .padding(.bottom, controlsVisible ? 120 : 32)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func seekBubbleView(_ bubble: SeekBubble) -> some View {
        HStack {
            if bubble.forward { Spacer() }
            VStack(spacing: 4) {
                Image(systemName: bubble.forward ? "goforward" : "gobackward").font(isLandscape ? .title.weight(.bold) : .title3.weight(.bold))
                Text("\(bubble.seconds) сек").font(.caption.weight(.bold))
            }
            .foregroundStyle(.white)
            .frame(width: isLandscape ? 120 : 84, height: isLandscape ? 120 : 84)
            .background(Color.white.opacity(0.14), in: Circle())
            .padding(.horizontal, isLandscape ? 60 : 24)
            .id(bubble.seconds)
            .transition(.scale(scale: 0.7).combined(with: .opacity))
            if !bubble.forward { Spacer() }
        }
        .allowsHitTesting(false)
    }

    // MARK: Behaviour

    private func toggleControls() {
        controlsVisible.toggle()
        if controlsVisible { scheduleHide() }
    }

    private func scheduleHide() {
        hideTask?.cancel()
        guard model.isNative else { return }
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard !Task.isCancelled, model.isPlaying, !model.isScrubbing else { return }
            controlsVisible = false
        }
    }

    private func doubleTapSeek(forward: Bool) {
        Haptics.tap()
        model.skip(by: forward ? 10 : -10)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            if var bubble = seekBubble, bubble.forward == forward {
                bubble.seconds += 10
                seekBubble = bubble
            } else {
                seekBubble = SeekBubble(forward: forward, seconds: 10)
            }
        }
        let current = seekBubble?.id
        Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            if seekBubble?.id == current {
                withAnimation { seekBubble = nil }
            }
        }
    }
}

// MARK: - Portrait panel

/// Below the video in portrait: what's playing, next/previous, player choice and the episode list.
private struct PortraitPanel: View {
    @ObservedObject var model: PlayerViewModel
    let progress: [String: EpisodeProgress]

    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if let next = model.nextEpisode, model.autoplayCountdown != nil || model.didFinish {
                        NextEpisodeCard(next: next, countdown: model.autoplayCountdown,
                                        onPlay: { model.playNext() }, onCancel: { model.cancelAutoplay() })
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    navigation
                    if model.alternatives.count > 1 { players }
                    episodes(reader)
                }
                .padding(16)
                .animation(Motion.spring, value: model.autoplayCountdown != nil || model.didFinish)
                .animation(Motion.spring, value: model.index)
            }
            .onAppear { reader.scrollTo(model.index, anchor: .center) }
            .onChange(of: model.index) { index in
                withAnimation(Motion.spring) { reader.scrollTo(index, anchor: .center) }
            }
        }
        .background(Theme.background)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.context.anime.title)
                .font(.title3.weight(.heavy))
                .foregroundStyle(.white)
                .lineLimit(2)
            Text(model.episode.displayTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(2)
            HStack(spacing: 6) {
                Tag(text: model.episode.voice, color: Theme.pink)
                if let player = model.episode.player { Tag(text: player) }
                if let quality = model.quality { Tag(text: quality.label) }
                if model.rate != 1 { Tag(text: String(format: "%gx", model.rate), color: Theme.violet) }
            }
        }
        .id("header")
    }

    private var navigation: some View {
        HStack(spacing: 10) {
            Button {
                Haptics.tap()
                model.playPrevious()
            } label: {
                Label("Предыдущая", systemImage: "backward.end.fill")
                    .labelStyle(.iconOnly)
                    .frame(width: 26)
            }
            .buttonStyle(GlassButtonStyle(circle: true))
            .disabled(!model.hasPrevious)
            .opacity(model.hasPrevious ? 1 : 0.4)
            .accessibilityLabel("Предыдущая серия")

            if let next = model.nextEpisode {
                Button {
                    Haptics.tap()
                    model.playNext()
                } label: {
                    HStack {
                        Image(systemName: "forward.end.fill")
                        Text("Следующая: \(next.numberText) серия").lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
            } else {
                Text("Это последняя доступная серия")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .card(radius: 16)
            }
        }
    }

    private var players: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Плеер").font(.caption.weight(.semibold)).foregroundStyle(Theme.tertiaryText)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.alternatives) { copy in
                        Button {
                            Haptics.selection()
                            model.switchPlayer(to: copy)
                        } label: {
                            Chip(title: copy.player ?? "Плеер", systemImage: "play.rectangle", isSelected: copy.id == model.episode.id)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
            }
            Text("Если видео не грузится или тормозит, попробуйте другой плеер — серия продолжится с того же места.")
                .font(.caption2)
                .foregroundStyle(Theme.tertiaryText)
        }
    }

    private func episodes(_ reader: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Серии · \(model.episodes.count)").font(.headline).foregroundStyle(.white)
            LazyVStack(spacing: 8) {
                ForEach(Array(model.episodes.enumerated()), id: \.offset) { index, episode in
                    Button {
                        Haptics.tap()
                        model.play(episodeAt: index)
                    } label: {
                        PlayerEpisodeRow(episode: episode, isCurrent: index == model.index,
                                         progress: progress[LibraryData.episodeKey(episode.number)])
                    }
                    .buttonStyle(PressableStyle(scale: 0.98))
                    .id(index)
                }
            }
        }
    }
}

private struct PlayerEpisodeRow: View {
    let episode: SourceEpisode
    let isCurrent: Bool
    let progress: EpisodeProgress?

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isCurrent ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.surfaceStrong))
                if isCurrent {
                    Image(systemName: "waveform").font(.headline.weight(.bold))
                } else {
                    Text(episode.numberText).font(.headline.monospacedDigit())
                }
            }
            .foregroundStyle(.white)
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 4) {
                Text(episode.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if isCurrent {
                    Text("Сейчас играет").font(.caption).foregroundStyle(Theme.pink)
                } else if let progress, progress.position > 0, !progress.isWatched {
                    ProgressView(value: progress.fraction).tint(Theme.pink)
                } else if let player = episode.player {
                    Text(player).font(.caption).foregroundStyle(Theme.tertiaryText)
                }
            }
            Spacer(minLength: 0)
            if progress?.isWatched == true {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
        }
        .padding(8)
        .background(isCurrent ? Theme.surfaceStrong : Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(isCurrent ? Theme.pink.opacity(0.5) : Theme.stroke))
        .opacity(progress?.isWatched == true && !isCurrent ? 0.7 : 1)
    }
}

private struct NextEpisodeCard: View {
    let next: SourceEpisode
    let countdown: Int?
    let onPlay: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ДАЛЕЕ").font(.caption2.weight(.heavy)).foregroundStyle(Theme.pink)
            Text(next.displayTitle).font(.headline).foregroundStyle(.white).lineLimit(2)
            HStack(spacing: 10) {
                Button(action: onPlay) {
                    Label(countdown.map { "Смотреть через \($0)" } ?? "Смотреть", systemImage: "play.fill")
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                }
                .buttonStyle(PrimaryButtonStyle())
                if countdown != nil {
                    Button("Отмена", action: onCancel).buttonStyle(GlassButtonStyle())
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// Episode list sheet used in fullscreen.
private struct EpisodesSheet: View {
    @ObservedObject var model: PlayerViewModel
    let progress: [String: EpisodeProgress]
    let onSelect: (Int) -> Void

    var body: some View {
        NavigationStack {
            ScrollViewReader { reader in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(Array(model.episodes.enumerated()), id: \.offset) { index, episode in
                            Button {
                                onSelect(index)
                            } label: {
                                PlayerEpisodeRow(episode: episode, isCurrent: index == model.index,
                                                 progress: progress[LibraryData.episodeKey(episode.number)])
                            }
                            .buttonStyle(PressableStyle(scale: 0.98))
                            .id(index)
                        }
                    }
                    .padding()
                }
                .onAppear { reader.scrollTo(model.index, anchor: .center) }
            }
            .screenBackground()
            .navigationTitle("Серии · \(model.episode.voice)")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
    }
}
