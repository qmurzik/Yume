import SwiftUI

struct ScheduleView: View {
    @StateObject private var model = ScheduleViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("День", selection: $model.day) {
                    ForEach(1...7, id: \.self) { day in
                        Text(ScheduleViewModel.dayNames[day - 1]).tag(day)
                    }
                }
                .pickerStyle(.segmented)
                .padding([.horizontal, .bottom])

                LoadableView(state: model.entries, retry: { Task { await model.load() } }) { _ in
                    let items = model.entries(for: model.day)
                    if items.isEmpty {
                        EmptyStateView(
                            title: "В этот день серий нет",
                            message: "\(ScheduleViewModel.fullDayNames[model.day - 1]): по расписанию AniLibria ничего не выходит.",
                            systemImage: "calendar.badge.exclamationmark"
                        )
                        Spacer()
                    } else {
                        List(items) { entry in
                            if let id = entry.title.shikimoriID {
                                NavigationLink(value: AnimeRoute(id: id)) { ScheduleRow(entry: entry) }
                            } else {
                                ScheduleRow(entry: entry)
                            }
                        }
                        .listStyle(.plain)
                        .refreshable { await model.load() }
                    }
                }
            }
            .navigationTitle("Расписание")
            .task { await model.loadIfNeeded() }
            .animeNavigation()
        }
    }
}

private struct ScheduleRow: View {
    let entry: ScheduleEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            PosterImage(url: entry.title.posterURL, cornerRadius: 6).frame(width: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title.title).font(.headline).lineLimit(2)
                if let original = entry.title.originalTitle {
                    Text(original).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                if let next = entry.nextEpisode {
                    Label("Ожидается \(next) серия", systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                } else if !entry.isOngoing {
                    Text("Сезон завершён").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}
