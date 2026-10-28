import SwiftUI

struct AnimeDetailView: View {
    let route: AnimeRoute
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        AnimeDetailContent(model: AnimeDetailViewModel(
            route: route,
            preferredSource: library.preferredSource(animeID: route.id),
            preferredVoice: library.preferredVoice(animeID: route.id)
        ))
    }
}

private struct AnimeDetailContent: View {
    @StateObject private var model: AnimeDetailViewModel
    @EnvironmentObject private var library: LibraryStore
    @State private var player: PlayerContext?
    @State private var descriptionExpanded = false

    init(model: @autoclosure @escaping () -> AnimeDetailViewModel) {
        _model = StateObject(wrappedValue: model())
    }

    var body: some View {
        LoadableView(state: model.anime, retry: { Task { await model.load() } }) { anime in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header(anime)
                    actions(anime)
                    if !anime.genres.isEmpty { genres(anime) }
                    if let description = anime.description { descriptionBlock(description) }
                    episodesSection(anime)
                    if !anime.related.isEmpty { related(anime) }
                    AnimeShelf(title: "Похожие", state: model.similar, emptyText: "Похожих тайтлов не нашлось") {
                        Task { await model.loadSimilar() }
                    }
                    .padding(.horizontal, -16)
                }
                .padding()
            }
            .refreshable { await model.reloadAll() }
            .navigationTitle(anime.title)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let anime = model.anime.value {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        library.toggleFavorite(SavedAnime(anime: anime))
                    } label: {
                        Image(systemName: library.isFavorite(anime.id) ? "heart.fill" : "heart")
                    }
                    .accessibilityLabel(library.isFavorite(anime.id) ? "Убрать из избранного" : "В избранное")
                }
            }
        }
        .task { await model.load() }
        .onChange(of: model.voice) { voice in
            if let voice, let source = model.sourceID {
                library.rememberChoice(animeID: model.animeID, source: source, voice: voice)
            }
        }
        .fullScreenCover(item: $player) { context in
            PlayerScreen(context: context, library: library)
        }
    }

    // MARK: Header

    private func header(_ anime: Anime) -> some View {
        HStack(alignment: .top, spacing: 16) {
            PosterImage(url: anime.posterURL ?? anime.posterPreviewURL)
                .frame(width: 140)
            VStack(alignment: .leading, spacing: 6) {
                Text(anime.title).font(.title2.weight(.bold))
                if anime.title != anime.name {
                    Text(anime.name).font(.subheadline).foregroundStyle(.secondary)
                }
                if let score = anime.score {
                    Label(String(format: "%.2f", score), systemImage: "star.fill")
                        .font(.headline)
                        .foregroundStyle(.yellow)
                }
                info("Тип", anime.kind?.title)
                info("Статус", anime.status?.title)
                info("Эпизоды", anime.episodesText)
                info("Длительность", anime.duration.flatMap { $0 > 0 ? "\($0) мин." : nil })
                info("Год", anime.year.map(String.init))
                info("Студия", anime.studios.isEmpty ? nil : anime.studios.joined(separator: ", "))
                if let next = anime.nextEpisodeAt, anime.status == .ongoing {
                    info("Следующая серия", next.formatted(date: .abbreviated, time: .shortened))
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func info(_ title: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.caption2).foregroundStyle(.secondary)
                Text(value).font(.footnote)
            }
        }
    }

    // MARK: Actions

    private func actions(_ anime: Anime) -> some View {
        HStack(spacing: 12) {
            if let resume = resumePoint {
                Button {
                    play(index: resume.index, anime: anime)
                } label: {
                    Label(resume.label, systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            Button {
                library.toggleFavorite(SavedAnime(anime: anime))
            } label: {
                Label(library.isFavorite(anime.id) ? "В избранном" : "В избранное",
                      systemImage: library.isFavorite(anime.id) ? "heart.fill" : "heart")
                    .frame(maxWidth: resumePoint == nil ? .infinity : nil)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    /// Continue the last watched episode, or start the next one / the first one.
    private var resumePoint: (index: Int, label: String)? {
        let list = model.episodes
        guard !list.isEmpty else { return nil }
        if let record = library.record(for: model.animeID),
           let index = list.firstIndex(where: { $0.number == record.episodeNumber }) {
            if record.progress.isWatched {
                if index + 1 < list.count {
                    return (index + 1, "Смотреть \(list[index + 1].numberText) серию")
                }
                return (index, "Пересмотреть \(list[index].numberText) серию")
            }
            return (index, "Продолжить \(list[index].numberText) серию")
        }
        return (0, list.count == 1 ? "Смотреть" : "Смотреть с 1 серии")
    }

    private func play(index: Int, anime: Anime) {
        guard let source = model.sourceID, model.episodes.indices.contains(index) else { return }
        player = PlayerContext(anime: SavedAnime(anime: anime), source: source, episodes: model.episodes, startIndex: index)
    }

    // MARK: Genres & description

    private func genres(_ anime: Anime) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(anime.genres) { genre in
                    Text(genre.title)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(.secondarySystemBackground), in: Capsule())
                }
            }
        }
    }

    private func descriptionBlock(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Описание").font(.title3.weight(.bold))
            Text(text)
                .font(.callout)
                .lineLimit(descriptionExpanded ? nil : 5)
            Button(descriptionExpanded ? "Свернуть" : "Подробнее") {
                withAnimation { descriptionExpanded.toggle() }
            }
            .font(.callout.weight(.semibold))
        }
    }

    // MARK: Episodes

    private func episodesSection(_ anime: Anime) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Серии").font(.title3.weight(.bold))
            if model.availableSources.count > 1 {
                Picker("Источник", selection: Binding(get: { model.sourceID ?? .aniLibria }, set: { model.selectSource($0) })) {
                    ForEach(model.availableSources) { source in
                        Text(source.title).tag(source)
                    }
                }
                .pickerStyle(.segmented)
            } else if let source = model.sourceID {
                Text("Источник: \(source.title)").font(.footnote).foregroundStyle(.secondary)
            }

            switch model.episodesState {
            case .idle, .loading:
                LoadingStateView(text: "Ищем серии…")
            case .failed(let error) where error.isNotFound:
                EmptyStateView(
                    title: "Нет в источнике «\(model.sourceID?.title ?? "")»",
                    message: model.availableSources.count > 1 ? "Попробуйте другой источник." : "Этот тайтл пока не озвучен.",
                    systemImage: "film.stack"
                )
            case .failed(let error):
                ErrorStateView(error: error, compact: true) { Task { await model.loadEpisodes(force: true) } }
            case .loaded where model.episodes.isEmpty:
                EmptyStateView(title: "Серий пока нет", message: "Они появятся, когда выйдут.", systemImage: "clock")
            case .loaded:
                voicePicker
                LazyVStack(spacing: 8) {
                    ForEach(Array(model.episodes.enumerated()), id: \.element.id) { index, episode in
                        EpisodeRow(
                            episode: episode,
                            progress: library.progress(animeID: anime.id, episode: episode.number)
                        )
                        .onTapGesture { play(index: index, anime: anime) }
                        .contextMenu {
                            let watched = library.progress(animeID: anime.id, episode: episode.number)?.isWatched == true
                            Button {
                                library.markWatched(!watched, anime: SavedAnime(anime: anime), episode: episode)
                            } label: {
                                Label(watched ? "Отметить непросмотренной" : "Отметить просмотренной",
                                      systemImage: watched ? "eye.slash" : "eye")
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var voicePicker: some View {
        let voices = model.voices
        if voices.count > 1 {
            Menu {
                Picker("Озвучка", selection: Binding(get: { model.voice ?? voices.first ?? "" }, set: { model.voice = $0 })) {
                    ForEach(voices, id: \.self) { voice in
                        Text(voice).tag(voice)
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "waveform")
                    Text(model.voice ?? voices.first ?? "Озвучка").lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").font(.caption)
                }
                .padding(12)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
            }
        } else if let voice = voices.first {
            Label(voice, systemImage: "waveform").font(.footnote).foregroundStyle(.secondary)
        }
    }

    // MARK: Related

    private func related(_ anime: Anime) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Связанное").font(.title3.weight(.bold))
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(anime.related, id: \.anime.id) { item in
                        NavigationLink(value: AnimeRoute(id: item.anime.id, preview: item.anime)) {
                            VStack(alignment: .leading, spacing: 4) {
                                AnimeCard(anime: item.anime, width: 110)
                                Text(item.relation).font(.caption2).foregroundStyle(Color.accentColor)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct EpisodeRow: View {
    let episode: SourceEpisode
    let progress: EpisodeProgress?

    var body: some View {
        HStack(spacing: 12) {
            if episode.previewURL != nil {
                ThumbnailImage(url: episode.previewURL).frame(width: 96)
            } else {
                Text(episode.numberText)
                    .font(.headline.monospacedDigit())
                    .frame(width: 44, height: 44)
                    .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(episode.displayTitle).font(.subheadline.weight(.medium)).lineLimit(2)
                if let duration = episode.duration {
                    Text("\(Int(duration / 60)) мин.").font(.caption).foregroundStyle(.secondary)
                }
                if let progress, !progress.isWatched, progress.position > 0 {
                    ProgressView(value: progress.fraction).tint(.accentColor)
                }
            }
            Spacer(minLength: 0)
            if progress?.isWatched == true {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Image(systemName: "play.circle").foregroundStyle(Color.accentColor)
            }
        }
        .padding(10)
        .background(Color(.secondarySystemBackground).opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
    }
}
