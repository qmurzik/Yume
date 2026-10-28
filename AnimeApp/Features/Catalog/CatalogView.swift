import SwiftUI

struct CatalogView: View {
    var body: some View {
        NavigationStack {
            CatalogGrid(model: CatalogViewModel(), showsFilters: true)
                .navigationTitle("Каталог")
                .animeNavigation()
        }
    }
}

/// "See all" list opened from a home shelf.
struct AnimeGridScreen: View {
    let title: String
    let query: CatalogQuery

    var body: some View {
        CatalogGrid(model: CatalogViewModel(query: query), showsFilters: false)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }
}

private struct CatalogGrid: View {
    @StateObject private var model: CatalogViewModel
    let showsFilters: Bool
    @State private var showFilters = false

    init(model: @autoclosure @escaping () -> CatalogViewModel, showsFilters: Bool) {
        _model = StateObject(wrappedValue: model())
        self.showsFilters = showsFilters
    }

    private let columns = [GridItem(.adaptive(minimum: 106, maximum: 170), spacing: 14, alignment: .top)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if showsFilters { filterBar }
                content
            }
            .padding(.bottom, 24)
        }
        .screenBackground()
        .refreshable { await model.reload() }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) { sortMenu }
        }
        .sheet(isPresented: $showFilters) {
            CatalogFiltersView(initial: model.query, model: model) { model.apply($0) }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .task {
            await model.loadIfNeeded()
            if showsFilters { await model.loadGenres() }
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button {
                    Haptics.tap()
                    showFilters = true
                } label: {
                    Chip(title: model.query.isFiltered ? "Фильтры · \(model.activeFilters.count)" : "Фильтры",
                         systemImage: "slider.horizontal.3",
                         isSelected: model.query.isFiltered)
                }
                ForEach(model.activeFilters) { filter in
                    Button {
                        Haptics.selection()
                        model.apply(filter.without)
                    } label: {
                        Chip(title: filter.title, systemImage: "xmark")
                    }
                }
                ForEach(quickKinds, id: \.self) { kind in
                    if model.query.kind == nil {
                        Button {
                            Haptics.selection()
                            var query = model.query
                            query.kind = kind
                            model.apply(query)
                        } label: {
                            Chip(title: kind.title)
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
        .buttonStyle(PressableStyle())
    }

    private let quickKinds: [AnimeKind] = [.tv, .movie, .ova]

    private var sortMenu: some View {
        Menu {
            Picker("Сортировка", selection: Binding(get: { model.query.order }, set: { model.setOrder($0) })) {
                ForEach(CatalogOrder.allCases) { order in
                    Text(order.title).tag(order)
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.subheadline.weight(.bold))
                .frame(width: 34, height: 34)
                .background(Theme.surface, in: Circle())
        }
        .accessibilityLabel("Сортировка")
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle, .loading:
            SkeletonGrid(columns: columns)
        case .failed(let error):
            ErrorStateView(error: error) { Task { await model.reload() } }
        case .loaded where model.items.isEmpty:
            VStack(spacing: 12) {
                EmptyStateView(title: "Ничего не найдено", message: "Попробуйте ослабить фильтры.", systemImage: "line.3.horizontal.decrease.circle")
                if model.query.isFiltered {
                    Button("Сбросить фильтры") {
                        model.apply(CatalogQuery(order: model.query.order))
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
        case .loaded:
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(model.items) { anime in
                    NavigationLink(value: AnimeRoute(id: anime.id, preview: anime)) {
                        AnimeCard(anime: anime)
                    }
                    .buttonStyle(PressableStyle())
                    .task { await model.loadMoreIfNeeded(current: anime) }
                }
            }
            .padding(.horizontal)
            footer
        }
    }

    @ViewBuilder
    private var footer: some View {
        if model.isLoadingMore {
            ProgressView().tint(Theme.pink).frame(maxWidth: .infinity).padding()
        } else if let error = model.loadMoreError {
            ErrorStateView(error: error, compact: true) { Task { await model.loadMore() } }
        } else if model.reachedEnd {
            Text("Вы долистали до конца").font(.footnote).foregroundStyle(Theme.tertiaryText).frame(maxWidth: .infinity).padding()
        }
    }
}
