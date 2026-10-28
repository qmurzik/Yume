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
            Form {
                Section {
                    NavigationLink {
                        GenrePicker(selection: $query.genreIDs, model: model)
                    } label: {
                        LabeledContent("Жанры", value: genresSummary)
                    }
                }
                Section("Период") {
                    Picker("Год", selection: $query.year) {
                        Text("Любой").tag(Int?.none)
                        ForEach(years, id: \.self) { year in
                            Text(String(year)).tag(Int?.some(year))
                        }
                    }
                    Picker("Сезон", selection: $query.season) {
                        Text("Любой").tag(AnimeSeason?.none)
                        ForEach(AnimeSeason.allCases) { season in
                            Text(season.title).tag(AnimeSeason?.some(season))
                        }
                    }
                }
                Section("Тайтл") {
                    Picker("Тип", selection: $query.kind) {
                        Text("Любой").tag(AnimeKind?.none)
                        ForEach(AnimeKind.filterable) { kind in
                            Text(kind.title).tag(AnimeKind?.some(kind))
                        }
                    }
                    Picker("Статус", selection: $query.status) {
                        Text("Любой").tag(AnimeStatus?.none)
                        ForEach(AnimeStatus.allCases) { status in
                            Text(status.title).tag(AnimeStatus?.some(status))
                        }
                    }
                }
                Section("Сортировка") {
                    Picker("Порядок", selection: $query.order) {
                        ForEach(CatalogOrder.allCases) { order in
                            Text(order.title).tag(order)
                        }
                    }
                }
                if query.isFiltered {
                    Section {
                        Button("Сбросить фильтры", role: .destructive) {
                            let order = query.order
                            query = CatalogQuery()
                            query.order = order
                        }
                    }
                }
            }
            .navigationTitle("Фильтры")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Применить") {
                        onApply(query)
                        dismiss()
                    }
                }
            }
            .task { await model.loadGenres() }
        }
    }

    private var genresSummary: String {
        guard !query.genreIDs.isEmpty else { return "Любые" }
        let names = (model.genres.value ?? []).filter { query.genreIDs.contains($0.id) }.map(\.title)
        return names.isEmpty ? "Выбрано: \(query.genreIDs.count)" : names.joined(separator: ", ")
    }
}

private struct GenrePicker: View {
    @Binding var selection: Set<Int>
    @ObservedObject var model: CatalogViewModel

    var body: some View {
        LoadableView(state: model.genres, isEmpty: { $0.isEmpty }, retry: {
            Task { await model.loadGenres() }
        }) { genres in
            List(genres) { genre in
                Button {
                    if selection.contains(genre.id) {
                        selection.remove(genre.id)
                    } else {
                        selection.insert(genre.id)
                    }
                } label: {
                    HStack {
                        Text(genre.title).foregroundStyle(.primary)
                        Spacer()
                        if selection.contains(genre.id) {
                            Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
        }
        .navigationTitle("Жанры")
        .toolbar {
            if !selection.isEmpty {
                Button("Очистить") { selection.removeAll() }
            }
        }
    }
}
