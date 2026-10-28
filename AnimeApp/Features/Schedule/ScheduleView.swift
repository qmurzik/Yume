import SwiftUI

struct ScheduleView: View {
    @StateObject private var model = ScheduleViewModel()
    private let today = ScheduleViewModel.todayWeekday()

    var body: some View {
        ZoomNavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    daySelector
                    content
                }
                .padding(.bottom, 24)
            }
            .screenBackground()
            .animation(Motion.fade, value: model.entries.phaseKey)
            .refreshable { await model.load() }
            .navigationTitle("Расписание")
            .task { await model.loadIfNeeded() }
        }
    }

    private var daySelector: some View {
        ScrollViewReader { reader in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(1...7, id: \.self) { day in
                        Button {
                            Haptics.selection()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { model.day = day }
                        } label: {
                            dayCell(day)
                        }
                        .buttonStyle(PressableStyle())
                        .id(day)
                    }
                }
                .padding(.horizontal)
            }
            .onAppear { reader.scrollTo(model.day, anchor: .center) }
        }
    }

    private func dayCell(_ day: Int) -> some View {
        let selected = model.day == day
        let date = ScheduleViewModel.date(of: day)
        let count = model.entries(for: day).count
        return VStack(spacing: 4) {
            Text(ScheduleViewModel.dayNames[day - 1]).font(.caption.weight(.bold))
            Text(date.formatted(.dateTime.day())).font(.title3.weight(.heavy))
            Circle()
                .fill(count > 0 ? (selected ? Color.white : Theme.pink) : Color.clear)
                .frame(width: 5, height: 5)
        }
        .foregroundStyle(selected ? Color.white : (day == today ? Theme.pink : Theme.secondaryText))
        .frame(width: 52, height: 74)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(selected ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.surface))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(day == today && !selected ? Theme.pink.opacity(0.6) : Theme.stroke)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.entries {
        case .idle, .loading:
            VStack(spacing: 10) {
                ForEach(0..<6, id: \.self) { _ in SkeletonRow() }
            }
            .padding(.horizontal)
        case .failed(let error):
            ErrorStateView(error: error) { Task { await model.load() } }
        case .loaded:
            let items = model.entries(for: model.day)
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(
                    title: model.day == today ? "Сегодня" : ScheduleViewModel.fullDayNames[model.day - 1],
                    subtitle: items.isEmpty ? nil : "\(items.count) \(Self.titlesWord(items.count)) по расписанию AniLibria"
                )
                if items.isEmpty {
                    EmptyStateView(title: "В этот день серий нет", message: "Выберите другой день недели.", systemImage: "calendar.badge.exclamationmark")
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, entry in
                            Group {
                                if let id = entry.title.shikimoriID {
                                    NavigationLink(value: AnimeRoute(id: id, zoomID: "day-\(id)")) {
                                        ScheduleRow(entry: entry, navigable: true).zoomSource("day-\(id)")
                                    }
                                    .buttonStyle(PressableStyle(scale: 0.98))
                                } else {
                                    ScheduleRow(entry: entry, navigable: false)
                                }
                            }
                            .appear(index)
                        }
                    }
                    .padding(.horizontal)
                    // A fresh list per day, sliding in from the side.
                    .id(model.day)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                }
            }
        }
    }

    static func titlesWord(_ count: Int) -> String {
        let mod10 = count % 10, mod100 = count % 100
        if mod10 == 1 && mod100 != 11 { return "тайтл" }
        if (2...4).contains(mod10) && !(12...14).contains(mod100) { return "тайтла" }
        return "тайтлов"
    }
}

private struct ScheduleRow: View {
    let entry: ScheduleEntry
    let navigable: Bool

    var body: some View {
        HStack(spacing: 14) {
            PosterImage(url: entry.title.posterURL, cornerRadius: 10).frame(width: 62)
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.title.title).font(.headline).foregroundStyle(.white).lineLimit(2).multilineTextAlignment(.leading)
                if let original = entry.title.originalTitle {
                    Text(original).font(.caption).foregroundStyle(Theme.secondaryText).lineLimit(1)
                }
                if let next = entry.nextEpisode {
                    Tag(text: "\(next) серия", color: Theme.pink)
                } else if !entry.isOngoing {
                    Tag(text: "Сезон завершён", color: Theme.secondaryText)
                }
            }
            Spacer(minLength: 0)
            if navigable {
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.tertiaryText)
            }
        }
        .padding(10)
        .card()
    }
}
