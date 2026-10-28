import SwiftUI

struct HomeView: View {
    @StateObject private var model = HomeViewModel()
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    if !library.continueWatching.isEmpty {
                        ContinueWatchingShelf(records: library.continueWatching)
                    }
                    AnimeShelf(title: "Онгоинги", state: model.ongoing) {
                        Task { await model.loadOngoing() }
                    }
                    AnimeShelf(title: "Недавно обновлённые", state: model.updated, emptyText: "Свежих серий пока нет") {
                        Task { await model.loadUpdated() }
                    }
                    AnimeShelf(title: "Популярное", state: model.popular) {
                        Task { await model.loadPopular() }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Главная")
            .refreshable { await model.reload() }
            .task { await model.loadIfNeeded() }
            .animeNavigation()
        }
    }
}

struct ContinueWatchingShelf: View {
    let records: [WatchRecord]
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Продолжить просмотр").font(.title3.weight(.bold)).padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(records) { record in
                        NavigationLink(value: AnimeRoute(id: record.anime.id)) {
                            ContinueCard(record: record)
                        }
                        .buttonStyle(.plain)
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

private struct ContinueCard: View {
    let record: WatchRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PosterImage(url: record.anime.posterURL)
                .overlay(alignment: .bottom) {
                    ProgressView(value: record.progress.fraction)
                        .tint(.accentColor)
                        .padding(8)
                }
            Text(record.anime.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2, reservesSpace: true)
            Text(record.progress.isWatched ? "Просмотрена \(record.episodeTitle.lowercased())" : record.episodeTitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 130)
    }
}
