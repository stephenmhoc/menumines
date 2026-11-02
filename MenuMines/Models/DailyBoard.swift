import Foundation

/// Returns today's daily board using a UTC date-based seed.
func dailyBoard() -> Board {
    return boardForDate(Date())
}

/// Returns a board for a specific date using a UTC date-based seed.
func boardForDate(_ date: Date) -> Board {
    let seed = seedFromDate(date)
    return Board(dailySeed: seed)
}

/// Computes a deterministic seed from a date using UTC timezone.
/// Formula: year * 10000 + month * 100 + day
/// Example: 2024-03-15 -> 20240315
func seedFromDate(_ date: Date) -> Int64 {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    let year = calendar.component(.year, from: date)
    let month = calendar.component(.month, from: date)
    let day = calendar.component(.day, from: date)
    return Int64(year * 10000 + month * 100 + day)
}

/// Converts a deterministic seed (YYYYMMDD) into a UTC date at the start of day.
func dateFromSeed(_ seed: Int64) -> Date? {
    let year = Int(seed / 10000)
    let month = Int((seed / 100) % 100)
    let day = Int(seed % 100)

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt

    var components = DateComponents()
    components.calendar = calendar
    components.timeZone = .gmt
    components.year = year
    components.month = month
    components.day = day

    return calendar.date(from: components)
}

// MARK: - Daily Completion Tracking

private let dailyCompletionKey = "dailyCompletionSeed"
private let dailyStatsRecordedKey = "dailyStatsRecordedSeed"

/// Returns whether today's daily puzzle has been completed.
func isDailyPuzzleComplete() -> Bool {
    return isDailyPuzzleComplete(for: Date())
}

/// Returns whether the daily puzzle for a specific date has been completed.
func isDailyPuzzleComplete(for date: Date) -> Bool {
    isDailyPuzzleComplete(forSeed: seedFromDate(date))
}

/// Returns whether the daily puzzle for a specific seed has been completed.
func isDailyPuzzleComplete(forSeed seed: Int64) -> Bool {
    let completedSeed = UserDefaults.standard.object(forKey: dailyCompletionKey) as? Int64 ?? 0
    return completedSeed == seed
}

/// Marks today's daily puzzle as complete.
func markDailyPuzzleComplete() {
    markDailyPuzzleComplete(for: Date())
}

/// Marks the daily puzzle for a specific date as complete.
func markDailyPuzzleComplete(for date: Date) {
    markDailyPuzzleComplete(forSeed: seedFromDate(date))
}

/// Marks the daily puzzle for a specific seed as complete.
///
/// Only moves forward. Finishing a game carried over from yesterday mustn't undo a today that
/// another Mac already completed.
func markDailyPuzzleComplete(forSeed seed: Int64) {
    let current = UserDefaults.standard.object(forKey: dailyCompletionKey) as? Int64 ?? 0
    guard seed >= current else { return }
    UserDefaults.standard.set(seed, forKey: dailyCompletionKey)
}

// MARK: - Daily Stats Recording

/// A single day's game stats.
struct DailyStats: Codable, Equatable {
    let seed: Int64
    let won: Bool
    let elapsedTime: TimeInterval
    let flagCount: Int
}

/// Returns the UserDefaults key for storing stats for a given seed.
private func statsKey(for seed: Int64) -> String {
    return "dailyStats_\(seed)"
}

/// Returns whether stats have been recorded for today.
func hasStatsBeenRecorded() -> Bool {
    hasStatsBeenRecorded(for: Date())
}

/// Returns whether stats have been recorded for a specific date.
func hasStatsBeenRecorded(for date: Date) -> Bool {
    hasStatsBeenRecorded(forSeed: seedFromDate(date))
}

/// Returns whether stats have been recorded for a specific seed.
func hasStatsBeenRecorded(forSeed seed: Int64) -> Bool {
    let recordedSeed = UserDefaults.standard.object(forKey: dailyStatsRecordedKey) as? Int64 ?? 0
    return recordedSeed == seed || UserDefaults.standard.data(forKey: statsKey(for: seed)) != nil
}

/// Records stats for today's puzzle. Does nothing if stats have already been recorded.
/// - Parameters:
///   - won: Whether the player won
///   - elapsedTime: Time taken to complete
///   - flagCount: Number of flags placed
/// - Returns: True if stats were recorded, false if already recorded or encoding failed
@discardableResult
func recordStats(won: Bool, elapsedTime: TimeInterval, flagCount: Int) -> Bool {
    recordStats(for: Date(), won: won, elapsedTime: elapsedTime, flagCount: flagCount)
}

/// Records stats for a specific date's puzzle. Does nothing if stats have already been recorded.
/// - Parameters:
///   - date: The date of the puzzle
///   - won: Whether the player won
///   - elapsedTime: Time taken to complete
///   - flagCount: Number of flags placed
/// - Returns: True if stats were recorded, false if already recorded or encoding failed
@discardableResult
func recordStats(for date: Date, won: Bool, elapsedTime: TimeInterval, flagCount: Int) -> Bool {
    recordStats(forSeed: seedFromDate(date), won: won, elapsedTime: elapsedTime, flagCount: flagCount)
}

/// Records stats for a specific seed's puzzle. Does nothing if stats have already been recorded.
/// - Parameters:
///   - seed: The daily puzzle seed
///   - won: Whether the player won
///   - elapsedTime: Time taken to complete
///   - flagCount: Number of flags placed
/// - Returns: True if stats were recorded, false if already recorded or encoding failed
@discardableResult
func recordStats(forSeed seed: Int64, won: Bool, elapsedTime: TimeInterval, flagCount: Int) -> Bool {
    guard !hasStatsBeenRecorded(forSeed: seed) else { return false }

    let stats = DailyStats(seed: seed, won: won, elapsedTime: elapsedTime, flagCount: flagCount)

    // Encode stats
    let data: Data
    do {
        data = try JSONEncoder().encode(stats)
    } catch {
        Telemetry.report(error, area: "persistence", step: "daily_stats_save")
        return false
    }

    // Save the stats record
    UserDefaults.standard.set(data, forKey: statsKey(for: seed))

    // Mark that stats have been recorded for this day
    UserDefaults.standard.set(seed, forKey: dailyStatsRecordedKey)

    return true
}

/// Retrieves the stats for a specific date, if they exist.
func getStats(for date: Date) -> DailyStats? {
    getStats(forSeed: seedFromDate(date))
}

/// Retrieves the stats for a specific seed, if they exist.
func getStats(forSeed seed: Int64) -> DailyStats? {
    guard let data = UserDefaults.standard.data(forKey: statsKey(for: seed)) else { return nil }

    do {
        return try JSONDecoder().decode(DailyStats.self, from: data)
    } catch {
        // This is the fallback the app restores a completed daily from, so a decode failure
        // here looks to the player like their result vanished. Every other decode path
        // reports; this one used to swallow.
        Telemetry.report(error, area: "persistence", step: "daily_stats_load")
        return nil
    }
}

/// Atomically marks the daily puzzle as complete and records stats.
/// This is the recommended way to mark completion to ensure consistency.
/// - Parameters:
///   - date: The date of the puzzle
///   - won: Whether the player won
///   - elapsedTime: Time taken to complete
///   - flagCount: Number of flags placed
/// - Returns: True if both operations succeeded, false otherwise
@discardableResult
func markCompleteAndRecordStats(for date: Date, won: Bool, elapsedTime: TimeInterval, flagCount: Int) -> Bool {
    markCompleteAndRecordStats(forSeed: seedFromDate(date), won: won, elapsedTime: elapsedTime, flagCount: flagCount)
}

/// Replaces a day's stats with the result every Mac agreed on.
///
/// If this Mac finished the day differently, its saved boards show a game that no longer
/// counts, so they go too, and a relaunch rebuilds the board from the stats.
func adoptAgreedStats(forSeed seed: Int64, won: Bool, elapsedTime: TimeInterval, flagCount: Int) {
    guard let existing = getStats(forSeed: seed) else { return }
    guard existing.won != won || existing.elapsedTime != elapsedTime else { return }

    UserDefaults.standard.removeObject(forKey: statsKey(for: seed))
    UserDefaults.standard.removeObject(forKey: dailyStatsRecordedKey)
    recordStats(forSeed: seed, won: won, elapsedTime: elapsedTime, flagCount: flagCount)

    guard existing.won != won else { return }
    if let snapshot = GameSnapshot.loadAnyDay(), snapshot.dailySeed == seed, snapshot.status != .playing {
        GameSnapshot.clear()
    }
    GameSnapshot.withStorageKey(GameSnapshot.dailyNamespace) { GameSnapshot.clear() }
}

/// Atomically marks the daily puzzle seed as complete and records stats.
/// This is the recommended way to mark completion to ensure consistency.
/// - Parameters:
///   - seed: The daily puzzle seed
///   - won: Whether the player won
///   - elapsedTime: Time taken to complete
///   - flagCount: Number of flags placed
/// - Returns: True if completion is consistent after the call, false otherwise
@discardableResult
func markCompleteAndRecordStats(forSeed seed: Int64, won: Bool, elapsedTime: TimeInterval, flagCount: Int) -> Bool {
    let recorded = recordStats(forSeed: seed, won: won, elapsedTime: elapsedTime, flagCount: flagCount)
    guard recorded || hasStatsBeenRecorded(forSeed: seed) else { return false }

    markDailyPuzzleComplete(forSeed: seed)
    return true
}

/// Atomically marks today's daily puzzle as complete and records stats.
/// - Parameters:
///   - won: Whether the player won
///   - elapsedTime: Time taken to complete
///   - flagCount: Number of flags placed
/// - Returns: True if both operations succeeded, false otherwise
@discardableResult
func markCompleteAndRecordStats(won: Bool, elapsedTime: TimeInterval, flagCount: Int) -> Bool {
    markCompleteAndRecordStats(for: Date(), won: won, elapsedTime: elapsedTime, flagCount: flagCount)
}
