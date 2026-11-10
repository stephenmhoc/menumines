import Foundation

/// Manages persistence and retrieval of game statistics.
/// Stores raw game results and computes derived metrics at runtime.
@Observable
final class StatsStore {
    private static let resultsKey = "gameResults"
    private static let resetAtKey = "statsResetAt"
    private static let pastDailyResultsKey = "pastDailyResults"

    /// All recorded game results, sorted by completion date (newest first).
    /// Daily results here are from the day itself. Past dailies are never in this list.
    private(set) var results: [GameResult] = []

    /// Every past-daily result this Mac holds, including any for a day that has since gained
    /// an on-the-day result from another Mac. Kept whole so that every Mac stores and syncs
    /// the same set. Use `pastDailyResults` for anything shown or counted.
    ///
    /// Written only by this class and its past-dailies extension, through `setPastDailyResults`.
    private(set) var storedPastDailyResults: [GameResult] = []

    /// When statistics were last erased. Results from before this never come back.
    private(set) var resetAt: Date?

    /// Shared singleton instance.
    static let shared = StatsStore()

    private init() {
        loadResults()
    }

    // MARK: - Computed Metrics

    /// Total number of games played.
    var gamesPlayed: Int {
        results.count
    }

    /// Number of games won.
    var wins: Int { results.wins }

    /// Win rate as a percentage (0-100), or nil if no games played.
    var winRate: Int? { results.winRate }

    /// Best time among wins in seconds, or nil if no wins.
    var bestTime: TimeInterval? { results.bestTime }

    /// Average time among wins in seconds, or nil if no wins.
    var averageTime: TimeInterval? { results.averageTime }

    /// Date when tracking started (earliest recorded result), or nil if no games.
    var trackedSince: Date? {
        (results + pastDailyResults).map(\.completedAt).min()
    }

    /// Whether there are any recorded games.
    var hasResults: Bool {
        !results.isEmpty
    }

    // MARK: - Daily Puzzle Metrics

    /// All recorded daily puzzle results (excludes random/continuous play).
    var dailyResults: [GameResult] {
        results.filter { $0.puzzleType == .daily }
    }

    /// Daily puzzle results keyed by seed, useful for history/calendar views.
    var dailyResultsBySeed: [Int64: GameResult] {
        Dictionary(dailyResults.map { ($0.dailySeed, $0) }) { existing, _ in existing }
    }

    /// Recent daily puzzle results, newest first.
    var recentDailyResults: [GameResult] {
        dailyResults
            .sorted { $0.dailySeed > $1.dailySeed }
            .prefix(5)
            .map { $0 }
    }

    /// Total number of daily puzzles played.
    var dailyGamesPlayed: Int {
        dailyResults.count
    }

    /// Number of daily puzzles won.
    var dailyWins: Int { dailyResults.wins }

    /// Daily puzzle win rate as a percentage (0-100), or nil if no daily games played.
    var dailyWinRate: Int? { dailyResults.winRate }

    /// Best time among daily wins in seconds, or nil if no daily wins.
    var dailyBestTime: TimeInterval? { dailyResults.bestTime }

    /// Average time among daily wins in seconds, or nil if no daily wins.
    var dailyAverageTime: TimeInterval? { dailyResults.averageTime }

    /// Daily completion rate over the local tracking span, as a percentage.
    var dailyCompletionRate: Int? {
        dailyCompletionRate(asOf: Date())
    }

    /// Daily completion rate over the local tracking span, as a percentage.
    func dailyCompletionRate(asOf date: Date) -> Int? {
        let dates = completionDates
        guard let first = dates.first else { return nil }

        let calendar = Calendar.utc
        let today = calendar.startOfDay(for: date)
        let firstDay = calendar.startOfDay(for: first)
        guard let dayCount = calendar.dateComponents([.day], from: firstDay, to: today).day else {
            return nil
        }

        let trackedDays = max(1, dayCount + 1)
        return Int(round(Double(dates.count) / Double(trackedDays) * 100))
    }

    // MARK: - Streaks

    /// Current consecutive-day streak based on completed daily seeds.
    var currentStreak: Int {
        currentStreak(asOf: Date())
    }

    /// Current consecutive-day streak based on completed daily seeds.
    func currentStreak(asOf date: Date) -> Int {
        let dates = completionDates
        guard let latest = dates.last else { return 0 }

        let calendar = Calendar.utc
        let today = calendar.startOfDay(for: date)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)
        guard calendar.isDate(latest, inSameDayAs: today)
            || (yesterday.map { calendar.isDate(latest, inSameDayAs: $0) } ?? false) else {
            return 0
        }

        var streak = 1
        var previous = latest

        for date in dates.dropLast().reversed() {
            guard let expected = calendar.date(byAdding: .day, value: -1, to: previous),
                  calendar.isDate(date, inSameDayAs: expected) else {
                break
            }
            streak += 1
            previous = date
        }

        return streak
    }

    /// Longest consecutive-day streak based on completed daily seeds.
    var longestStreak: Int {
        let dates = completionDates
        guard !dates.isEmpty else { return 0 }

        let calendar = Calendar.utc
        var longest = 1
        var current = 1
        var previous = dates[0]

        for date in dates.dropFirst() {
            if let expected = calendar.date(byAdding: .day, value: 1, to: previous),
               calendar.isDate(date, inSameDayAs: expected) {
                current += 1
            } else {
                current = 1
            }
            longest = max(longest, current)
            previous = date
        }

        return longest
    }

    // MARK: - Recording

    /// Records a game result and persists to storage.
    /// Daily puzzles are deduplicated by seed (only one result per day).
    /// Random puzzles are always recorded (no deduplication).
    /// Past dailies go to their own storage, once per day, and replays are never recorded.
    /// - Returns: Whether the result was recorded.
    @MainActor
    @discardableResult
    func record(_ result: GameResult) -> Bool {
        switch result.puzzleType {
        case .practice:
            return false
        case .pastDaily:
            return recordPastDaily(result)
        case .daily:
            if results.contains(where: { $0.puzzleType == .daily && $0.dailySeed == result.dailySeed }) {
                return false
            }
        case .random:
            // Random puzzles are always recorded
            break
        }
        results.insert(result, at: 0)
        saveResults()

        // Publish immediately rather than at next launch, so finishing on one Mac is visible
        // on another before the streak has a chance to look broken.
        if result.puzzleType == .daily {
            StatsSync.sync()
        }
        return true
    }

    /// Clears all statistics, on every Mac.
    @MainActor
    func reset() {
        let date = Date()
        results = []
        storedPastDailyResults = []
        resetAt = date
        UserDefaults.standard.removeObject(forKey: Self.resultsKey)
        UserDefaults.standard.removeObject(forKey: Self.pastDailyResultsKey)
        UserDefaults.standard.set(date, forKey: Self.resetAtKey)
        StatsSync.publishReset(at: date)
    }

    /// Applies a reset made on another Mac.
    /// - Returns: Whether anything local changed.
    @MainActor
    @discardableResult
    func applyReset(at date: Date) -> Bool {
        if let resetAt, resetAt >= date { return false }

        resetAt = date
        UserDefaults.standard.set(date, forKey: Self.resetAtKey)

        var changed = false

        let remaining = results.filter { $0.completedAt > date }
        if remaining.count != results.count {
            results = remaining
            saveResults()
            changed = true
        }

        let remainingPast = storedPastDailyResults.filter { $0.completedAt > date }
        if remainingPast.count != storedPastDailyResults.count {
            setPastDailyResults(remainingPast)
            changed = true
        }
        return changed
    }

    // MARK: - Persistence

    private func loadResults() {
        resetAt = UserDefaults.standard.object(forKey: Self.resetAtKey) as? Date
        if let data = UserDefaults.standard.data(forKey: Self.resultsKey) {
            do {
                results = try JSONDecoder().decode([GameResult].self, from: data)
            } catch {
                Telemetry.report(error, area: "persistence", step: "stats_load")
            }
        }
        if let data = UserDefaults.standard.data(forKey: Self.pastDailyResultsKey) {
            do {
                storedPastDailyResults = try JSONDecoder().decode([GameResult].self, from: data)
            } catch {
                Telemetry.report(error, area: "persistence", step: "past_daily_stats_load")
            }
        }
    }

    /// Replaces the stored past dailies and saves them.
    func setPastDailyResults(_ results: [GameResult]) {
        storedPastDailyResults = results
        savePastDailyResults()
    }

    /// Past dailies have a key of their own. A version that doesn't know about them leaves it
    /// alone, and can still read everything under the key it does know.
    private func savePastDailyResults() {
        do {
            let data = try JSONEncoder().encode(storedPastDailyResults)
            UserDefaults.standard.set(data, forKey: Self.pastDailyResultsKey)
        } catch {
            Telemetry.report(error, area: "persistence", step: "past_daily_stats_save")
        }
    }

    private func saveResults() {
        do {
            let data = try JSONEncoder().encode(results)
            UserDefaults.standard.set(data, forKey: Self.resultsKey)
        } catch {
            Telemetry.report(error, area: "persistence", step: "stats_save")
        }
    }

    // MARK: - Streak Helpers

    private var completionDates: [Date] {
        // Only count daily puzzles for streak calculations
        let dailySeeds = Set(dailyResults.map(\.dailySeed))
        return dailySeeds.compactMap { dateFromSeed($0) }.sorted()
    }

    // MARK: - iCloud Sync

    /// Merges a set of results in from another device.
    ///
    /// Only daily results are exchanged. They are the ones tied to a calendar day and to
    /// streaks, so they mean the same thing on every Mac, whereas random puzzles are just a
    /// count of games played on one machine and syncing them would double-count.
    ///
    /// Each day has one result on every Mac: the first one finished. A result for today also
    /// completes today here, so a day finished on one Mac can't be played again on another.
    /// - Returns: Whether anything local changed.
    @MainActor
    @discardableResult
    func merge(dailyResults incoming: [GameResult]) -> Bool {
        var bySeed = dailyResultsBySeed
        var changed = false

        for result in incoming where result.puzzleType == .daily {
            if let resetAt, result.completedAt <= resetAt { continue }
            if let existing = bySeed[result.dailySeed], !Self.isFirst(result, before: existing) { continue }
            bySeed[result.dailySeed] = result
            changed = true
        }

        guard changed else { return false }

        results = (results.filter { $0.puzzleType != .daily } + bySeed.values)
            .sorted { $0.completedAt > $1.completedAt }
        saveResults()

        if let today = bySeed[seedFromDate(Date())] {
            adoptAgreedStats(
                forSeed: today.dailySeed,
                won: today.won,
                elapsedTime: today.elapsedTime,
                flagCount: today.won ? Board.mineCount : 0
            )
            markCompleteAndRecordStats(
                forSeed: today.dailySeed,
                won: today.won,
                elapsedTime: today.elapsedTime,
                flagCount: today.won ? Board.mineCount : 0
            )
        }
        return true
    }

    /// Picks between two results for one day, the same way on every Mac.
    static func isFirst(_ result: GameResult, before other: GameResult) -> Bool {
        if result.completedAt != other.completedAt {
            return result.completedAt < other.completedAt
        }
        // Only for an exact tie, so that merge order can never decide it.
        return result.won && !other.won
    }

    // MARK: - Testing Support

    /// Creates a StatsStore with the given results for testing purposes.
    /// - Parameters:
    ///   - results: The initial results to populate.
    ///   - pastDailyResults: The initial past-daily results to populate.
    static func forTesting(with results: [GameResult] = [], pastDailyResults: [GameResult] = []) -> StatsStore {
        let store = StatsStore()
        store.results = results
        store.storedPastDailyResults = pastDailyResults
        return store
    }
}

/// The same sums for all games and for daily games alone.
private extension [GameResult] {
    var wins: Int {
        filter(\.won).count
    }

    var winRate: Int? {
        guard !isEmpty else { return nil }
        return Int(round(Double(wins) / Double(count) * 100))
    }

    var bestTime: TimeInterval? {
        filter(\.won).map(\.elapsedTime).min()
    }

    var averageTime: TimeInterval? {
        let winTimes = filter(\.won).map(\.elapsedTime)
        guard !winTimes.isEmpty else { return nil }
        return winTimes.reduce(0, +) / Double(winTimes.count)
    }
}
