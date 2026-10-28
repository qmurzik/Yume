import Combine
import Foundation

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var text = ""
    @Published private(set) var results: Loadable<[Anime]> = .idle
    @Published private(set) var trending: Loadable<[Anime]> = .idle
    @Published private(set) var recent: [String]

    static let debounce: UInt64 = 450_000_000
    private static let recentKey = "search.recent"
    private let services: AppServices

    init(services: AppServices = .live) {
        self.services = services
        recent = UserDefaults.standard.stringArray(forKey: Self.recentKey) ?? []
    }

    var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Called from `.task(id: text)`: SwiftUI cancels the previous call on every keystroke,
    /// so sleeping first gives the debounce.
    func search(debounced: Bool = true) async {
        let query = trimmed
        guard query.count >= 2 else {
            results = .idle
            return
        }
        do {
            if debounced { try await Task.sleep(nanoseconds: Self.debounce) }
            results = .loading
            // Shikimori searches both the Russian and the original titles.
            let found = try await services.shikimori.search(query)
            try Task.checkCancellation()
            results = .loaded(found)
        } catch is CancellationError {
        } catch {
            results = .failed(error)
        }
    }

    func loadTrending() async {
        guard trending.isIdle else { return }
        trending = .loading
        do {
            trending = .loaded(try await services.shikimori.animes(HomeViewModel.ongoingQuery, page: 1, limit: 12))
        } catch is CancellationError {
            trending = .idle
        } catch {
            trending = .failed(error)
        }
    }

    /// Remembers the current query once the user acts on it.
    func commit() {
        let query = trimmed
        guard query.count >= 2 else { return }
        recent.removeAll { $0.caseInsensitiveCompare(query) == .orderedSame }
        recent.insert(query, at: 0)
        recent = Array(recent.prefix(10))
        UserDefaults.standard.set(recent, forKey: Self.recentKey)
    }

    func clearRecent() {
        recent = []
        UserDefaults.standard.removeObject(forKey: Self.recentKey)
    }
}
