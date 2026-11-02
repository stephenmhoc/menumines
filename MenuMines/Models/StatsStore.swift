import Foundation

/// Manages persistence and retrieval of game statistics.
/// Stores raw game results and computes derived metrics at runtime.
@Observable
final class StatsStore {
    private static let resultsKey = "gameResults"
    private static let resetAtKey = "statsResetAt"

    /// All recorded game results, sorted by completion date (newest first).
    private(set) var results: [GameResult] = []

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
    var wins: Int {
        results.filter(\.won).count
    }

    /// Win rate as a percentage (0-100), or nil if no games played.
    var winRate: Int? {
        guard gamesPlayed > 0 else { return nil }
        return Int(round(Double(wins) / Double(gamesPlayed) * 100))
    }

    /// Best time among wins in seconds, or nil if no wins.
    var bestTime: TimeInterval? {
        let winTimes = results.filter(\.won).map(\.elapsedTime)
        return winTimes.min()
    }

    /// Average time among wins in seconds, or nil if no wins.
    var averageTime: TimeInterval? {
        let winTimes = results.filter(\.won).map(\.elapsedTime)
        guard !winTimes.isEmpty else { return nil }
        return winTimes.reduce(0, +) / Double(winTimes.count)
    }

    /// Date when tracking started (earliest recorded result), or nil if no games.
    var trackedSince: Date? {
        results.map(\.completedAt).min()
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

    /// Returns the daily result for a seed, if one exists.
    func dailyResult(forSeed seed: Int64) -> GameResult? {
        dailyResultsBySeed[seed]
    }

    /// Total number of daily puzzles played.
    var dailyGamesPlayed: Int {
        dailyResults.count
    }

    /// Number of daily puzzles won.
    var dailyWins: Int {
        dailyResults.filter(\.won).count
    }

    /// Daily puzzle win rate as a percentage (0-100), or nil if no daily games played.
    var dailyWinRate: Int? {
        guard dailyGamesPlayed > 0 else { return nil }
        return Int(round(Double(dailyWins) / Double(dailyGamesPlayed) * 100))
    }

    /// Best time among daily wins in seconds, or nil if no daily wins.
    var dailyBestTime: TimeInterval? {
        let winTimes = dailyResults.filter(\.won).map(\.elapsedTime)
        return winTimes.min()
    }

    /// Average time among daily wins in seconds, or nil if no daily wins.
    var dailyAverageTime: TimeInterval? {
        let winTimes = dailyResults.filter(\.won).map(\.elapsedTime)
        guard !winTimes.isEmpty else { return nil }
        return winTimes.reduce(0, +) / Double(winTimes.count)
    }

    /// Daily completion rate over the local tracking span, as a percentage.
    var dailyCompletionRate: Int? {
        dailyCompletionRate(asOf: Date())
    }

    /// Daily completion rate over the local tracking span, as a percentage.
    func dailyCompletionRate(asOf date: Date) -> Int? {
        let dates = completionDates
        guard let first = dates.first else { return nil }

        let calendar = Self.utcCalendar
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

        let calendar = Self.utcCalendar
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

        let calendar = Self.utcCalendar
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
    /// - Returns: Whether the result was recorded.
    @MainActor
    @discardableResult
    func record(_ result: GameResult) -> Bool {
        // Only deduplicate daily puzzles - random puzzles are always recorded
        if result.puzzleType == .daily {
            if results.contains(where: { $0.puzzleType == .daily && $0.dailySeed == result.dailySeed }) {
                return false
            }
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
        resetAt = date
        UserDefaults.standard.removeObject(forKey: Self.resultsKey)
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

        let remaining = results.filter { $0.completedAt > date }
        guard remaining.count != results.count else { return false }
        results = remaining
        saveResults()
        return true
    }

    // MARK: - Persistence

    private func loadResults() {
        resetAt = UserDefaults.standard.object(forKey: Self.resetAtKey) as? Date
        guard let data = UserDefaults.standard.data(forKey: Self.resultsKey) else { return }
        do {
            results = try JSONDecoder().decode([GameResult].self, from: data)
        } catch {
            Telemetry.report(error, area: "persistence", step: "stats_load")
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

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

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
    private static func isFirst(_ result: GameResult, before other: GameResult) -> Bool {
        if result.completedAt != other.completedAt {
            return result.completedAt < other.completedAt
        }
        // Only for an exact tie, so that merge order can never decide it.
        return result.won && !other.won
    }

    // MARK: - Testing Support

    /// Creates a StatsStore with the given results for testing purposes.
    /// - Parameter results: The initial results to populate.
    static func forTesting(with results: [GameResult] = []) -> StatsStore {
        let store = StatsStore()
        store.results = results
        return store
    }
}
