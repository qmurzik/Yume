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

struct AnimeCard: View {
    let anime: Anime
    var width: CGFloat?
    var zoomID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            PosterImage(url: anime.posterPreviewURL ?? anime.posterURL)
                .zoomSource(zoomID)
                .overlay(alignment: .topTrailing) {
                    if let score = anime.score { ScoreSeal(score: score).padding(6) }
                }
                .overlay(alignment: .bottomLeading) {
                    if anime.status == .ongoing {
                        Tag(text: "Онгоинг", color: Theme.accent, filled: true).padding(6)
                    }
                }
                .shadow(color: .black.opacity(0.45), radius: 8, y: 5)
            Text(anime.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.cream)
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
                .foregroundStyle(Theme.cream)
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
                Text(anime.title).font(.headline).foregroundStyle(Theme.cream).lineLimit(2)
                if anime.title != anime.name {
                    Text(anime.name).font(.subheadline).foregroundStyle(Theme.secondaryText).lineLimit(1)
                }
                HStack(spacing: 6) {
                    if let score = anime.score { ScoreSeal(score: score) }
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
    var kicker: String?
    let state: Loadable<[Anime]>
    var seeAll: CatalogRoute?
    var emptyText = "Пока ничего нет"
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: title, subtitle: subtitle, kicker: kicker) {
                if let seeAll {
                    NavigationLink(value: seeAll) {
                        HStack(spacing: 4) {
                            Text("ВСЕ").tracking(1)
                            Image(systemName: "arrow.right").font(.caption.weight(.heavy))
                        }
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(Theme.cream)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.stroke))
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

/// Ranked shelf: posters with huge outlined numerals behind them.
struct TopTenShelf: View {
    let title: String
    var kicker: String?
    let state: Loadable<[Anime]>
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: title, kicker: kicker)
            switch state {
            case .idle, .loading:
                SkeletonShelf().transition(.opacity)
            case .failed(let error):
                ErrorStateView(error: error, compact: true, retry: retry)
            case .loaded(let items):
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .bottom, spacing: 4) {
                        ForEach(Array(items.prefix(10).enumerated()), id: \.element.id) { index, anime in
                            let zoomID = "top-\(anime.id)"
                            NavigationLink(value: AnimeRoute(id: anime.id, preview: anime, zoomID: zoomID)) {
                                HStack(alignment: .bottom, spacing: -18) {
                                    OutlinedNumber(value: index + 1)
                                    PosterImage(url: anime.posterPreviewURL ?? anime.posterURL)
                                        .frame(width: 118)
                                        .zoomSource(zoomID)
                                        .shadow(color: .black.opacity(0.6), radius: 10, x: -6, y: 4)
                                }
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

/// Big numeral drawn as an outline (cream strokes around ink fill).
private struct OutlinedNumber: View {
    let value: Int

    var body: some View {
        let text = Text("\(value)").font(.display(118, .black, relativeTo: .largeTitle))
        ZStack {
            ForEach(0..<8, id: \.self) { step in
                let angle = Double(step) / 8 * 2 * .pi
                text.foregroundStyle(Theme.cream.opacity(0.55))
                    .offset(x: cos(angle) * 1.6, y: sin(angle) * 1.6)
            }
            text.foregroundStyle(Theme.background)
        }
        .fixedSize()
        .offset(y: 22)
        .accessibilityLabel("Место \(value)")
    }
}
