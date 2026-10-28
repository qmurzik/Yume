import Combine
import Foundation

@MainActor
final class CatalogViewModel: ObservableObject {
    enum Phase {
        case idle, loading, loaded, failed(Error)
    }

    @Published private(set) var items: [Anime] = []
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var isLoadingMore = false
    @Published private(set) var loadMoreError: Error?
    @Published private(set) var reachedEnd = false
    @Published private(set) var query = CatalogQuery()
    @Published private(set) var genres: Loadable<[Genre]> = .idle

    private let services: AppServices
    private var page = 0
    /// Bumped on every filter change so late responses for old filters are dropped.
    private var generation = 0

    init(services: AppServices = .live) {
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

    private static func unique(_ list: [Anime]) -> [Anime] {
        var seen = Set<Int>()
        return list.filter { seen.insert($0.id).inserted }
    }
}
