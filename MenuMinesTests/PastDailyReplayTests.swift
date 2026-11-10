import Foundation
import Testing
@testable import MenuMines

// MARK: - Days that already have a result, and the offer of one that doesn't

/// Serialized because these share UserDefaults and the shared stats store with each other.
@Suite("Past daily replays and offers", .serialized)
@MainActor
struct PastDailyReplayTests {
    // MARK: Days already played

    @Test("A day played on the day is an unrecorded replay")
    func testDayPlayedOnTheDayIsPractice() async throws {
        let cleanup = setupCleanPastDailyState()
        defer { cleanup() }

        let yesterday = pastSeed(daysAgo: 1)
        let onTheDay = onTheDayResult(yesterday, won: false, at: Date().addingTimeInterval(60))
        StatsStore.shared.merge(dailyResults: [onTheDay])

        let state = freshTodaysDaily()
        #expect(state.playPastDay(seed: yesterday))
        #expect(state.puzzleType == .practice)
        #expect(state.canReset, "A replay can be restarted freely")

        winGame(state)
        try #require(state.status == .won)
        await waitForRecording()

        #expect(StatsStore.shared.pastDailyResults.isEmpty)
        #expect(StatsStore.shared.dailyResults == [onTheDay])
    }

    @Test("Progress saved before another Mac finished the day is dropped, and the day becomes a replay")
    func testSyncedResultEndsSavedProgress() throws {
        let cleanup = setupCleanPastDailyState()
        defer { cleanup() }

        let yesterday = pastSeed(daysAgo: 1)
        let state = freshTodaysDaily()
        state.playPastDay(seed: yesterday)
        try makeOpeningMove(state)
        state.returnToToday()
        try #require(state.pastDailySeedsInProgress == [yesterday])

        StatsStore.shared.merge(pastDailyResults: [pastDailyResult(yesterday, at: Date().addingTimeInterval(60))])

        #expect(state.playPastDay(seed: yesterday))
        #expect(state.puzzleType == .practice)
        #expect(state.status == .notStarted)
        #expect(state.pastDailySeedsInProgress.isEmpty)
    }

    @Test("A past daily finished after another Mac's result arrived doesn't replace it")
    func testResultFromAnotherMacStands() async throws {
        let cleanup = setupCleanPastDailyState()
        defer { cleanup() }

        let yesterday = pastSeed(daysAgo: 1)
        let state = freshTodaysDaily()
        state.playPastDay(seed: yesterday)
        try makeOpeningMove(state)

        // Dated ahead of the reset this test started with.
        let arrived = pastDailyResult(yesterday, won: false, at: Date().addingTimeInterval(1))
        #expect(StatsStore.shared.merge(pastDailyResults: [arrived]))

        winGame(state)
        try #require(state.status == .won)
        await waitForRecording()

        #expect(StatsStore.shared.pastDailyResults == [arrived])
    }

    @Test("Continuous play is unchanged: reset after the daily still deals a random board")
    func testContinuousPlayStillDealsRandomBoards() async throws {
        let cleanup = setupCleanPastDailyState(continuousPlay: true)
        defer { cleanup() }

        let state = freshTodaysDaily()
        winGame(state)
        try #require(state.status == .won)
        await waitForRecording()

        #expect(state.canReset)
        state.reset()
        #expect(state.puzzleType == .random, "And reset does what it always did")

        // From a random board, a past day is one step away and today is still done.
        #expect(state.playPastDay(seed: pastSeed(daysAgo: 1)))
        #expect(state.puzzleType == .pastDaily)
        state.returnToToday()
        #expect(state.puzzleType == .daily)
        #expect(state.status == .won)
    }
}
