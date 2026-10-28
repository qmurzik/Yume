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

    init(context: PlayerContext, library: LibraryStore) {
        _model = StateObject(wrappedValue: PlayerViewModel(context: context, library: library))
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.ignoresSafeArea()
                switch model.phase {
                case .loading:
                    loadingView
                case .failed(let error):
                    failedView(error)
                case .native:
                    nativePlayer
                case .embed(let url):
                    embedPlayer(url)
                }
            }
            .onAppear { isLandscape = proxy.size.width > proxy.size.height }
            .onChange(of: proxy.size) { size in isLandscape = size.width > size.height }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(isLandscape || !controlsVisible)
        .persistentSystemOverlays(.hidden)
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

    // MARK: States

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView().tint(.white).controlSize(.large)
            Text(model.episode.displayTitle).font(.headline).foregroundStyle(.white)
            Text(model.episode.voice).font(.subheadline).foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topLeading) { closeButton.padding() }
    }

    private func failedView(_ error: Error) -> some View {
        ErrorStateView(error: error) { model.retry() }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topLeading) { closeButton.padding() }
    }

    // MARK: Native player

    private var nativePlayer: some View {
        ZStack {
            PlayerLayerView(player: model.player, gravity: fillScreen ? .resizeAspectFill : .resizeAspect) { layer in
                model.attach(layer: layer)
            }
            .ignoresSafeArea()

            gestureLayer

            if isLocked {
                lockedOverlay
            } else if controlsVisible {
                controls.transition(.opacity.combined(with: .scale(scale: 1.03)))
            }

            if let bubble = seekBubble {
                seekBubbleView(bubble)
            }

            if model.canSkipOpening {
                skipOpeningButton
            }

            if let next = model.nextEpisode, model.autoplayCountdown != nil || model.didFinish {
                nextEpisodeCard(next)
            }
        }
        .offset(y: dragOffset)
        .scaleEffect(1 - min(dragOffset, 400) / 2000)
        .animation(.easeInOut(duration: 0.25), value: controlsVisible)
        .animation(Motion.snappy, value: isLocked)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.canSkipOpening)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.autoplayCountdown != nil || model.didFinish)
    }

    /// Single tap toggles the controls, double tap on either half seeks 10 seconds.
    private var gestureLayer: some View {
        HStack(spacing: 0) {
            tapZone(forward: false)
            tapZone(forward: true)
        }
        .ignoresSafeArea()
        // Swipe down to close, like a sheet.
        .simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onChanged { value in
                    guard !isLocked, !isLandscape, value.translation.height > 0,
                          abs(value.translation.height) > abs(value.translation.width) else { return }
                    dragOffset = value.translation.height
                }
                .onEnded { value in
                    if dragOffset > 140 || value.predictedEndTranslation.height > 420 {
                        Haptics.tap()
                        dismiss()
                    } else {
                        withAnimation(Motion.spring) { dragOffset = 0 }
                    }
                }
        )
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
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .foregroundStyle(.white)
            .padding(.bottom, 40)
        }
        .transition(.opacity)
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

    private var controls: some View {
        ZStack {
            VStack(spacing: 0) {
                LinearGradient(colors: [.black.opacity(0.75), .clear], startPoint: .top, endPoint: .bottom).frame(height: 160)
                Spacer()
                LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom).frame(height: 220)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                topBar
                Spacer()
                centerControls
                Spacer()
                bottomBar
            }
            .padding(.horizontal, isLandscape ? 28 : 16)
            .padding(.vertical, 8)
        }
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "chevron.down")
                .font(.headline.weight(.bold))
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial, in: Circle())
        }
        .foregroundStyle(.white)
        .accessibilityLabel("Закрыть плеер")
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            closeButton
            VStack(alignment: .leading, spacing: 2) {
                Text(model.context.anime.title).font(.subheadline.weight(.bold)).lineLimit(1)
                Text("\(model.episode.displayTitle) · \(model.episode.voice)")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            Spacer(minLength: 8)
            iconButton("lock.fill", label: "Заблокировать управление") {
                Haptics.success()
                isLocked = true
                controlsVisible = false
            }
            AirPlayButton().frame(width: 36, height: 36)
            if model.isPictureInPicturePossible {
                iconButton(model.isPictureInPictureActive ? "pip.exit" : "pip.enter", label: "Картинка в картинке") {
                    model.togglePictureInPicture()
                }
            }
            settingsMenu
        }
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
            Toggle(isOn: $fillScreen) {
                Label("Заполнить экран", systemImage: "arrow.up.left.and.arrow.down.right")
            }
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.headline)
                .frame(width: 40, height: 40)
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
                .font(.headline)
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial, in: Circle())
        }
        .foregroundStyle(.white)
        .accessibilityLabel(label)
    }

    private var centerControls: some View {
        HStack(spacing: isLandscape ? 56 : 36) {
            transportButton("backward.end.fill", size: 22, enabled: model.hasPrevious, label: "Предыдущая серия") { model.playPrevious() }
            transportButton("gobackward.10", size: 28, label: "Назад на 10 секунд") { model.skip(by: -10) }
            Button {
                Haptics.tap()
                model.togglePlay()
                scheduleHide()
            } label: {
                ZStack {
                    Circle().fill(.ultraThinMaterial).frame(width: 76, height: 76)
                    if model.isBuffering {
                        ProgressView().tint(.white).controlSize(.large)
                    } else {
                        Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 32, weight: .bold))
                            .offset(x: model.isPlaying ? 0 : 3)
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
            transportButton("goforward.10", size: 28, label: "Вперёд на 10 секунд") { model.skip(by: 10) }
            transportButton("forward.end.fill", size: 22, enabled: model.hasNext, label: "Следующая серия") { model.playNext() }
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
                .frame(width: 52, height: 52)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.85))
        .foregroundStyle(.white.opacity(enabled ? 1 : 0.3))
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private var bottomBar: some View {
        VStack(spacing: 6) {
            HStack {
                Text(TimeFormat.string(model.isScrubbing ? model.scrubTime : model.currentTime))
                Spacer()
                Text("-" + TimeFormat.string(max(0, model.duration - (model.isScrubbing ? model.scrubTime : model.currentTime))))
            }
            .font(.caption.monospacedDigit().weight(.semibold))
            .foregroundStyle(.white.opacity(0.85))

            PlayerScrubber(
                current: model.isScrubbing ? model.scrubTime : model.currentTime,
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

            HStack(spacing: 10) {
                pillButton("Серии", systemImage: "list.bullet") { showEpisodes = true }
                if model.hasNext {
                    pillButton("Следующая", systemImage: "forward.end.fill") { model.playNext() }
                }
                Spacer()
                if model.rate != 1 {
                    Tag(text: String(format: "%gx", model.rate), color: Theme.pink)
                }
                if let quality = model.quality {
                    Tag(text: quality.label, color: .white)
                }
                iconButton(isLandscape ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                           label: isLandscape ? "Выйти из полноэкранного режима" : "Во весь экран") {
                    Orientation.set(landscape: !isLandscape)
                }
            }
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
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(PressableStyle())
        .foregroundStyle(.white)
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
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(.horizontal, isLandscape ? 28 : 16)
        .padding(.bottom, controlsVisible ? 120 : 36)
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    private func nextEpisodeCard(_ next: SourceEpisode) -> some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                VStack(alignment: .leading, spacing: 10) {
                    Text("ДАЛЕЕ").font(.caption2.weight(.heavy)).foregroundStyle(Theme.pink)
                    Text(next.displayTitle).font(.headline).foregroundStyle(.white).lineLimit(2)
                    HStack(spacing: 10) {
                        Button {
                            model.playNext()
                        } label: {
                            Label(model.autoplayCountdown.map { "Смотреть через \($0)" } ?? "Смотреть", systemImage: "play.fill")
                                .font(.subheadline.weight(.bold))
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        if model.autoplayCountdown != nil {
                            Button("Отмена") { model.cancelAutoplay() }
                                .buttonStyle(GlassButtonStyle())
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: 340, alignment: .leading)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
        .padding(.horizontal, isLandscape ? 28 : 16)
        .padding(.bottom, controlsVisible ? 120 : 36)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func seekBubbleView(_ bubble: SeekBubble) -> some View {
        HStack {
            if bubble.forward { Spacer() }
            VStack(spacing: 6) {
                Image(systemName: bubble.forward ? "goforward" : "gobackward").font(.title.weight(.bold))
                Text("\(bubble.seconds) сек").font(.footnote.weight(.bold))
            }
            .foregroundStyle(.white)
            .frame(width: 120, height: 120)
            .background(Color.white.opacity(0.12), in: Circle())
            .id(bubble.seconds)
            .transition(.scale(scale: 0.7).combined(with: .opacity))
            .padding(.horizontal, 40)
            if !bubble.forward { Spacer() }
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    // MARK: Embed player (YummyAnime)

    private func embedPlayer(_ url: URL) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                closeButton
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.context.anime.title).font(.subheadline.weight(.bold)).lineLimit(1)
                    Text("\(model.episode.displayTitle) · \(model.episode.voice)")
                        .font(.caption).foregroundStyle(Theme.secondaryText).lineLimit(1)
                }
                .foregroundStyle(.white)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            EmbedPlayerView(url: url)
                .ignoresSafeArea(edges: isLandscape ? .all : [])

            if !isLandscape {
                HStack(spacing: 10) {
                    pillButton("Серии", systemImage: "list.bullet") { showEpisodes = true }
                    Spacer()
                    if model.hasPrevious {
                        pillButton("Предыдущая", systemImage: "backward.end.fill") { model.playPrevious() }
                    }
                    if model.hasNext {
                        pillButton("Следующая", systemImage: "forward.end.fill") { model.playNext() }
                    }
                }
                .padding()
            }
        }
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

/// Episode list inside the player.
private struct EpisodesSheet: View {
    @ObservedObject var model: PlayerViewModel
    let progress: [String: EpisodeProgress]
    let onSelect: (Int) -> Void

    var body: some View {
        NavigationStack {
            ScrollViewReader { reader in
                List {
                    ForEach(Array(model.context.episodes.enumerated()), id: \.element.id) { index, episode in
                        Button {
                            onSelect(index)
                        } label: {
                            HStack(spacing: 12) {
                                Text(episode.numberText)
                                    .font(.headline.monospacedDigit())
                                    .frame(width: 44, height: 44)
                                    .background(index == model.index ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.surface),
                                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .foregroundStyle(.white)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(episode.displayTitle).font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(2)
                                    if index == model.index {
                                        Text("Сейчас играет").font(.caption).foregroundStyle(Theme.pink)
                                    } else if let item = progress[LibraryData.episodeKey(episode.number)], item.position > 0 {
                                        ProgressView(value: item.fraction).tint(Theme.pink)
                                    }
                                }
                                Spacer()
                                if progress[LibraryData.episodeKey(episode.number)]?.isWatched == true {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                }
                            }
                        }
                        .listRowBackground(Theme.elevated)
                        .id(index)
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Theme.background)
                .onAppear { reader.scrollTo(model.index, anchor: .center) }
            }
            .navigationTitle("Серии · \(model.episode.voice)")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
    }
}
