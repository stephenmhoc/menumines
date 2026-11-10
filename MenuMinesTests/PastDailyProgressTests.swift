import Foundation
import Testing
@testable import MenuMines

// MARK: - Leaving and coming back

/// Serialized because these share UserDefaults and the shared stats store with each other.
@Suite("Past daily progress", .serialized)
@MainActor
struct PastDailyProgressTests {
    // MARK: No lost progress

    @Test("A past daily left for today comes back exactly as it was, timer included")
    func testResumeAfterLeaving() throws {
        let cleanup = setupCleanPastDailyState()
        defer { cleanup() }

        let yesterday = pastSeed(daysAgo: 1)
        let state = freshTodaysDaily()
        state.playPastDay(seed: yesterday)
        try makeOpeningMove(state)
        let flagTarget = try #require(findHiddenCell(in: state))
        state.toggleFlag(row: flagTarget.row, col: flagTarget.col)
        state.select(row: 4, col: 5)
        state.pauseTimer()
        state.elapsedTime = 42

        let board = state.board
        let log = state.playLog
        let clicks = state.clickCount

        state.returnToToday()
        #expect(state.puzzleType == .daily)
        #expect(state.dailySeed == seedFromDate(Date()))
        #expect(state.pastDailySeedsInProgress == [yesterday], "The calendar shows the day as in progress")

        #expect(state.playPastDay(seed: yesterday))

        #expect(state.puzzleType == .pastDaily)
        #expect(state.dailySeed == yesterday)
        #expect(state.status == .playing)
        #expect(state.board == board)
        #expect(state.elapsedTime == 42)
        #expect(state.flagCount == 1)
        #expect(state.playLog == log)
        #expect(state.clickCount == clicks)
        #expect(state.selectedRow == 4)
        #expect(state.selectedCol == 5)
        #expect(state.isPaused, "The clock waits for the panel")
        #expect(!state.canReset, "Coming back to it doesn't unlock reset")

        state.resumeTimer()
        #expect(!state.isPaused)
        state.pauseTimer()
        #expect(state.elapsedTime >= 42, "The clock carries on from where it stopped")
    }

    @Test("A past daily survives quitting and relaunching")
    func testResumeAfterRelaunch() throws {
        let cleanup = setupCleanPastDailyState()
        defer { cleanup() }

        let yesterday = pastSeed(daysAgo: 1)
        let state = freshTodaysDaily()
        state.playPastDay(seed: yesterday)
        try makeOpeningMove(state)
        // What quitting does.
        state.pauseTimer()
        state.elapsedTime = 73
        state.save()
        let board = state.board
        let log = state.playLog

        let relaunched = GameState.restored()
        #expect(relaunched.puzzleType == .daily, "A launch always starts on today")
        #expect(relaunched.dailySeed == seedFromDate(Date()))
        #expect(relaunched.pastDailySeedsInProgress == [yesterday])
        #expect(relaunched.nextMissedDaySeed == yesterday, "A started day is still a missed one")

        #expect(relaunched.playPastDay(seed: yesterday))

        #expect(relaunched.puzzleType == .pastDaily)
        #expect(relaunched.status == .playing)
        #expect(relaunched.board == board)
        #expect(relaunched.elapsedTime == 73)
        #expect(relaunched.playLog == log)
        #expect(!relaunched.canReset)
    }

    @Test("Starting another day keeps the first one's progress")
    func testSeveralDaysInProgress() throws {
        let cleanup = setupCleanPastDailyState()
        defer { cleanup() }

        let yesterday = pastSeed(daysAgo: 1)
        let dayBefore = pastSeed(daysAgo: 2)
        let state = freshTodaysDaily()

        state.playPastDay(seed: yesterday)
        try makeOpeningMove(state)
        let yesterdaysBoard = state.board

        state.playPastDay(seed: dayBefore)
        #expect(state.status == .notStarted)
        try makeOpeningMove(state)
        let dayBeforesBoard = state.board

        #expect(state.pastDailySeedsInProgress == [yesterday, dayBefore])

        state.playPastDay(seed: yesterday)
        #expect(state.board == yesterdaysBoard)
        #expect(state.status == .playing)

        state.playPastDay(seed: dayBefore)
        #expect(state.board == dayBeforesBoard)
        #expect(state.status == .playing)
    }

    @Test("Finishing a past daily clears its saved progress")
    func testProgressIsClearedOnCompletion() async throws {
        let cleanup = setupCleanPastDailyState()
        defer { cleanup() }

        let yesterday = pastSeed(daysAgo: 1)
        let state = freshTodaysDaily()
        state.playPastDay(seed: yesterday)
        try makeOpeningMove(state)
        state.save()
        try #require(GameSnapshot.pastDailySeedsInProgress() == [yesterday])

        try loseGame(state)
        state.save()
        await waitForRecording()

        #expect(GameSnapshot.pastDailySeedsInProgress().isEmpty)
        #expect(state.pastDailySeedsInProgress.isEmpty)
        #expect(GameSnapshot.loadPastDaily(seed: yesterday) == nil)
    }

    @Test("A day's saved progress is only ever a game under way for that day")
    func testSavedProgressIsValidated() {
        let cleanup = setupCleanPastDailyState()
        defer { cleanup() }

        let yesterday = pastSeed(daysAgo: 1)
        let finished = GameSnapshot(
            board: Board(dailySeed: yesterday), status: .won, elapsedTime: 10, flagCount: 0,
            selectedRow: 0, selectedCol: 0, dailySeed: yesterday, puzzleType: .pastDaily
        )
        finished.saveAsPastDaily()
        #expect(GameSnapshot.loadPastDaily(seed: yesterday) == nil)
        #expect(GameSnapshot.pastDailySeedsInProgress().isEmpty, "And it's cleared rather than left behind")

        UserDefaults.standard.set(Data("not a snapshot".utf8), forKey: "gameSnapshot.past.\(yesterday)")
        #expect(GameSnapshot.loadPastDaily(seed: yesterday) == nil)

        let state = freshTodaysDaily()
        #expect(state.playPastDay(seed: yesterday))
        #expect(state.status == .notStarted, "Unreadable progress means a fresh board, not a crash")
    }

    // MARK: Today's game

    @Test("Today's game in progress is there, untouched, after a visit to a past day")
    func testTodaysGameSurvivesVisit() throws {
        let cleanup = setupCleanPastDailyState()
        defer { cleanup() }

        let today = seedFromDate(Date())
        let state = freshTodaysDaily()
        try makeOpeningMove(state)
        state.pauseTimer()
        state.elapsedTime = 17
        let todaysBoard = state.board
        let todaysLog = state.playLog

        state.playPastDay(seed: pastSeed(daysAgo: 1))
        try makeOpeningMove(state)
        state.checkForDailyRollover()
        #expect(state.puzzleType == .pastDaily, "Opening the panel must not discard the past daily")

        state.returnToToday()

        #expect(state.puzzleType == .daily)
        #expect(state.dailySeed == today)
        #expect(state.status == .playing)
        #expect(state.board == todaysBoard)
        #expect(state.playLog == todaysLog)
        #expect(state.elapsedTime == 17)
        #expect(!state.canReset, "Today's reset lock is as it was")
    }

    @Test("Today's game in progress comes back on relaunch even with a past daily under way")
    func testTodaysGameComesBackOnRelaunch() throws {
        let cleanup = setupCleanPastDailyState()
        defer { cleanup() }

        let state = freshTodaysDaily()
        try makeOpeningMove(state)
        let todaysBoard = state.board

        state.playPastDay(seed: pastSeed(daysAgo: 1))
        try makeOpeningMove(state)
        state.pauseTimer()
        state.save()

        for continuousPlay in [true, false] {
            UserDefaults.standard.set(continuousPlay, forKey: Constants.SettingsKeys.continuousPlay)
            let relaunched = GameState.restored()
            #expect(relaunched.puzzleType == .daily)
            #expect(relaunched.status == .playing)
            #expect(relaunched.board == todaysBoard)
        }
    }

    @Test("A finished today is still finished after playing a past day")
    func testFinishedTodaySurvivesVisit() async throws {
        let cleanup = setupCleanPastDailyState()
        defer { cleanup() }

        let today = seedFromDate(Date())
        let state = freshTodaysDaily()
        winGame(state)
        try #require(state.status == .won)
        await waitForRecording()
        let finishedBoard = state.board

        state.playPastDay(seed: pastSeed(daysAgo: 1))
        try loseGame(state)
        await waitForRecording()
        state.returnToToday()

        #expect(state.puzzleType == .daily)
        #expect(state.status == .won)
        #expect(state.board == finishedBoard)
        #expect(isDailyPuzzleComplete(forSeed: today))
        #expect(getStats(forSeed: today)?.won == true, "Losing a past day doesn't change today's result")
        #expect(StatsStore.shared.dailyResults.map(\.dailySeed) == [today])
        #expect(StatsStore.shared.currentStreak == 1)
    }

    @Test("A daily carried over from its own day is left to finish as that day's result")
    func testCarriedOverDailyIsNotRestarted() throws {
        let cleanup = setupCleanPastDailyState()
        defer { cleanup() }

        let yesterday = pastSeed(daysAgo: 1)
        let state = GameState(board: Board(dailySeed: yesterday), dailySeed: yesterday, puzzleType: .daily)
        try makeOpeningMove(state)
        let board = state.board

        #expect(state.playPastDay(seed: yesterday))

        #expect(state.puzzleType == .daily)
        #expect(state.status == .playing)
        #expect(state.board == board)
    }
}
