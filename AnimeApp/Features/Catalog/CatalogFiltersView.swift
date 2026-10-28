import SwiftUI

struct CatalogFiltersView: View {
    @State private var query: CatalogQuery
    @ObservedObject var model: CatalogViewModel
    let onApply: (CatalogQuery) -> Void
    @Environment(\.dismiss) private var dismiss

    init(initial: CatalogQuery, model: CatalogViewModel, onApply: @escaping (CatalogQuery) -> Void) {
        _query = State(initialValue: initial)
        self.model = model
        self.onApply = onApply
    }

    private var years: [Int] {
        let current = Calendar.current.component(.year, from: Date())
        return Array((1970...(current + 1)).reversed())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    group("Сортировка") {
                        Flow {
                            ForEach(CatalogOrder.allCases) { order in
                                chip(order.title, selected: query.order == order) { query.order = order }
                            }
                        }
                    }
                    group("Тип") {
                        Flow {
                            chip("Любой", selected: query.kind == nil) { query.kind = nil }
                            ForEach(AnimeKind.filterable) { kind in
                                chip(kind.title, selected: query.kind == kind) { query.kind = query.kind == kind ? nil : kind }
                            }
                        }
                    }
                    group("Статус") {
                        Flow {
                            chip("Любой", selected: query.status == nil) { query.status = nil }
                            ForEach(AnimeStatus.allCases) { status in
                                chip(status.title, selected: query.status == status) { query.status = query.status == status ? nil : status }
                            }
                        }
                    }
                    group("Сезон") {
                        Flow {
                            chip("Любой", selected: query.season == nil) { query.season = nil }
                            ForEach(AnimeSeason.allCases) { season in
                                chip(season.title, selected: query.season == season) { query.season = query.season == season ? nil : season }
                            }
                        }
                    }
                    group("Год") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                chip("Любой", selected: query.year == nil) { query.year = nil }
                                ForEach(years, id: \.self) { year in
                                    chip(String(year), selected: query.year == year) { query.year = query.year == year ? nil : year }
                                }
                            }
                            .padding(.horizontal)
                        }
                        .padding(.horizontal, -16)
                    }
                    group("Жанры") { genres }
                }
                .padding()
                .padding(.bottom, 90)
            }
            .screenBackground()
            .safeAreaInset(edge: .bottom) { bottomBar }
            .navigationTitle("Фильтры")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if query.isFiltered {
                        Button("Сбросить") {
                            Haptics.tap()
                            query = CatalogQuery(order: query.order)
                        }
                        .foregroundStyle(Theme.pink)
                    }
                }
            }
            .task { await model.loadGenres() }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var genres: some View {
        switch model.genres {
        case .idle, .loading:
            Flow {
                ForEach(0..<14, id: \.self) { index in
                    SkeletonBlock(radius: 16).frame(width: CGFloat(70 + (index * 23) % 60), height: 36)
                }
            }
            .shimmering()
        case .failed(let error):
            ErrorStateView(error: error, compact: true) { Task { await model.loadGenres() } }
        case .loaded(let list):
            Flow {
                ForEach(list) { genre in
                    chip(genre.title, selected: query.genreIDs.contains(genre.id)) {
                        if query.genreIDs.contains(genre.id) {
                            query.genreIDs.remove(genre.id)
                        } else {
                            query.genreIDs.insert(genre.id)
                        }
                    }
                }
            }
        }
    }

    private var bottomBar: some View {
        Button {
            Haptics.success()
            onApply(query)
            dismiss()
        } label: {
            Text(query.isFiltered ? "Показать результаты" : "Показать всё")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(PrimaryButtonStyle())
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline).foregroundStyle(.white)
            content()
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { action() }
        } label: {
            Chip(title: title, isSelected: selected)
        }
        .buttonStyle(PressableStyle())
    }
}
