import Combine
import Foundation

@MainActor
final class CatalogViewModel: ObservableObject {
    enum Phase {
        case idle, loading, loaded, failed(Error)
    }

    @Published private(set) var items: [Anime] = []
    @Published private(set) var phase: Phase = .idle

    var phaseKey: Int {
        switch phase {
        case .idle: return 0
        case .loading: return 1
        case .loaded: return items.isEmpty ? 2 : 3
        case .failed: return 4
        }
    }
    @Published private(set) var isLoadingMore = false
    @Published private(set) var loadMoreError: Error?
    @Published private(set) var reachedEnd = false
    @Published private(set) var query: CatalogQuery
    @Published private(set) var genres: Loadable<[Genre]> = .idle

    private let services: AppServices
    private var page = 0
    /// Bumped on every filter change so late responses for old filters are dropped.
    private var generation = 0

    init(query: CatalogQuery = CatalogQuery(), services: AppServices = .live) {
        self.query = query
        self.services = services
    }

    func loadIfNeeded() async {
        if case .idle = phase { await reload() }
    }

    func apply(_ newQuery: CatalogQuery) {
        guard newQuery != query else { return }
        query = newQuery
        Task { await reload() }
    }

    func setOrder(_ order: CatalogOrder) {
        var newQuery = query
        newQuery.order = order
        apply(newQuery)
    }

    func reload() async {
        generation += 1
        let current = generation
        page = 0
        reachedEnd = false
        loadMoreError = nil
        isLoadingMore = false
        if items.isEmpty { phase = .loading }
        do {
            let result = try await services.shikimori.animes(query, page: 1)
            guard current == generation else { return }
            items = Self.unique(result)
            page = 1
            reachedEnd = result.count < ShikimoriAPI.pageSize
            phase = .loaded
        } catch is CancellationError {
            if current == generation, items.isEmpty { phase = .idle }
        } catch {
            guard current == generation else { return }
            items = []
            phase = .failed(error)
        }
    }

    func loadMoreIfNeeded(current anime: Anime) async {
        guard let index = items.firstIndex(of: anime), index >= items.count - 6 else { return }
        await loadMore()
    }

    func loadMore() async {
        guard case .loaded = phase, !isLoadingMore, !reachedEnd else { return }
        let current = generation
        isLoadingMore = true
        loadMoreError = nil
        defer { if current == generation { isLoadingMore = false } }
        do {
            let result = try await services.shikimori.animes(query, page: page + 1)
            guard current == generation else { return }
            page += 1
            let known = Set(items.map(\.id))
            items.append(contentsOf: Self.unique(result).filter { !known.contains($0.id) })
            reachedEnd = result.count < ShikimoriAPI.pageSize
        } catch is CancellationError {
        } catch {
            if current == generation { loadMoreError = error }
        }
    }

    func loadGenres() async {
        if case .loaded = genres { return }
        genres = .loading
        do {
            genres = .loaded(try await services.shikimori.genres())
        } catch {
            genres = .failed(error)
        }
    }

    struct ActiveFilter: Identifiable {
        let title: String
        /// The current query with this filter removed.
        let without: CatalogQuery
        var id: String { title }
    }

    /// Human-readable active filters, each with a query that removes it.
    var activeFilters: [ActiveFilter] {
        var result: [ActiveFilter] = []
        let genreNames = Dictionary(uniqueKeysWithValues: (genres.value ?? []).map { ($0.id, $0.title) })
        for id in query.genreIDs.sorted() {
            var copy = query
            copy.genreIDs.remove(id)
            result.append(ActiveFilter(title: genreNames[id] ?? "Жанр", without: copy))
        }
        if let season = query.season {
            var copy = query
            copy.season = nil
            result.append(ActiveFilter(title: season.title, without: copy))
        }
        if let year = query.year {
            var copy = query
            copy.year = nil
            result.append(ActiveFilter(title: String(year), without: copy))
        }
        if let kind = query.kind {
            var copy = query
            copy.kind = nil
            result.append(ActiveFilter(title: kind.title, without: copy))
        }
        if let status = query.status {
            var copy = query
            copy.status = nil
            result.append(ActiveFilter(title: status.title, without: copy))
        }
        return result
    }

    private static func unique(_ list: [Anime]) -> [Anime] {
        var seen = Set<Int>()
        return list.filter { seen.insert($0.id).inserted }
    }
}
