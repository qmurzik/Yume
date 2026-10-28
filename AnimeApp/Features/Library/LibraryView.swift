import SwiftUI

struct LibraryView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case favorites = "Избранное"
        case history = "История"
        var id: String { rawValue }
        var icon: String { self == .favorites ? "heart.fill" : "clock.fill" }
    }

    @EnvironmentObject private var library: LibraryStore
    @State private var tab: Tab = .favorites
    @State private var confirmClear = false
    @Namespace private var tabNamespace

    private let columns = [GridItem(.adaptive(minimum: 106, maximum: 170), spacing: 14, alignment: .top)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    stats
                    tabSwitcher
                    switch tab {
                    case .favorites: favorites
                    case .history: history
                    }
                }
                .padding(.bottom, 24)
            }
            .screenBackground()
            .navigationTitle("Моё")
            .toolbar {
                if tab == .history, !library.history.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Очистить") { confirmClear = true }
                            .foregroundStyle(Theme.pink)
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

    private var stats: some View {
        HStack(spacing: 0) {
            stat(value: "\(library.favorites.count)", title: "в избранном")
            divider
            stat(value: "\(library.watchedEpisodesCount)", title: "серий просмотрено")
            divider
            stat(value: hoursText, title: "за просмотром")
        }
        .padding(.vertical, 18)
        .background {
            ZStack {
                Theme.accentGradient.opacity(0.9)
                LinearGradient(colors: [.clear, .black.opacity(0.25)], startPoint: .top, endPoint: .bottom)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Theme.pink.opacity(0.3), radius: 18, y: 8)
        .padding(.horizontal)
    }

    private var hoursText: String {
        let hours = library.watchedSeconds / 3600
        return hours >= 10 ? "\(Int(hours)) ч" : String(format: "%.1f ч", hours)
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.25)).frame(width: 1, height: 36)
    }

    private func stat(value: String, title: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title2.weight(.heavy)).monospacedDigit()
            Text(title).font(.caption.weight(.medium)).opacity(0.85).multilineTextAlignment(.center)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
    }

    private var tabSwitcher: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases) { item in
                Button {
                    Haptics.selection()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { tab = item }
                } label: {
                    Label(item.rawValue, systemImage: item.icon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(tab == item ? Color.white : Theme.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background {
                            if tab == item {
                                Capsule().fill(Theme.surfaceStrong).matchedGeometryEffect(id: "tab", in: tabNamespace)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Theme.surface, in: Capsule())
        .padding(.horizontal)
    }

    @ViewBuilder
    private var favorites: some View {
        let items = library.favorites
        if items.isEmpty {
            EmptyStateView(title: "В избранном пусто", message: "Нажмите ♡ на странице тайтла, чтобы добавить его сюда.", systemImage: "heart")
        } else {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(items, id: \.anime.id) { entry in
                    NavigationLink(value: AnimeRoute(id: entry.anime.id)) {
                        SavedAnimeCard(anime: entry.anime)
                    }
                    .buttonStyle(PressableStyle())
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

    @ViewBuilder
    private var history: some View {
        let records = library.history
        if records.isEmpty {
            EmptyStateView(title: "История пуста", message: "Здесь появятся тайтлы, которые вы начали смотреть.", systemImage: "clock.arrow.circlepath")
        } else {
            LazyVStack(spacing: 10) {
                ForEach(records) { record in
                    NavigationLink(value: AnimeRoute(id: record.anime.id)) {
                        HistoryRow(record: record, watchedCount: library.progress(animeID: record.anime.id).values.filter(\.isWatched).count)
                    }
                    .buttonStyle(PressableStyle(scale: 0.98))
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

private struct HistoryRow: View {
    let record: WatchRecord
    let watchedCount: Int

    var body: some View {
        HStack(spacing: 14) {
            PosterImage(url: record.anime.posterURL, cornerRadius: 10).frame(width: 62)
            VStack(alignment: .leading, spacing: 6) {
                Text(record.anime.title).font(.headline).foregroundStyle(.white).lineLimit(2).multilineTextAlignment(.leading)
                Text("\(record.episodeTitle) · \(record.voice)")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                ProgressView(value: record.progress.fraction).tint(Theme.pink)
                HStack {
                    Label("\(watchedCount)", systemImage: "checkmark.circle")
                    Spacer()
                    Text(record.updatedAt.formatted(.relative(presentation: .named)))
                }
                .font(.caption2)
                .foregroundStyle(Theme.tertiaryText)
            }
        }
        .padding(10)
        .card()
    }
}
