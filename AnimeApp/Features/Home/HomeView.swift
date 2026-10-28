import SwiftUI

struct HomeView: View {
    @StateObject private var model = HomeViewModel()
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        ZoomNavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    hero
                    if !library.continueWatching.isEmpty {
                        ContinueWatchingShelf(records: library.continueWatching)
                    }
                    AnimeShelf(title: "Онгоинги", subtitle: "Выходят прямо сейчас", state: model.ongoing,
                               seeAll: CatalogRoute(title: "Онгоинги", query: HomeViewModel.ongoingQuery)) {
                        Task { await model.loadOngoing() }
                    }
                    AnimeShelf(title: "Новые серии", subtitle: "Свежие эпизоды с озвучкой", state: model.updated,
                               emptyText: "Свежих серий пока нет") {
                        Task { await model.loadUpdated() }
                    }
                    AnimeShelf(title: "Популярное", state: model.popular,
                               seeAll: CatalogRoute(title: "Популярное", query: HomeViewModel.popularQuery)) {
                        Task { await model.loadPopular() }
                    }
                    AnimeShelf(title: "Лучшее за всё время", subtitle: "По оценкам Shikimori", state: model.top,
                               seeAll: CatalogRoute(title: "Лучшее", query: HomeViewModel.topQuery)) {
                        Task { await model.loadTop() }
                    }
                }
                .padding(.bottom, 24)
            }
            .ignoresSafeArea(edges: .top)
            .screenBackground()
            .refreshable { await model.reload() }
            .task { await model.loadIfNeeded() }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    @ViewBuilder
    private var hero: some View {
        Group {
            switch model.ongoing {
            case .loaded where !model.featured.isEmpty:
                HeroCarousel(items: model.featured).transition(.opacity)
            case .failed:
                Color.clear.frame(height: 100)
            default:
                SkeletonBlock(radius: 0).frame(height: 540).shimmering().transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.5), value: model.ongoing.phaseKey)
    }
}

/// Full-width auto-advancing banner of featured titles.
private struct HeroCarousel: View {
    let items: [Anime]
    @State private var selection = 0
    @EnvironmentObject private var library: LibraryStore
    private let timer = Timer.publish(every: 7, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selection) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, anime in
                    slide(anime).tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            HStack(spacing: 6) {
                ForEach(items.indices, id: \.self) { index in
                    Capsule()
                        .fill(index == selection ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Color.white.opacity(0.3)))
                        .frame(width: index == selection ? 22 : 7, height: 7)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selection)
            .padding(.bottom, 4)
        }
        .frame(height: 540)
        .onReceive(timer) { _ in
            withAnimation(.easeInOut(duration: 0.6)) { selection = (selection + 1) % max(1, items.count) }
        }
    }

    private func slide(_ anime: Anime) -> some View {
        ZStack(alignment: .bottomLeading) {
            // Parallax: the picture moves slower than the page while swiping.
            GeometryReader { proxy in
                BackdropImage(url: anime.posterURL ?? anime.posterPreviewURL)
                    .frame(width: proxy.size.width * 1.3, height: proxy.size.height)
                    .offset(x: -proxy.size.width * 0.15 - proxy.frame(in: .global).minX * 0.3)
            }
            .overlay(Theme.heroFade)
            .overlay(LinearGradient(colors: [.black.opacity(0.45), .clear], startPoint: .top, endPoint: .center))
            .zoomSource("hero-\(anime.id)")

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Tag(text: "ОНГОИНГ", color: Theme.pink, filled: true)
                    if let score = anime.score {
                        Tag(text: String(format: "★ %.1f", score), color: Theme.scoreColor(score))
                    }
                    if let kind = anime.kind { Tag(text: kind.title) }
                }
                Text(anime.title)
                    .font(.system(size: 30, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .shadow(color: .black.opacity(0.5), radius: 8)
                if !anime.genres.isEmpty {
                    Text(anime.genres.prefix(3).map(\.title).joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
                HStack(spacing: 10) {
                    NavigationLink(value: AnimeRoute(id: anime.id, preview: anime, zoomID: "hero-\(anime.id)")) {
                        Label("Смотреть", systemImage: "play.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    Button {
                        Haptics.success()
                        library.toggleFavorite(SavedAnime(anime: anime))
                    } label: {
                        Image(systemName: library.isFavorite(anime.id) ? "heart.fill" : "heart")
                            .foregroundStyle(library.isFavorite(anime.id) ? Theme.pink : .white)
                            .id(library.isFavorite(anime.id))
                            .transition(.scale(scale: 0.4).combined(with: .opacity))
                            .animation(.spring(response: 0.35, dampingFraction: 0.5), value: library.isFavorite(anime.id))
                    }
                    .buttonStyle(GlassButtonStyle(circle: true))
                    .accessibilityLabel(library.isFavorite(anime.id) ? "Убрать из избранного" : "В избранное")
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 34)
        }
        .clipped()
    }
}

struct ContinueWatchingShelf: View {
    let records: [WatchRecord]
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Продолжить просмотр")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                        NavigationLink(value: AnimeRoute(id: record.anime.id, zoomID: "continue-\(record.anime.id)")) {
                            ContinueCard(record: record)
                                .zoomSource("continue-\(record.anime.id)")
                        }
                        .buttonStyle(PressableStyle())
                        .appear(index)
                        .contextMenu {
                            Button(role: .destructive) {
                                library.removeFromHistory(record.anime.id)
                            } label: {
                                Label("Убрать из истории", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

/// Wide card: blurred backdrop, poster, episode and progress.
private struct ContinueCard: View {
    let record: WatchRecord

    var body: some View {
        HStack(spacing: 12) {
            PosterImage(url: record.anime.posterURL, cornerRadius: 10).frame(width: 64)
            VStack(alignment: .leading, spacing: 6) {
                Text(record.anime.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(record.progress.isWatched ? "Просмотрена · \(record.episodeTitle)" : record.episodeTitle)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    ProgressView(value: record.progress.fraction).tint(Theme.pink)
                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Theme.accentGradient)
                }
            }
            .padding(.vertical, 4)
        }
        .padding(10)
        .frame(width: 290, height: 116)
        .background {
            BackdropImage(url: record.anime.posterURL, blur: 24)
                .overlay(Theme.background.opacity(0.72))
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.stroke))
    }
}
