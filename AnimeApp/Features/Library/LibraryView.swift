import SwiftUI

struct LibraryView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case favorites = "Избранное"
        case history = "История"
        var id: String { rawValue }
    }

    @EnvironmentObject private var library: LibraryStore
    @State private var tab: Tab = .favorites
    @State private var confirmClear = false

    private let columns = [GridItem(.adaptive(minimum: 108, maximum: 180), spacing: 12, alignment: .top)]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Раздел", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding([.horizontal, .bottom])

                switch tab {
                case .favorites: favorites
                case .history: history
                }
            }
            .navigationTitle("Моё")
            .toolbar {
                if tab == .history, !library.history.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Очистить", role: .destructive) { confirmClear = true }
                    }
                }
            }
            .confirmationDialog("Очистить историю и прогресс просмотра?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Очистить", role: .destructive) { library.clearHistory() }
                Button("Отмена", role: .cancel) {}
            }
            .animeNavigation()
        }
    }

    @ViewBuilder
    private var favorites: some View {
        let items = library.favorites
        if items.isEmpty {
            EmptyStateView(title: "В избранном пусто", message: "Нажмите ♡ на странице тайтла, чтобы добавить его сюда.", systemImage: "heart")
            Spacer()
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(items, id: \.anime.id) { entry in
                        NavigationLink(value: AnimeRoute(id: entry.anime.id)) {
                            SavedAnimeCard(anime: entry.anime)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                library.toggleFavorite(entry.anime)
                            } label: {
                                Label("Убрать из избранного", systemImage: "heart.slash")
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    @ViewBuilder
    private var history: some View {
        let records = library.history
        if records.isEmpty {
            EmptyStateView(title: "История пуста", message: "Здесь появятся тайтлы, которые вы начали смотреть.", systemImage: "clock.arrow.circlepath")
            Spacer()
        } else {
            List {
                ForEach(records) { record in
                    NavigationLink(value: AnimeRoute(id: record.anime.id)) {
                        HistoryRow(record: record, watchedCount: library.progress(animeID: record.anime.id).values.filter(\.isWatched).count)
                    }
                }
                .onDelete { offsets in
                    offsets.map { records[$0].anime.id }.forEach(library.removeFromHistory)
                }
            }
            .listStyle(.plain)
        }
    }
}

private struct HistoryRow: View {
    let record: WatchRecord
    let watchedCount: Int

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            PosterImage(url: record.anime.posterURL, cornerRadius: 6).frame(width: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(record.anime.title).font(.headline).lineLimit(2)
                Text("\(record.episodeTitle) · \(record.voice)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                ProgressView(value: record.progress.fraction).tint(.accentColor)
                HStack {
                    Text("Просмотрено серий: \(watchedCount)")
                    Spacer()
                    Text(record.updatedAt.formatted(.relative(presentation: .named)))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
