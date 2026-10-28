import XCTest
@testable import AnimeApp

final class RateLimiterTests: XCTestCase {
    /// Virtual clock: sleeping just advances time, so the test is instant and deterministic.
    private final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var value: TimeInterval = 0
        var now: TimeInterval { lock.lock(); defer { lock.unlock() }; return value }
        func advance(_ seconds: TimeInterval) { lock.lock(); value += seconds; lock.unlock() }
    }

    func testEnforcesEveryWindow() async throws {
        let clock = Clock()
        let limiter = RateLimiter(
            windows: [.init(limit: 5, interval: 1), .init(limit: 90, interval: 60)],
            now: { clock.now },
            sleep: { clock.advance($0) }
        )
        var times: [TimeInterval] = []
        for _ in 0..<100 {
            try await limiter.acquire()
            times.append(clock.now)
        }
        for index in 5..<times.count {
            XCTAssertGreaterThanOrEqual(times[index] - times[index - 5], 1 - 1e-9, "more than 5 requests in a second")
        }
        for index in 90..<times.count {
            XCTAssertGreaterThanOrEqual(times[index] - times[index - 90], 60 - 1e-9, "more than 90 requests in a minute")
        }
        XCTAssertEqual(times[4], 0, "the first burst is not delayed")
    }
}
