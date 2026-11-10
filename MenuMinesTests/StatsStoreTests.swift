import Foundation
import Testing
@testable import MenuMines

@Suite("StatsStore Tests", .serialized)
struct StatsStoreTests {

    // MARK: - iCloud Merge

    @MainActor
    @Test("Merging pulls in days this device has never seen")
    func testMergeAddsUnseenDays() {
        let store = StatsStore.forTesting(with: [
            GameResult(won: true, elapsedTime: 60, dailySeed: 20260101, puzzleType: .daily)
        ])

        let changed = store.merge(dailyResults: [
            GameResult(won: false, elapsedTime: 90, dailySeed: 20260102, puzzleType: .daily)
        ])

        #expect(changed)
        #expect(store.dailyGamesPlayed == 2)
    }

    @MainActor
    @Test("A day this device already has is not duplicated")
    func testMergeIgnoresKnownDays() {
        let existing = GameResult(won: true, elapsedTime: 60, dailySeed: 20260101, puzzleType: .daily)
        let store = StatsStore.forTesting(with: [existing])

        let changed = store.merge(dailyResults: [
            GameResult(won: false, elapsedTime: 999, dailySeed: 20260101, puzzleType: .daily)
        ])

        #expect(!changed)
        #expect(store.dailyGamesPlayed == 1)
        #expect(store.dailyWins == 1, "The local result should win, not be overwritten by a later sync")
    }

    @MainActor
    @Test("Random puzzles are not accepted from another device")
    func testMergeRejectsRandomResults() {
        let store = StatsStore.forTesting(with: [])

        let changed = store.merge(dailyResults: [
            GameResult(won: true, elapsedTime: 30, dailySeed: -12345, puzzleType: .random)
        ])

        #expect(!changed, "Random puzzles are per-machine, so syncing them would double-count")
        #expect(store.gamesPlayed == 0)
    }

    @MainActor
    @Test("Merged days count toward streaks")
    func testMergedDaysExtendStreaks() {
        let store = StatsStore.forTesting(with: [])
        store.merge(dailyResults: [
            GameResult(won: true, elapsedTime: 60, dailySeed: 20260101, puzzleType: .daily),
            GameResult(won: true, elapsedTime: 60, dailySeed: 20260102, puzzleType: .daily),
            GameResult(won: true, elapsedTime: 60, dailySeed: 20260103, puzzleType: .daily)
        ])

        #expect(store.longestStreak == 3, "A streak earned on another Mac should carry over")
    }

    private let testResultsKey = "gameResults"

    private func clearStats() {
        UserDefaults.standard.removeObject(forKey: testResultsKey)
    }

    private func makeResult(
        won: Bool,
        elapsedTime: TimeInterval = 120,
        dailySeed: Int64 = 20260125,
        completedAt: Date = Date(),
        puzzleType: PuzzleType = .daily
    ) -> GameResult {
        GameResult(
            won: won,
            elapsedTime: elapsedTime,
            dailySeed: dailySeed,
            completedAt: completedAt,
            puzzleType: puzzleType
        )
    }

    private func date(_ seed: Int64) -> Date {
        dateFromSeed(seed) ?? Date(timeIntervalSince1970: 0)
    }

    // MARK: - Empty State

    @Test("Empty store has no games played")
    func testEmptyStoreHasNoGamesPlayed() {
        let store = StatsStore.forTesting()
        #expect(store.gamesPlayed == 0)
        #expect(store.wins == 0)
        #expect(store.winRate == nil)
        #expect(store.bestTime == nil)
        #expect(store.averageTime == nil)
        #expect(store.trackedSince == nil)
        #expect(!store.hasResults)
        #expect(store.currentStreak == 0)
        #expect(store.longestStreak == 0)
    }

@Test("Recent results name the puzzle, not the local day it was finished")
    func testRecentResultsNameThePuzzle() {
        let result = makeResult(won: false, dailySeed: 20260424, completedAt: Date(timeIntervalSince1970: 0))
        let locale = Locale(identifier: "en_US")

        #expect(StatsRecentResults.formattedDate(for: result, locale: locale) == "Apr 24, 2026")
    }

    // MARK: - Games Played

    @Test("Games played counts all results")
    func testGamesPlayedCountsAllResults() {
        let store = StatsStore.forTesting(with: [
            makeResult(won: true),
            makeResult(won: false),
            makeResult(won: true)
        ])
        #expect(store.gamesPlayed == 3)
    }

    // MARK: - Wins

    @Test("Wins counts only winning games")
    func testWinsCountsOnlyWinningGames() {
        let store = StatsStore.forTesting(with: [
            makeResult(won: true),
            makeResult(won: false),
            makeResult(won: true),
            makeResult(won: false)
        ])
        #expect(store.wins == 2)
    }

    // MARK: - Win Rate

    @Test("Win rate calculates correctly")
    func testWinRateCalculatesCorrectly() {
        let store = StatsStore.forTesting(with: [
            makeResult(won: true),
            makeResult(won: true),
            makeResult(won: false),
            makeResult(won: false)
        ])
        #expect(store.winRate == 50)
    }

    @Test("Win rate rounds to whole percent")
    func testWinRateRoundsToWholePercent() {
        let store = StatsStore.forTesting(with: [
            makeResult(won: true),
            makeResult(won: true),
            makeResult(won: false)
        ])
        // 2/3 = 66.67% -> rounds to 67%
        #expect(store.winRate == 67)
    }

    @Test("Win rate is 100% when all wins")
    func testWinRateIs100WhenAllWins() {
        let store = StatsStore.forTesting(with: [
            makeResult(won: true),
            makeResult(won: true)
        ])
        #expect(store.winRate == 100)
    }

    @Test("Win rate is 0% when no wins")
    func testWinRateIs0WhenNoWins() {
        let store = StatsStore.forTesting(with: [
            makeResult(won: false),
            makeResult(won: false)
        ])
        #expect(store.winRate == 0)
    }

    // MARK: - Best Time

    @Test("Best time is minimum of wins only")
    func testBestTimeIsMinimumOfWinsOnly() {
        let store = StatsStore.forTesting(with: [
            makeResult(won: true, elapsedTime: 120),
            makeResult(won: false, elapsedTime: 50),  // Should be ignored
            makeResult(won: true, elapsedTime: 90),
            makeResult(won: true, elapsedTime: 150)
        ])
        #expect(store.bestTime == 90)
    }

    @Test("Best time is nil when no wins")
    func testBestTimeIsNilWhenNoWins() {
        let store = StatsStore.forTesting(with: [
            makeResult(won: false, elapsedTime: 50)
        ])
        #expect(store.bestTime == nil)
    }

    // MARK: - Average Time

    @Test("Average time is calculated from wins only")
    func testAverageTimeIsCalculatedFromWinsOnly() {
        let store = StatsStore.forTesting(with: [
            makeResult(won: true, elapsedTime: 100),
            makeResult(won: false, elapsedTime: 50),  // Should be ignored
            makeResult(won: true, elapsedTime: 200)
        ])
        #expect(store.averageTime == 150)
    }

    @Test("Average time is nil when no wins")
    func testAverageTimeIsNilWhenNoWins() {
        let store = StatsStore.forTesting(with: [
            makeResult(won: false, elapsedTime: 100)
        ])
        #expect(store.averageTime == nil)
    }

    // MARK: - Tracked Since

    @Test("Tracked since is earliest result date")
    func testTrackedSinceIsEarliestResultDate() {
        let earliest = Date(timeIntervalSince1970: 1000)
        let middle = Date(timeIntervalSince1970: 2000)
        let latest = Date(timeIntervalSince1970: 3000)

        let store = StatsStore.forTesting(with: [
            makeResult(won: true, completedAt: latest),
            makeResult(won: false, completedAt: earliest),
            makeResult(won: true, completedAt: middle)
        ])
        #expect(store.trackedSince == earliest)
    }

    // MARK: - Streaks

    @Test("Current streak counts consecutive days ending at most recent completion")
    func testCurrentStreakCountsMostRecentRun() {
        let store = StatsStore.forTesting(with: [
            makeResult(won: true, dailySeed: 20260125),
            makeResult(won: false, dailySeed: 20260126),
            makeResult(won: true, dailySeed: 20260128)
        ])

        #expect(store.currentStreak(asOf: date(20260129)) == 1)
        #expect(store.longestStreak == 2)
    }

    @Test("Longest streak counts the maximum consecutive run")
    func testLongestStreakCountsMaximumRun() {
        let store = StatsStore.forTesting(with: [
            makeResult(won: true, dailySeed: 20260125),
            makeResult(won: true, dailySeed: 20260126),
            makeResult(won: false, dailySeed: 20260127),
            makeResult(won: true, dailySeed: 20260129)
        ])

        #expect(store.currentStreak(asOf: date(20260130)) == 1)
        #expect(store.longestStreak == 3)
    }

    @Test("Streaks count across month boundaries")
    func testStreaksCountAcrossMonthBoundaries() {
        let store = StatsStore.forTesting(with: [
            makeResult(won: true, dailySeed: 20260131),
            makeResult(won: true, dailySeed: 20260201)
        ])

        #expect(store.currentStreak(asOf: date(20260201)) == 2)
        #expect(store.longestStreak == 2)
    }

    @Test("Current streak is zero when latest completion is stale")
    func testCurrentStreakIsZeroWhenLatestCompletionIsStale() {
        let store = StatsStore.forTesting(with: [
            makeResult(won: true, dailySeed: 20260125),
            makeResult(won: true, dailySeed: 20260126)
        ])

        #expect(store.currentStreak(asOf: date(20260201)) == 0)
        #expect(store.longestStreak == 2)
    }

    @Test("Daily history helpers expose daily-only result data")
    func testDailyHistoryHelpers() {
        let store = StatsStore.forTesting(with: [
            makeResult(won: true, elapsedTime: 100, dailySeed: 20260125),
            makeResult(won: false, elapsedTime: 50, dailySeed: 20260126),
            makeResult(won: true, elapsedTime: 80, dailySeed: -10, puzzleType: .random)
        ])

        #expect(store.dailyResultsBySeed[20260125]?.won == true)
        #expect(store.dailyResultsBySeed[20260126]?.won == false)
        #expect(store.dailyBestTime == 100)
        #expect(store.dailyAverageTime == 100)
        #expect(store.recentDailyResults.map(\.dailySeed) == [20260126, 20260125])
    }

    @Test("Daily completion rate counts tracked UTC days")
    func testDailyCompletionRateCountsTrackedDays() {
        let store = StatsStore.forTesting(with: [
            makeResult(won: true, dailySeed: 20260125),
            makeResult(won: false, dailySeed: 20260127)
        ])

        #expect(store.dailyCompletionRate(asOf: date(20260128)) == 50)
    }

    // MARK: - Recording

    @Test("Recording a result adds it to the store")
    @MainActor
    func testRecordingResultAddsToStore() {
        clearStats()
        let store = StatsStore.forTesting()
        let result = makeResult(won: true)

        store.record(result)

        #expect(store.gamesPlayed == 1)
        #expect(store.wins == 1)
    }

    // MARK: - Deduplication

    @Test("Recording with same dailySeed replaces existing result")
    @MainActor
    func testRecordDeduplicatesByDailySeed() {
        clearStats()
        let store = StatsStore.forTesting()
        let seed: Int64 = 20260125

        // Record first result for today
        let result1 = makeResult(won: true, elapsedTime: 100, dailySeed: seed)
        store.record(result1)
        #expect(store.gamesPlayed == 1)
        #expect(store.bestTime == 100)

        // Record second result with same seed - should be ignored
        let result2 = makeResult(won: true, elapsedTime: 50, dailySeed: seed)
        store.record(result2)
        #expect(store.gamesPlayed == 1, "Should still have 1 game, not 2")
        #expect(store.bestTime == 100, "Should keep first result's time")
    }

    @Test("Recording with different dailySeed adds new result")
    @MainActor
    func testRecordAllowsDifferentSeeds() {
        clearStats()
        let store = StatsStore.forTesting()

        // Record for different days
        let result1 = makeResult(won: true, elapsedTime: 100, dailySeed: 20260125)
        let result2 = makeResult(won: true, elapsedTime: 80, dailySeed: 20260126)
        store.record(result1)
        store.record(result2)

        #expect(store.gamesPlayed == 2, "Should have 2 games from different days")
        #expect(store.bestTime == 80, "Best time should be from faster game")
    }

    // MARK: - Reset

    @Test("Reset clears all results")
    @MainActor
    func testResetClearsAllResults() {
        let store = StatsStore.forTesting(with: [
            makeResult(won: true),
            makeResult(won: false)
        ])

        store.reset()

        #expect(store.gamesPlayed == 0)
        #expect(!store.hasResults)
    }

    // MARK: - Persistence

    @Test("Stats persist to UserDefaults")
    @MainActor
    func testStatsPersistToUserDefaults() {
        clearStats()
        let store = StatsStore.forTesting()
        let result = makeResult(won: true, elapsedTime: 100)

        store.record(result)

        guard let data = UserDefaults.standard.data(forKey: testResultsKey) else {
            Issue.record("Expected data to be saved to UserDefaults")
            return
        }

        guard let decoded = try? JSONDecoder().decode([GameResult].self, from: data) else {
            Issue.record("Expected data to be decodable")
            return
        }

        #expect(decoded.count == 1)
        #expect(decoded[0].won == true)
        #expect(decoded[0].elapsedTime == 100)
    }
}
