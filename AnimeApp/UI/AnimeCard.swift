import SwiftUI

struct AnimeRoute: Hashable {
    let id: Int
    var preview: Anime?
}

extension View {
    /// Registers the title screen for every navigation stack.
    func animeNavigation() -> some View {
        navigationDestination(for: AnimeRoute.self) { route in
            AnimeDetailView(route: route)
        }
    }
}

struct ScoreBadge: View {
    let score: Double

    var body: some View {
        Label(String(format: "%.1f", score), systemImage: "star.fill")
            .font(.caption2.weight(.bold))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(6)
    }
}

struct AnimeCard: View {
    let anime: Anime
    var width: CGFloat?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PosterImage(url: anime.posterPreviewURL ?? anime.posterURL)
                .overlay(alignment: .topLeading) {
                    if let score = anime.score { ScoreBadge(score: score) }
                }
            Text(anime.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2, reservesSpace: true)
            Text(anime.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: width)
        .contentShape(Rectangle())
    }
}

struct SavedAnimeCard: View {
    let anime: SavedAnime

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PosterImage(url: anime.posterURL)
            Text(anime.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2, reservesSpace: true)
            if !anime.subtitle.isEmpty {
                Text(anime.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .contentShape(Rectangle())
    }
}

/// Row used by search results and lists.
struct AnimeRow: View {
    let anime: Anime

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            PosterImage(url: anime.posterPreviewURL ?? anime.posterURL, cornerRadius: 6)
                .frame(width: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(anime.title).font(.headline).lineLimit(2)
                if anime.title != anime.name {
                    Text(anime.name).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                Text(anime.subtitle).font(.caption).foregroundStyle(.secondary)
                if let score = anime.score {
                    Label(String(format: "%.2f", score), systemImage: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

/// Titled horizontal shelf of titles.
struct AnimeShelf: View {
    let title: String
    let state: Loadable<[Anime]>
    var emptyText = "Пока ничего нет"
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title3.weight(.bold)).padding(.horizontal)
            switch state {
            case .idle, .loading:
                ProgressView().frame(maxWidth: .infinity, minHeight: 240)
            case .failed(let error):
                ErrorStateView(error: error, compact: true, retry: retry)
            case .loaded(let items) where items.isEmpty:
                Text(emptyText).font(.footnote).foregroundStyle(.secondary).padding(.horizontal)
            case .loaded(let items):
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(items) { anime in
                            NavigationLink(value: AnimeRoute(id: anime.id, preview: anime)) {
                                AnimeCard(anime: anime, width: 130)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
}
