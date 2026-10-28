import SwiftUI

struct SearchView: View {
    @StateObject private var model = SearchViewModel()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Поиск")
                .searchable(text: $model.text, placement: .navigationBarDrawer(displayMode: .always), prompt: "Название на русском или в оригинале")
                .autocorrectionDisabled()
                .task(id: model.text) { await model.search() }
                .animeNavigation()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.results {
        case .idle:
            EmptyStateView(title: "Найдите аниме", message: "Введите хотя бы два символа: «Фрирен», «Frieren», «葬送のフリーレン».", systemImage: "magnifyingglass")
        case .loading:
            LoadingStateView(text: "Ищем…")
        case .failed(let error):
            ErrorStateView(error: error) { Task { await model.search(debounced: false) } }
        case .loaded(let items) where items.isEmpty:
            EmptyStateView(title: "Ничего не найдено", message: "По запросу «\(model.trimmed)» ничего нет. Проверьте написание.", systemImage: "questionmark.circle")
        case .loaded(let items):
            List(items) { anime in
                NavigationLink(value: AnimeRoute(id: anime.id, preview: anime)) {
                    AnimeRow(anime: anime)
                }
            }
            .listStyle(.plain)
        }
    }
}
