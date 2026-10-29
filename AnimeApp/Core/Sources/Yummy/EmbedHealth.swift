import Foundation

/// Remembers which embedded players recently refused to play, so "Авто" stops picking them.
/// Failures older than a week are forgotten.
final class EmbedHealth: @unchecked Sendable {
    static let shared = EmbedHealth()

    private let lock = NSLock()
    private let defaults: UserDefaults
    private let key = "embed.failures"
    private static let window: TimeInterval = 7 * 24 * 3600
    private static let threshold = 2

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func load(now: Date) -> [String: [TimeInterval]] {
        let raw = defaults.dictionary(forKey: key) as? [String: [TimeInterval]] ?? [:]
        return raw.mapValues { $0.filter { now.timeIntervalSince1970 - $0 < Self.window } }.filter { !$0.value.isEmpty }
    }

    func recordFailure(player: String, now: Date = Date()) {
        lock.lock(); defer { lock.unlock() }
        var failures = load(now: now)
        failures[player, default: []].append(now.timeIntervalSince1970)
        defaults.set(failures, forKey: key)
    }

    /// Players to try last: known-restricted ones plus those that failed repeatedly this week.
    func deprioritized(now: Date = Date()) -> Set<String> {
        lock.lock(); defer { lock.unlock() }
        let unreliable = load(now: now).filter { $0.value.count >= Self.threshold }.keys
        return EpisodeGrouping.restrictedPlayers.union(unreliable)
    }
}
