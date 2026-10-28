import SwiftUI

struct AnimeRoute: Hashable {
    let id: Int
    var preview: Anime?
    /// Identifies the tapped card for the zoom transition; unique within a screen.
    var zoomID: String?
}

/// "See all" from a shelf: a catalog grid with a preset query.
struct CatalogRoute: Hashable {
    let title: String
    let query: CatalogQuery
}

extension View {
    /// Registers the title and list screens for every navigation stack.
    func animeNavigation() -> some View {
        navigationDestination(for: AnimeRoute.self) { route in
            AnimeDetailView(route: route)
                .zoomDestination(route.zoomID)
        }
        .navigationDestination(for: CatalogRoute.self) { route in
            AnimeGridScreen(title: route.title, query: route.query)
        }
    }
}

struct ScoreBadge: View {
    let score: Double

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "star.fill").font(.system(size: 9, weight: .black))
            Text(String(format: "%.1f", score)).font(.caption2.weight(.heavy)).monospacedDigit()
        }
        .foregroundStyle(Theme.scoreColor(score))
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.55), in: Capsule())
        .padding(7)
    }
}

struct AnimeCard: View {
    let anime: Anime
    var width: CGFloat?
    var zoomID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            PosterImage(url: anime.posterPreviewURL ?? anime.posterURL)
                .zoomSource(zoomID)
                .overlay(alignment: .topLeading) {
                    if let score = anime.score { ScoreBadge(score: score) }
                }
                .overlay(alignment: .bottomLeading) {
                    if anime.status == .ongoing {
                        Tag(text: "ОНГОИНГ", color: Theme.pink, filled: true).padding(7)
                    }
                }
                .shadow(color: .black.opacity(0.35), radius: 10, y: 6)
            Text(anime.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
            Text(anime.subtitle)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
        }
        .frame(width: width)
        .contentShape(Rectangle())
    }
}

struct SavedAnimeCard: View {
    let anime: SavedAnime
    var zoomID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            PosterImage(url: anime.posterURL)
                .zoomSource(zoomID)
                .shadow(color: .black.opacity(0.35), radius: 10, y: 6)
            Text(anime.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
            if !anime.subtitle.isEmpty {
                Text(anime.subtitle).font(.caption).foregroundStyle(Theme.secondaryText).lineLimit(1)
            }
        }
        .contentShape(Rectangle())
    }
}

/// Row used by search results.
struct AnimeRow: View {
    let anime: Anime
    var zoomID: String?

    var body: some View {
        HStack(spacing: 14) {
            PosterImage(url: anime.posterPreviewURL ?? anime.posterURL, cornerRadius: 10)
                .frame(width: 66)
                .zoomSource(zoomID)
            VStack(alignment: .leading, spacing: 5) {
                Text(anime.title).font(.headline).foregroundStyle(.white).lineLimit(2)
                if anime.title != anime.name {
                    Text(anime.name).font(.subheadline).foregroundStyle(Theme.secondaryText).lineLimit(1)
                }
                HStack(spacing: 6) {
                    if let score = anime.score {
                        Label(String(format: "%.1f", score), systemImage: "star.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.scoreColor(score))
                    }
                    Text(anime.subtitle).font(.caption).foregroundStyle(Theme.secondaryText).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.tertiaryText)
        }
        .padding(10)
        .card()
        .contentShape(Rectangle())
    }
}

/// Titled horizontal shelf of titles with an optional "see all" link.
struct AnimeShelf: View {
    let title: String
    var subtitle: String?
    let state: Loadable<[Anime]>
    var seeAll: CatalogRoute?
    var emptyText = "Пока ничего нет"
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: title, subtitle: subtitle) {
                if let seeAll {
                    NavigationLink(value: seeAll) {
                        HStack(spacing: 4) {
                            Text("Все")
                            Image(systemName: "chevron.right").font(.caption.weight(.bold))
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.pink)
                    }
                }
            }
            switch state {
            case .idle, .loading:
                SkeletonShelf().transition(.opacity)
            case .failed(let error):
                ErrorStateView(error: error, compact: true, retry: retry).transition(.opacity)
            case .loaded(let items) where items.isEmpty:
                Text(emptyText).font(.footnote).foregroundStyle(Theme.secondaryText).padding(.horizontal)
            case .loaded(let items):
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, anime in
                            let zoomID = "\(title)-\(anime.id)"
                            NavigationLink(value: AnimeRoute(id: anime.id, preview: anime, zoomID: zoomID)) {
                                AnimeCard(anime: anime, width: 132, zoomID: zoomID)
                            }
                            .buttonStyle(PressableStyle())
                            .appear(index)
                        }
                    }
                    .padding(.horizontal)
                }
                .transition(.opacity)
            }
        }
        .animation(Motion.fade, value: state.phaseKey)
    }
}
