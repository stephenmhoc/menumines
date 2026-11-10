import Foundation
import Testing
@testable import MenuMines

// MARK: - Recording a finished past daily

/// Serialized because these share UserDefaults and the shared stats store with each other.
@Suite("Past daily recording", .serialized)
@MainActor
struct PastDailyRecordingTests {
    @Test("Winning a past daily records one result for that day")
    func testWinIsRecordedOnce() async throws {
        let cleanup = setupCleanPastDailyState()
        defer { cleanup() }

        let yesterday = pastSeed(daysAgo: 1)
        let state = freshTodaysDaily()
        state.playPastDay(seed: yesterday)
        winGame(state)
        try #require(state.status == .won)
        await waitForRecording()

        let recorded = StatsStore.shared.pastDailyResults
        #expect(recorded.count == 1)
        #expect(recorded.first?.dailySeed == yesterday)
        #expect(recorded.first?.won == true)
        #expect(recorded.first?.puzzleType == .pastDaily)
        #expect(StatsStore.shared.pastDailyGamesPlayed == 1)
        #expect(StatsStore.shared.pastDailyWins == 1)
        #expect(StatsStore.shared.hasDailyResult(forSeed: yesterday))
    }

    @Test("Losing a past daily records one result for that day")
    func testLossIsRecordedOnce() async throws {
        let cleanup = setupCleanPastDailyState()
        defer { cleanup() }

        let yesterday = pastSeed(daysAgo: 1)
        let state = freshTodaysDaily()
        state.playPastDay(seed: yesterday)
        try makeOpeningMove(state)
        try loseGame(state)
        await waitForRecording()

        #expect(StatsStore.shared.pastDailyResults.map(\.dailySeed) == [yesterday])
        #expect(StatsStore.shared.pastDailyResults.first?.won == false)
        #expect(StatsStore.shared.pastDailyGamesPlayed == 1)
        #expect(StatsStore.shared.pastDailyWins == 0)
    }

    @Test("A day that's been played as a past daily is a replay from then on, and records nothing more")
    func testSecondPlayIsUnrecordedPractice() async throws {
        let cleanup = setupCleanPastDailyState()
        defer { cleanup() }

        let yesterday = pastSeed(daysAgo: 1)
        let state = freshTodaysDaily()
        state.playPastDay(seed: yesterday)
        try loseGame(state)
        await waitForRecording()
        let first = try #require(StatsStore.shared.pastDailyResults.first)

        state.returnToToday()
        #expect(state.playPastDay(seed: yesterday))
        #expect(state.puzzleType == .practice, "The day has its result, so this is a replay")
        winGame(state)
        try #require(state.status == .won)
        await waitForRecording()

        #expect(StatsStore.shared.pastDailyResults == [first], "A replay can't turn the loss into a win")
        #expect(StatsStore.shared.results.isEmpty)
    }

    @Test("Picking the day again straight after finishing it is a replay, before the result has even been stored")
    func testReplayRightAfterFinishing() async throws {
        let cleanup = setupCleanPastDailyState()
        defer { cleanup() }

        let yesterday = pastSeed(daysAgo: 1)
        let state = freshTodaysDaily()
        state.playPastDay(seed: yesterday)
        try loseGame(state)

        // No waiting: the result is still on its way to the store.
        #expect(state.nextMissedDaySeed != yesterday, "The day just finished isn't offered again")
        #expect(state.playPastDay(seed: yesterday))
        #expect(state.puzzleType == .practice)

        await waitForRecording()
        #expect(StatsStore.shared.pastDailyResults.count == 1)
    }

    @Test("A past daily never touches streaks, on-the-day stats or today's completion")
    func testResultStaysOutOfDailyStats() async throws {
        let cleanup = setupCleanPastDailyState()
        defer { cleanup() }

        let today = seedFromDate(Date())
        let yesterday = pastSeed(daysAgo: 1)
        let state = freshTodaysDaily()
        state.playPastDay(seed: yesterday)
        winGame(state)
        try #require(state.status == .won)
        await waitForRecording()

        let store = StatsStore.shared
        #expect(store.results.isEmpty, "All-games stats don't count past dailies")
        #expect(store.gamesPlayed == 0)
        #expect(store.dailyResults.isEmpty)
        #expect(store.dailyResultsBySeed[yesterday] == nil)
        #expect(store.dailyGamesPlayed == 0)
        #expect(store.dailyWins == 0)
        #expect(store.dailyBestTime == nil)
        #expect(store.dailyCompletionRate == nil)
        #expect(store.recentDailyResults.isEmpty)
        #expect(store.currentStreak == 0, "Yesterday played today doesn't start a streak")
        #expect(store.longestStreak == 0)

        #expect(!isDailyPuzzleComplete(forSeed: today))
        #expect(!isDailyPuzzleComplete(forSeed: yesterday))
        #expect(getStats(forSeed: yesterday) == nil)
        #expect(!hasStatsBeenRecorded(forSeed: yesterday))
        #expect(GameSnapshot.withStorageKey(GameSnapshot.dailyNamespace) { GameSnapshot.loadAnyDay() } == nil)
    }

    @Test("A past daily can't repair a streak broken by the day it fills in")
    func testStreakIsNotRepaired() async throws {
        let cleanup = setupCleanPastDailyState()
        defer { cleanup() }

        // Played two days ago and today, missed yesterday.
        let afterReset = Date().addingTimeInterval(60)
        let today = seedFromDate(Date())
        StatsStore.shared.merge(dailyResults: [
            onTheDayResult(pastSeed(daysAgo: 2), at: afterReset),
            onTheDayResult(today, at: afterReset)
        ])
        try #require(StatsStore.shared.currentStreak == 1)
        try #require(StatsStore.shared.longestStreak == 1)

        let state = freshTodaysDaily()
        #expect(state.playPastDay(seed: pastSeed(daysAgo: 1)))
        winGame(state)
        try #require(state.status == .won)
        await waitForRecording()

        #expect(StatsStore.shared.pastDailyGamesPlayed == 1)
        #expect(StatsStore.shared.currentStreak == 1)
        #expect(StatsStore.shared.longestStreak == 1)
        #expect(StatsStore.shared.dailyGamesPlayed == 2)
    }

    @Test("Nothing a past daily writes can be read by a version that doesn't know the type")
    func testOlderVersionsNeverSeeThePastDailyType() async throws {
        let cleanup = setupCleanPastDailyState()
        defer { cleanup() }

        let state = freshTodaysDaily()
        state.playPastDay(seed: pastSeed(daysAgo: 2))
        try makeOpeningMove(state)
        state.save()
        state.playPastDay(seed: pastSeed(daysAgo: 1))
        winGame(state)
        await waitForRecording()
        state.save()

        // The keys versions up to 1.0.22 read.
        for key in ["gameSnapshot", "gameSnapshot.daily", "gameResults"] {
            let stored = UserDefaults.standard.data(forKey: key).flatMap { String(data: $0, encoding: .utf8) } ?? ""
            #expect(!stored.contains("pastDaily"), "\(key) would fail to decode on an older version")
        }
        #expect(UserDefaults.standard.data(forKey: "pastDailyResults") != nil)
    }
}
