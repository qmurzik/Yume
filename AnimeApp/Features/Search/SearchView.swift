import SwiftUI

struct SearchView: View {
    @StateObject private var model = SearchViewModel()
    private let columns = [GridItem(.adaptive(minimum: 106, maximum: 170), spacing: 14, alignment: .top)]

    var body: some View {
        ZoomNavigationStack {
            ScrollView {
                content
                    .padding(.bottom, 24)
                    .animation(Motion.fade, value: model.results.phaseKey)
            }
            .scrollDismissesKeyboard(.immediately)
            .screenBackground()
            .navigationTitle("Поиск")
            .searchable(text: $model.text, placement: .navigationBarDrawer(displayMode: .always), prompt: "Фрирен, Frieren, 葬送のフリーレン…")
            .autocorrectionDisabled()
            .onSubmit(of: .search) { model.commit() }
            .task(id: model.text) { await model.search() }
            .task { await model.loadTrending() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.results {
        case .idle:
            idle
        case .loading:
            VStack(spacing: 10) {
                ForEach(0..<6, id: \.self) { _ in SkeletonRow() }
            }
            .padding()
        case .failed(let error):
            ErrorStateView(error: error) { Task { await model.search(debounced: false) } }
        case .loaded(let items) where items.isEmpty:
            EmptyStateView(title: "Ничего не найдено", message: "По запросу «\(model.trimmed)» ничего нет. Попробуйте оригинальное название.", systemImage: "questionmark.circle")
        case .loaded(let items):
            LazyVStack(spacing: 10) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, anime in
                    NavigationLink(value: AnimeRoute(id: anime.id, preview: anime, zoomID: "search-\(anime.id)")) {
                        AnimeRow(anime: anime, zoomID: "search-\(anime.id)")
                    }
                    .buttonStyle(PressableStyle(scale: 0.98))
                    .appear(index)
                    .simultaneousGesture(TapGesture().onEnded { model.commit() })
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }

    private var idle: some View {
        VStack(alignment: .leading, spacing: 26) {
            if !model.recent.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Вы искали", kicker: "履歴") {
                        Button("Очистить") { model.clearRecent() }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    Flow(spacing: 8) {
                        ForEach(model.recent, id: \.self) { query in
                            Button {
                                Haptics.selection()
                                model.text = query
                            } label: {
                                Chip(title: query, systemImage: "clock.arrow.circlepath")
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                    .padding(.horizontal)
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Сейчас смотрят", subtitle: "Популярные онгоинги", kicker: "人気")
                switch model.trending {
                case .idle, .loading:
                    SkeletonGrid(columns: columns)
                case .failed(let error):
                    ErrorStateView(error: error, compact: true) { Task { await model.loadTrending() } }
                case .loaded(let items):
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, anime in
                            NavigationLink(value: AnimeRoute(id: anime.id, preview: anime, zoomID: "trend-\(anime.id)")) {
                                AnimeCard(anime: anime, zoomID: "trend-\(anime.id)")
                            }
                            .buttonStyle(PressableStyle())
                            .appear(index)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .padding(.top, 8)
    }
}
