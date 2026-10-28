import SwiftUI

struct CatalogView: View {
    @StateObject private var model = CatalogViewModel()
    @State private var showFilters = false

    private let columns = [GridItem(.adaptive(minimum: 108, maximum: 180), spacing: 12, alignment: .top)]

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Каталог")
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) { sortMenu }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            showFilters = true
                        } label: {
                            Image(systemName: model.query.isFiltered
                                  ? "line.3.horizontal.decrease.circle.fill"
                                  : "line.3.horizontal.decrease.circle")
                        }
                        .accessibilityLabel("Фильтры")
                    }
                }
                .sheet(isPresented: $showFilters) {
                    CatalogFiltersView(initial: model.query, model: model) { model.apply($0) }
                }
                .task { await model.loadIfNeeded() }
                .animeNavigation()
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Сортировка", selection: Binding(get: { model.query.order }, set: { model.setOrder($0) })) {
                ForEach(CatalogOrder.allCases) { order in
                    Text(order.title).tag(order)
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down.circle")
        }
        .accessibilityLabel("Сортировка")
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle, .loading:
            LoadingStateView()
        case .failed(let error):
            ErrorStateView(error: error) { Task { await model.reload() } }
        case .loaded where model.items.isEmpty:
            VStack(spacing: 12) {
                EmptyStateView(title: "Ничего не найдено", message: "Попробуйте изменить фильтры.", systemImage: "line.3.horizontal.decrease.circle")
                if model.query.isFiltered {
                    Button("Сбросить фильтры") {
                        var reset = CatalogQuery()
                        reset.order = model.query.order
                        model.apply(reset)
                    }
                    .buttonStyle(.bordered)
                }
            }
        case .loaded:
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(model.items) { anime in
                        NavigationLink(value: AnimeRoute(id: anime.id, preview: anime)) {
                            AnimeCard(anime: anime)
                        }
                        .buttonStyle(.plain)
                        .task { await model.loadMoreIfNeeded(current: anime) }
                    }
                }
                .padding(.horizontal)
                footer
            }
            .refreshable { await model.reload() }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if model.isLoadingMore {
            ProgressView().padding()
        } else if let error = model.loadMoreError {
            ErrorStateView(error: error, compact: true) { Task { await model.loadMore() } }
        } else if model.reachedEnd {
            Text("Это всё").font(.footnote).foregroundStyle(.secondary).padding()
        }
    }
}
