import Combine
import Foundation

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var text = ""
    @Published private(set) var results: Loadable<[Anime]> = .idle

    static let debounce: UInt64 = 450_000_000
    private let services: AppServices

    init(services: AppServices = .live) {
        self.services = services
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
}
