import Combine
import Foundation

@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var ongoing: Loadable<[Anime]> = .idle
    @Published private(set) var updated: Loadable<[Anime]> = .idle
    @Published private(set) var popular: Loadable<[Anime]> = .idle

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
        _ = await (first, second, third)
    }

    func loadOngoing() async {
        var query = CatalogQuery()
        query.status = .ongoing
        query.order = .popularity
        ongoing = .loading
        ongoing = await result { try await self.services.shikimori.animes(query, page: 1, limit: 20) }
    }

    func loadPopular() async {
        var query = CatalogQuery()
        query.order = .popularity
        popular = .loading
        popular = await result { try await self.services.shikimori.animes(query, page: 1, limit: 20) }
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
