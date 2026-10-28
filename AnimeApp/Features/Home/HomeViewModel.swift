import Combine
import Foundation

@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var ongoing: Loadable<[Anime]> = .idle
    @Published private(set) var updated: Loadable<[Anime]> = .idle
    @Published private(set) var popular: Loadable<[Anime]> = .idle
    @Published private(set) var top: Loadable<[Anime]> = .idle

    static let ongoingQuery: CatalogQuery = {
        var query = CatalogQuery()
        query.status = .ongoing
        query.order = .popularity
        return query
    }()

    static let popularQuery = CatalogQuery(order: .popularity)
    static let topQuery = CatalogQuery(order: .ranked)

    private let services: AppServices

    init(services: AppServices = .live) {
        self.services = services
    }

    func loadIfNeeded() async {
        guard ongoing.isIdle else { return }
        await reload()
    }

    func reload() async {
        async let first: Void = loadOngoing()
        async let second: Void = loadUpdated()
        async let third: Void = loadPopular()
        async let fourth: Void = loadTop()
        _ = await (first, second, third, fourth)
    }

    func loadOngoing() async {
        ongoing = .loading
        ongoing = await result { try await self.services.shikimori.animes(Self.ongoingQuery, page: 1, limit: 20) }
    }

    func loadPopular() async {
        popular = .loading
        popular = await result { try await self.services.shikimori.animes(Self.popularQuery, page: 1, limit: 20) }
    }

    func loadTop() async {
        top = .loading
        top = await result { try await self.services.shikimori.animes(Self.topQuery, page: 1, limit: 20) }
    }

    /// Hero banner: the most popular ongoing titles that have a description-worthy poster.
    var featured: [Anime] {
        Array((ongoing.value ?? []).filter { $0.posterURL != nil }.prefix(6))
    }

    /// Fresh episodes come from AniLibria; metadata and posters are taken from Shikimori by id.
    func loadUpdated() async {
        updated = .loading
        updated = await result {
            let releases = try await self.services.aniLibria.latest(limit: 24)
            var seen = Set<Int>()
            let ids = releases.compactMap(\.shikimoriID).filter { seen.insert($0).inserted }
            return try await self.services.shikimori.animes(ids: ids)
        }
    }

    private func result(_ work: @escaping () async throws -> [Anime]) async -> Loadable<[Anime]> {
        do {
            return .loaded(try await work())
        } catch is CancellationError {
            return .idle
        } catch {
            return .failed(error)
        }
    }
}
