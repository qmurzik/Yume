import Foundation

/// Sliding-window rate limiter shared by every request to one API.
/// Shikimori allows 5 requests per second and 90 per minute; each window is enforced.
actor RateLimiter {
    struct Window: Sendable {
        let limit: Int
        let interval: TimeInterval
    }

    private let windows: [Window]
    private var timestamps: [TimeInterval] = []
    private let now: @Sendable () -> TimeInterval
    private let sleep: @Sendable (TimeInterval) async throws -> Void

    init(
        windows: [Window],
        now: @escaping @Sendable () -> TimeInterval = { Date().timeIntervalSince1970 },
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { seconds in
            try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
        }
    ) {
        self.windows = windows
        self.now = now
        self.sleep = sleep
    }

    static let shikimori = RateLimiter(windows: [
        Window(limit: 5, interval: 1),
        Window(limit: 90, interval: 60),
    ])

    /// Suspends until a request may be sent, then records it.
    func acquire() async throws {
        while true {
            let current = now()
            let longest = windows.map(\.interval).max() ?? 0
            timestamps.removeAll { current - $0 >= longest }

            let wait = windows.compactMap { window -> TimeInterval? in
                let recent = timestamps.filter { current - $0 < window.interval }
                guard recent.count >= window.limit else { return nil }
                // The oldest request that still counts towards the limit has to leave the window.
                let oldest = recent[recent.count - window.limit]
                return oldest + window.interval - current
            }.max()

            guard let wait, wait > 0 else {
                timestamps.append(current)
                return
            }
            try await sleep(wait)
        }
    }
}
