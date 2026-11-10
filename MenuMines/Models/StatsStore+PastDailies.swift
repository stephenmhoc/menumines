import Foundation

/// Results for days played after the day had passed.
///
/// These live in `storedPastDailyResults`, apart from `results`, so nothing that computes
/// streaks, daily stats or all-games stats can see them.
extension StatsStore {
    // MARK: - Metrics

    /// Results for days played after the day had passed, newest day first.
    ///
    /// Kept apart from `results`, so nothing that computes streaks, daily stats or all-games
    /// stats can see them. A day that also has an on-the-day result is left out: that result
    /// is the one that stands, and the day is never counted twice.
    var pastDailyResults: [GameResult] {
        pastDailyResultsBySeed.values.sorted { $0.dailySeed > $1.dailySeed }
    }

    /// Past-daily results keyed by seed, without days that have an on-the-day result.
    var pastDailyResultsBySeed: [Int64: GameResult] {
        let onTheDay = dailyResultsBySeed
        return Self.firstBySeed(storedPastDailyResults).filter { onTheDay[$0.key] == nil }
    }

    /// Number of days played as past dailies.
    var pastDailyGamesPlayed: Int {
        pastDailyResultsBySeed.count
    }

    /// Number of past dailies won.
    var pastDailyWins: Int {
        pastDailyResultsBySeed.values.filter(\.won).count
    }

    /// Every day that has a result, whether from the day itself or from later.
    var playedDailySeeds: Set<Int64> {
        Set(dailyResults.map(\.dailySeed)).union(storedPastDailyResults.map(\.dailySeed))
    }

    /// Whether a day has a result, from the day itself or from later.
    func hasDailyResult(forSeed seed: Int64) -> Bool {
        results.contains { $0.puzzleType == .daily && $0.dailySeed == seed }
            || storedPastDailyResults.contains { $0.dailySeed == seed }
    }

    // MARK: - Recording

    /// Records the one result a day gets when it's played after the day has passed.
    ///
    /// Refused if the day already has a result of either kind, so a day can't be filled in
    /// twice, or filled in over a result from the day itself.
    @MainActor
    func recordPastDaily(_ result: GameResult) -> Bool {
        guard !hasDailyResult(forSeed: result.dailySeed) else { return false }

        setPastDailyResults([result] + storedPastDailyResults)
        StatsSync.sync()
        return true
    }

    // MARK: - iCloud Sync

    /// Merges past-daily results in from another device.
    ///
    /// Each day keeps one past-daily result on every Mac, the first one finished, by the same
    /// rule as on-the-day results. Nothing here touches on-the-day results, today's completion
    /// or streaks. If a day has both kinds, the on-the-day one is what's shown and counted.
    /// - Returns: Whether anything local changed.
    @MainActor
    @discardableResult
    func merge(pastDailyResults incoming: [GameResult]) -> Bool {
        var bySeed = Self.firstBySeed(storedPastDailyResults)
        var changed = false

        for result in incoming where result.puzzleType == .pastDaily {
            if let resetAt, result.completedAt <= resetAt { continue }
            if let existing = bySeed[result.dailySeed], !Self.isFirst(result, before: existing) { continue }
            bySeed[result.dailySeed] = result
            changed = true
        }

        guard changed else { return false }

        setPastDailyResults(bySeed.values.sorted { $0.completedAt > $1.completedAt })
        return true
    }

    /// One result per day, the first finished.
    private static func firstBySeed(_ results: [GameResult]) -> [Int64: GameResult] {
        Dictionary(results.map { ($0.dailySeed, $0) }) { existing, other in
            isFirst(other, before: existing) ? other : existing
        }
    }
}
