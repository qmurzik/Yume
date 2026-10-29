import SwiftUI

struct AnimeDetailView: View {
    let route: AnimeRoute
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        AnimeDetailContent(model: AnimeDetailViewModel(
            route: route,
            preferredSource: library.preferredSource(animeID: route.id),
            preferredVoice: library.preferredVoice(animeID: route.id),
            preferredPlayer: library.preferredPlayer(animeID: route.id)
        ))
    }
}

private struct AnimeDetailContent: View {
    @StateObject private var model: AnimeDetailViewModel
    @EnvironmentObject private var library: LibraryStore
    @State private var player: PlayerContext?
    @State private var descriptionExpanded = false
    @State private var rangeIndex = 0
    @State private var showSettings = false

    private static let headerHeight: CGFloat = 420
    private static let rangeSize = 50

    init(model: @autoclosure @escaping () -> AnimeDetailViewModel) {
        _model = StateObject(wrappedValue: model())
    }

    var body: some View {
        Group {
            switch model.anime {
            case .idle, .loading:
                skeleton
            case .failed(let error):
                ErrorStateView(error: error) { Task { await model.load() } }
                    .frame(maxHeight: .infinity)
            case .loaded(let anime):
                content(anime)
            }
        }
        .screenBackground()
        .animation(Motion.fade, value: model.anime.phaseKey)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            if let anime = model.anime.value {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 8) {
                        ShareLink(item: AppConfig.shikimoriBaseURL.appendingPathComponent("animes/\(anime.id)")) {
                            toolbarIcon("square.and.arrow.up")
                        }
                        Button {
                            Haptics.success()
                            library.toggleFavorite(SavedAnime(anime: anime))
                        } label: {
                            toolbarIcon(library.isFavorite(anime.id) ? "heart.fill" : "heart", tint: library.isFavorite(anime.id) ? Theme.accent : .white)
                        }
                        .accessibilityLabel(library.isFavorite(anime.id) ? "Убрать из избранного" : "В избранное")
                    }
                }
            }
        }
        .task { await model.load() }
        .onChange(of: model.voice) { voice in
            rangeIndex = defaultRange
            if let voice, let source = model.sourceID {
                library.rememberChoice(animeID: model.animeID, source: source, voice: voice)
            }
        }
        .onChange(of: model.episodes.count) { _ in rangeIndex = defaultRange }
        .onChange(of: model.player) { player in
            library.rememberPlayer(animeID: model.animeID, player: player)
        }
        .fullScreenCover(item: $player) { context in
            PlayerScreen(context: context, library: library)
        }
        .sheet(isPresented: $showSettings, onDismiss: { model.refreshSources() }) {
            SettingsView()
        }
        .onReceive(NotificationCenter.default.publisher(for: YummyCredentials.didChange)) { _ in
            model.refreshSources()
        }
    }

    private func toolbarIcon(_ name: String, tint: Color = .white) -> some View {
        Image(systemName: name)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(tint)
            .frame(width: 34, height: 34)
            .background(.ultraThinMaterial, in: Circle())
    }

    private var skeleton: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SkeletonBlock(radius: 0).frame(height: Self.headerHeight)
                SkeletonBlock().frame(height: 50).padding(.horizontal)
                SkeletonBlock().frame(height: 120).padding(.horizontal)
                ForEach(0..<4, id: \.self) { _ in SkeletonBlock().frame(height: 72).padding(.horizontal) }
            }
            .shimmering()
        }
        .ignoresSafeArea(edges: .top)
        .disabled(true)
    }

    private func content(_ anime: Anime) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header(anime)
                VStack(alignment: .leading, spacing: 26) {
                    actions(anime)
                    if !anime.genres.isEmpty { genres(anime) }
                    if let description = anime.description { descriptionBlock(description) }
                    facts(anime)
                    watchSection(anime)
                }
                .padding(.horizontal)
                if !anime.related.isEmpty { related(anime) }
                AnimeShelf(title: "Похожие", kicker: "おすすめ", state: model.similar, emptyText: "Похожих тайтлов не нашлось") {
                    Task { await model.loadSimilar() }
                }
            }
            .padding(.bottom, 30)
        }
        .ignoresSafeArea(edges: .top)
        .refreshable { await model.reloadAll() }
    }

    // MARK: Header

    private func header(_ anime: Anime) -> some View {
        GeometryReader { proxy in
            let pull = max(0, proxy.frame(in: .global).minY)
            ZStack(alignment: .bottomLeading) {
                BackdropImage(url: anime.posterURL ?? anime.posterPreviewURL, blur: 22)
                    .overlay(Theme.background.opacity(0.25))
                    .overlay(Theme.heroFade)
                    .overlay(GrainOverlay(opacity: 0.12))
                    .frame(width: proxy.size.width, height: Self.headerHeight + pull)
                    .offset(y: -pull)

                HStack(alignment: .bottom, spacing: 16) {
                    PosterImage(url: anime.posterURL ?? anime.posterPreviewURL)
                        .frame(width: 132)
                        .shadow(color: .black.opacity(0.6), radius: 18, y: 10)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(anime.title)
                            .font(.display(22, .black, relativeTo: .title))
                            .appear(1)
                            .foregroundStyle(Theme.cream)
                            .lineLimit(4)
                            .minimumScaleFactor(0.8)
                        if anime.title != anime.name {
                            Text(anime.name).font(.subheadline).foregroundStyle(Theme.secondaryText).lineLimit(2)
                        }
                        HStack(spacing: 6) {
                            if let score = anime.score { ScoreSeal(score: score, large: true) }
                            if let status = anime.status {
                                Tag(text: status.title, color: status == .ongoing ? Theme.accent : .white)
                            }
                        }
                        if anime.status == .ongoing, let next = anime.nextEpisodeAt, next > Date() {
                            Label("Новая серия \(next.formatted(.relative(presentation: .named)))", systemImage: "bell.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal)
                .padding(.bottom, 4)
            }
        }
        .frame(height: Self.headerHeight)
    }

    // MARK: Actions

    private func actions(_ anime: Anime) -> some View {
        VStack(spacing: 10) {
            if let resume = resumePoint {
                Button {
                    Haptics.tap()
                    play(index: resume.index, anime: anime)
                } label: {
                    HStack {
                        Image(systemName: "play.fill")
                        VStack(alignment: .leading, spacing: 1) {
                            Text(resume.label)
                            if let detail = resume.detail {
                                Text(detail).font(.caption.weight(.medium)).opacity(0.85)
                            }
                        }
                        Spacer()
                        if let fraction = resume.fraction {
                            ZStack {
                                Circle().stroke(Color.white.opacity(0.3), lineWidth: 3)
                                Circle().trim(from: 0, to: CGFloat(fraction)).stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                            }
                            .frame(width: 26, height: 26)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(PrimaryButtonStyle())
            } else if model.episodesState.isLoading || model.episodesState.isIdle {
                SkeletonBlock(radius: 16).frame(height: 56).shimmering()
            }
        }
    }

    private struct ResumePoint {
        let index: Int
        let label: String
        var detail: String?
        var fraction: Double?
    }

    /// Continue the last watched episode, or start the next one / the first one.
    private var resumePoint: ResumePoint? {
        let list = model.episodes
        guard !list.isEmpty else { return nil }
        if let record = library.record(for: model.animeID),
           let index = list.firstIndex(where: { $0.number == record.episodeNumber }) {
            if record.progress.isWatched {
                if index + 1 < list.count {
                    return ResumePoint(index: index + 1, label: "Смотреть \(list[index + 1].numberText) серию", detail: "Следующая после просмотренной")
                }
                return ResumePoint(index: index, label: "Пересмотреть \(list[index].numberText) серию", detail: "Это последняя доступная")
            }
            let left = record.duration.map { max(0, $0 - record.position) }
            return ResumePoint(
                index: index,
                label: "Продолжить \(list[index].numberText) серию",
                detail: left.map { "Осталось \(Int(($0 / 60).rounded(.up))) мин." },
                fraction: record.progress.fraction
            )
        }
        return ResumePoint(index: 0, label: list.count == 1 ? "Смотреть" : "Смотреть с 1 серии",
                           detail: "\(list.count) \(Self.episodesWord(list.count)) · \(list[0].voice)")
    }

    static func episodesWord(_ count: Int) -> String {
        let mod10 = count % 10, mod100 = count % 100
        if mod10 == 1 && mod100 != 11 { return "серия" }
        if (2...4).contains(mod10) && !(12...14).contains(mod100) { return "серии" }
        return "серий"
    }

    private func play(index: Int, anime: Anime) {
        guard let source = model.sourceID, model.episodes.indices.contains(index) else { return }
        player = PlayerContext(anime: SavedAnime(anime: anime), source: source, episodes: model.episodes,
                               startIndex: index, alternatives: model.alternatives, webURL: model.currentWebURL)
    }

    // MARK: Info

    private func genres(_ anime: Anime) -> some View {
        Flow(spacing: 8) {
            ForEach(anime.genres) { genre in
                NavigationLink(value: CatalogRoute(title: genre.title, query: CatalogQuery(genreIDs: [genre.id]))) {
                    Chip(title: genre.title)
                }
                .buttonStyle(PressableStyle())
            }
        }
    }

    private func descriptionBlock(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("О тайтле").font(.display(18, .bold, relativeTo: .title3))
            Text(text)
                .font(.callout)
                .foregroundStyle(Color.white.opacity(0.85))
                .lineSpacing(3)
                .lineLimit(descriptionExpanded ? nil : 5)
            Button {
                withAnimation(.easeInOut) { descriptionExpanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Text(descriptionExpanded ? "Свернуть" : "Читать полностью")
                    Image(systemName: descriptionExpanded ? "chevron.up" : "chevron.down").font(.caption.weight(.bold))
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
            }
        }
    }

    private struct Fact: Identifiable {
        let title: String
        let value: String
        var id: String { title }
    }

    private func facts(_ anime: Anime) -> some View {
        let candidates: [(String, String?)] = [
            ("Тип", anime.kind?.title),
            ("Эпизоды", anime.episodesText),
            ("Длительность", anime.duration.flatMap { $0 > 0 ? "\($0) мин." : nil }),
            ("Год", anime.year.map(String.init)),
            ("Студия", anime.studios.isEmpty ? nil : anime.studios.joined(separator: ", ")),
            ("Следующая серия", anime.status == .ongoing ? anime.nextEpisodeAt?.formatted(date: .abbreviated, time: .shortened) : nil),
        ]
        let items = candidates.compactMap { title, value in value.map { Fact(title: title, value: $0) } }

        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title).font(.caption).foregroundStyle(Theme.tertiaryText)
                    Text(item.value).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.cream).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .card(radius: 12)
            }
        }
    }

    // MARK: Watching

    private func watchSection(_ anime: Anime) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Смотреть").font(.display(18, .bold, relativeTo: .title3))
                Spacer()
                if !model.episodes.isEmpty {
                    Text("\(model.episodes.count) \(Self.episodesWord(model.episodes.count))")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            sourceChips
            sourceNotes

            switch model.episodesState {
            case .idle, .loading:
                VStack(spacing: 10) {
                    ForEach(0..<4, id: \.self) { _ in SkeletonBlock(radius: 14).frame(height: 74) }
                }
                .shimmering()
            case .failed(let error) where error.isNotFound:
                EmptyStateView(
                    title: "Нет в источнике «\(model.sourceID?.title ?? "")»",
                    message: notFoundMessage,
                    systemImage: "film.stack"
                )
            case .failed(let error):
                ErrorStateView(error: error, compact: true) { Task { await model.loadEpisodes(force: true) } }
            case .loaded where model.episodes.isEmpty:
                EmptyStateView(title: "Серий пока нет", message: "Они появятся, когда выйдут.", systemImage: "clock")
            case .loaded:
                voiceChips
                playerChips
                rangeChips
                episodeList(anime)
                    .id("\(model.sourceID?.rawValue ?? "")-\(model.voice ?? "")-\(model.player ?? "")-\(rangeIndex)")
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(Motion.spring, value: model.episodesState.phaseKey)
        .animation(Motion.spring, value: model.voice)
        .animation(Motion.spring, value: model.player)
        .animation(Motion.spring, value: rangeIndex)
        .animation(Motion.snappy, value: model.sourceID)
    }

    private var sourceChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.availableSources) { source in
                    Button {
                        Haptics.selection()
                        model.selectSource(source)
                    } label: {
                        Chip(title: source.title,
                             systemImage: model.missingIn.contains(source) ? "xmark.circle" : "play.tv",
                             isSelected: model.sourceID == source,
                             isDisabled: model.missingIn.contains(source) && model.sourceID != source)
                    }
                    .buttonStyle(PressableStyle())
                }
                ForEach(model.disabledSources) { source in
                    Button {
                        Haptics.tap()
                        showSettings = true
                    } label: {
                        Chip(title: "\(source.title) · войти", systemImage: "key.fill", isDisabled: true)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
    }

    @ViewBuilder
    private var sourceNotes: some View {
        if !model.disabledSources.isEmpty {
            Button {
                showSettings = true
            } label: {
                Label("Войдите в \(model.disabledSources.map(\.title).joined(separator: ", ")), чтобы открыть больше озвучек и субтитров",
                      systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.leading)
            }
        }
    }

    private var notFoundMessage: String {
        let all = model.availableSources
        guard all.count > 1 else { return "Этот тайтл пока не озвучен." }
        guard Set(model.missingIn) == Set(all) else { return "Попробуйте другой источник." }
        let names = all.map(\.title).joined(separator: ", ")
        return "Мы проверили все источники: \(names). Возможно, тайтл удалён по требованию правообладателя или ещё не озвучен."
    }

    @ViewBuilder
    private var voiceChips: some View {
        let voices = model.voices
        if voices.count > 1 {
            VStack(alignment: .leading, spacing: 8) {
                Text("Озвучка и субтитры").font(.caption.weight(.semibold)).foregroundStyle(Theme.tertiaryText)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(voices, id: \.self) { voice in
                            Button {
                                Haptics.selection()
                                model.voice = voice
                            } label: {
                                Chip(title: "\(voice) · \(model.voiceCounts[voice] ?? 0) эп.",
                                     systemImage: voice.localizedCaseInsensitiveContains("субтитр") ? "captions.bubble" : "waveform",
                                     isSelected: (model.voice ?? voices.first) == voice)
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                }
            }
        } else if let voice = voices.first {
            Label(voice, systemImage: "waveform").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondaryText)
        }
    }

    /// YummyAnime: one voice-over is often hosted by several players; "Авто" takes the most complete
    /// and fills its gaps from the others.
    @ViewBuilder
    private var playerChips: some View {
        let players = model.players
        if players.count > 1 {
            VStack(alignment: .leading, spacing: 8) {
                Text("Плеер").font(.caption.weight(.semibold)).foregroundStyle(Theme.tertiaryText)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Button {
                            Haptics.selection()
                            model.player = nil
                        } label: {
                            Chip(title: "Авто", systemImage: "wand.and.stars", isSelected: model.player == nil)
                        }
                        .buttonStyle(PressableStyle())
                        ForEach(players, id: \.self) { name in
                            Button {
                                Haptics.selection()
                                model.player = name
                            } label: {
                                Chip(title: name, systemImage: "play.rectangle", isSelected: model.player == name)
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                }
            }
        }
    }

    private var ranges: [Range<Int>] {
        let count = model.episodes.count
        guard count > Self.rangeSize + 10 else { return [0..<count] }
        return stride(from: 0, to: count, by: Self.rangeSize).map { $0..<min(count, $0 + Self.rangeSize) }
    }

    /// The range holding the episode to resume, so long series open where the user is.
    private var defaultRange: Int {
        guard let index = resumePoint?.index else { return 0 }
        return ranges.firstIndex { $0.contains(index) } ?? 0
    }

    @ViewBuilder
    private var rangeChips: some View {
        if ranges.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(ranges.enumerated()), id: \.offset) { offset, range in
                        Button {
                            Haptics.selection()
                            rangeIndex = offset
                        } label: {
                            Chip(title: "\(model.episodes[range.lowerBound].numberText)–\(model.episodes[range.upperBound - 1].numberText)",
                                 isSelected: rangeIndex == offset)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
            }
        }
    }

    private func episodeList(_ anime: Anime) -> some View {
        let range = ranges.indices.contains(rangeIndex) ? ranges[rangeIndex] : (ranges.first ?? 0..<0)
        let current = library.record(for: anime.id)
        return LazyVStack(spacing: 10) {
            ForEach(Array(range), id: \.self) { index in
                let episode = model.episodes[index]
                let position = index - range.lowerBound
                let progress = library.progress(animeID: anime.id, episode: episode.number)
                Button {
                    Haptics.tap()
                    play(index: index, anime: anime)
                } label: {
                    EpisodeRow(episode: episode, progress: progress,
                               isCurrent: current?.episodeNumber == episode.number && current?.voice == episode.voice)
                }
                .buttonStyle(PressableStyle(scale: 0.98))
                .appear(position)
                .contextMenu {
                    let watched = progress?.isWatched == true
                    Button {
                        library.markWatched(!watched, anime: SavedAnime(anime: anime), episode: episode)
                    } label: {
                        Label(watched ? "Отметить непросмотренной" : "Отметить просмотренной",
                              systemImage: watched ? "eye.slash" : "eye")
                    }
                    if index > 0 {
                        Button {
                            Haptics.success()
                            for previous in model.episodes[...index] {
                                library.markWatched(true, anime: SavedAnime(anime: anime), episode: previous)
                            }
                        } label: {
                            Label("Отметить просмотренными 1–\(episode.numberText)", systemImage: "checkmark.circle")
                        }
                    }
                    if let player = episode.player {
                        Text("Плеер: \(player)")
                    }
                }
            }
        }
    }

    // MARK: Related

    private func related(_ anime: Anime) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Связанное", subtitle: "Сезоны, фильмы и спешлы", kicker: "関連")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(Array(anime.related.enumerated()), id: \.element.anime.id) { index, item in
                        NavigationLink(value: AnimeRoute(id: item.anime.id, preview: item.anime, zoomID: "related-\(item.anime.id)")) {
                            VStack(alignment: .leading, spacing: 6) {
                                AnimeCard(anime: item.anime, width: 118, zoomID: "related-\(item.anime.id)")
                                Text(item.relation)
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                        .buttonStyle(PressableStyle())
                        .appear(index)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

private struct EpisodeRow: View {
    let episode: SourceEpisode
    let progress: EpisodeProgress?
    var isCurrent = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomLeading) {
                if episode.previewURL != nil {
                    ThumbnailImage(url: episode.previewURL)
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LinearGradient(colors: [Theme.gold.opacity(0.35), Theme.accent.opacity(0.25)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .overlay {
                            Text(episode.numberText)
                                .font(.system(size: 22, weight: .heavy).monospacedDigit())
                                .foregroundStyle(Theme.cream)
                        }
                }
                if let progress, progress.position > 0, !progress.isWatched {
                    GeometryReader { proxy in
                        Capsule().fill(Theme.accentFill)
                            .frame(width: proxy.size.width * CGFloat(progress.fraction), height: 3)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                    .padding(4)
                }
            }
            .frame(width: 112)
            .overlay {
                Image(systemName: "play.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.cream)
                    .frame(width: 28, height: 28)
                    .background(Color.black.opacity(0.45), in: Circle())
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(episode.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.cream)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    if let duration = episode.duration {
                        Text("\(Int((duration / 60).rounded())) мин.")
                    }
                    if let player = episode.player {
                        Text(player)
                    }
                    if isCurrent {
                        Text("· Вы остановились здесь").foregroundStyle(Theme.accent)
                    }
                }
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 0)
            if progress?.isWatched == true {
                Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(.green)
            }
        }
        .padding(8)
        .background(isCurrent ? Theme.surfaceStrong : Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(isCurrent ? Theme.accent.opacity(0.5) : Theme.stroke))
        .opacity(progress?.isWatched == true ? 0.7 : 1)
        .contentShape(Rectangle())
    }
}
