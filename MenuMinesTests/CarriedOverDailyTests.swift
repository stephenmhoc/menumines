import Foundation
import Testing
@testable import MenuMines

/// A daily started before UTC midnight and still under way afterwards. It's the player's one
/// attempt at that day: it can't be dropped, reset or duplicated as a past daily, and it counts
/// on its day when it's finished.
///
/// Serialized because these share UserDefaults and the shared stats store with each other.
@Suite("Carried-over daily", .serialized)
@MainActor
struct CarriedOverDailyTests {
    /// Yesterday's daily with its opening made, as if it was started just before midnight.
    private func carriedOverDaily() throws -> GameState {
        let yesterday = pastSeed(daysAgo: 1)
        let state = GameState(board: Board(dailySeed: yesterday), dailySeed: yesterday, puzzleType: .daily)
        try makeOpeningMove(state)
        return state
    }

    /// Clears the day stats a finished carried-over daily leaves for its own day.
    private func clearCarriedOverStats() {
        UserDefaults.standard.removeObject(forKey: "dailyStats_\(pastSeed(daysAgo: 1))")
    }

    // MARK: Picking its day

    @Test("Picking a carried-over daily's day after visiting another day puts that game back, not a fresh past daily")
    func testPickingItsDayResumesIt() async throws {
        let cleanup = setupCleanPastDailyState(continuousPlay: false)
        defer {
            cleanup()
            clearCarriedOverStats()
        }

        let yesterday = pastSeed(daysAgo: 1)
        let state = try carriedOverDaily()
        let board = state.board

        #expect(state.playPastDay(seed: pastSeed(daysAgo: 2)))
        #expect(state.pastDailySeedsInProgress.contains(yesterday), "The calendar shows the day as under way")

        #expect(state.playPastDay(seed: yesterday))
        #expect(state.puzzleType == .daily, "It's the day's own game, not a second attempt")
        #expect(state.status == .playing)
        #expect(state.board == board)
        #expect(GameSnapshot.loadPastDaily(seed: yesterday) == nil, "There's never a separate attempt at the same day")

        // The probe from the review: a mine here ends the day's one attempt, as a loss on the day.
        try loseGame(state)
        await waitForRecording()
        #expect(StatsStore.shared.pastDailyResults.isEmpty)
        #expect(StatsStore.shared.dailyResultsBySeed[yesterday]?.won == false)
        #expect(state.playPastDay(seed: yesterday))
        #expect(state.puzzleType == .practice, "With its result in, the day is only a replay")
    }

    @Test("Back to Today from a past day returns to the carried-over daily")
    func testBackToTodayReturnsToIt() throws {
        let cleanup = setupCleanPastDailyState(continuousPlay: true)
        defer { cleanup() }

        let state = try carriedOverDaily()
        let board = state.board

        #expect(state.playPastDay(seed: pastSeed(daysAgo: 3)))
        state.returnToToday()

        #expect(state.puzzleType == .daily)
        #expect(state.dailySeed == pastSeed(daysAgo: 1))
        #expect(state.board == board)
    }

    // MARK: Never dropped

    @Test("A carried-over daily can't be reset, so its day can't be started over")
    func testResetIsLocked() throws {
        let cleanup = setupCleanPastDailyState(continuousPlay: false)
        defer { cleanup() }

        let yesterday = pastSeed(daysAgo: 1)
        let state = try carriedOverDaily()
        let board = state.board

        #expect(!state.canReset)
        state.reset()
        #expect(state.dailySeed == yesterday)
        #expect(state.board == board)
        #expect(state.status == .playing)

        #expect(state.playPastDay(seed: yesterday))
        #expect(state.puzzleType == .daily)
        #expect(state.board == board)
    }

    @Test("Relaunching after midnight with continuous play on keeps the carried-over daily")
    func testContinuousPlayRelaunchKeepsIt() throws {
        let cleanup = setupCleanPastDailyState(continuousPlay: true)
        defer { cleanup() }

        let yesterday = pastSeed(daysAgo: 1)
        let state = try carriedOverDaily()
        state.pauseTimer()
        state.elapsedTime = 37
        state.save()
        let board = state.board

        let relaunched = GameState.restored()
        #expect(relaunched.puzzleType == .daily)
        #expect(relaunched.dailySeed == yesterday)
        #expect(relaunched.status == .playing)
        #expect(relaunched.board == board)
        #expect(relaunched.elapsedTime == 37)
        #expect(!relaunched.canReset)

        // Its day is still that game, from anywhere.
        #expect(relaunched.playPastDay(seed: pastSeed(daysAgo: 2)))
        #expect(relaunched.playPastDay(seed: yesterday))
        #expect(relaunched.puzzleType == .daily)
        #expect(relaunched.board == board)
        #expect(GameSnapshot.loadPastDaily(seed: yesterday) == nil)
    }

    @Test("Relaunching with continuous play off keeps it too, so the rule doesn't depend on the setting")
    func testRelaunchWithContinuousPlayOffKeepsIt() throws {
        let cleanup = setupCleanPastDailyState(continuousPlay: false)
        defer { cleanup() }

        let state = try carriedOverDaily()
        state.pauseTimer()
        state.save()

        let relaunched = GameState.restored()
        #expect(relaunched.puzzleType == .daily)
        #expect(relaunched.dailySeed == pastSeed(daysAgo: 1))
        #expect(relaunched.board == state.board)
    }

    @Test("The day rolling over again doesn't drop a carried-over daily")
    func testRolloverKeepsIt() throws {
        let cleanup = setupCleanPastDailyState(continuousPlay: true)
        defer { cleanup() }

        let state = try carriedOverDaily()
        let board = state.board

        state.dayMayHaveChanged()
        state.checkForDailyRollover()

        #expect(state.puzzleType == .daily)
        #expect(state.board == board)
        #expect(GameSnapshot.loadAnyDay()?.board == board)
    }

    // MARK: Finishing it

    @Test("Finishing a carried-over daily counts on its day, and isn't recorded as played later")
    func testFinishingCountsOnTheDay() async throws {
        let cleanup = setupCleanPastDailyState(continuousPlay: false)
        defer {
            cleanup()
            clearCarriedOverStats()
        }

        let yesterday = pastSeed(daysAgo: 1)
        let state = try carriedOverDaily()
        winGame(state)
        try #require(state.status == .won)
        await waitForRecording()

        #expect(StatsStore.shared.dailyResultsBySeed[yesterday]?.won == true)
        #expect(StatsStore.shared.pastDailyResults.isEmpty)
        #expect(!isDailyPuzzleComplete(), "Today is still to play")
    }
}

// MARK: - Saved after every move

/// What's on disk keeps up with the board for every game that will be recorded, so a crash or
/// a force quit never rolls one back.
@Suite("Recorded games are saved as they're played", .serialized)
@MainActor
struct RecordedProgressSaveTests {
    /// A few moves after the opening: a flag, then another safe cell.
    private func playSomeMoves(_ state: GameState) throws {
        try makeOpeningMove(state)
        let flag = try #require(findHiddenCell(in: state))
        state.toggleFlag(row: flag.row, col: flag.col)
        let safe = try #require(hiddenSafeCell(in: state))
        state.reveal(row: safe.row, col: safe.col)
        try #require(state.status == .playing)
    }

    private func hiddenSafeCell(in state: GameState) -> (row: Int, col: Int)? {
        for row in 0..<Board.rows {
            for col in 0..<Board.cols {
                let cell = state.board.cells[row][col]
                if case .hidden = cell.state, !cell.hasMine { return (row, col) }
            }
        }
        return nil
    }

    @Test("A past daily force-quit after several moves comes back at its last move")
    func testPastDailyAfterSeveralMoves() throws {
        let cleanup = setupCleanPastDailyState()
        defer { cleanup() }

        let yesterday = pastSeed(daysAgo: 1)
        let state = freshTodaysDaily()
        #expect(state.playPastDay(seed: yesterday))
        try playSomeMoves(state)

        // No panel close, no quit: whatever is on disk now is what a relaunch gets.
        let saved = try #require(GamePersistenceCoordinator.restorePastDaily(seed: yesterday))
        #expect(saved.board == state.board)
        #expect(saved.flagCount == 1)
        #expect(saved.clickCount == state.clickCount)
        #expect(saved.playLog == state.playLog)
        #expect(saved.elapsedTime == state.elapsedTime)
    }

    @Test("Today's daily force-quit after its first moves comes back, not as a fresh board")
    func testTodaysDailyAfterSeveralMoves() throws {
        let cleanup = setupCleanPastDailyState(continuousPlay: false)
        defer { cleanup() }

        let state = freshTodaysDaily()
        try makeOpeningMove(state)
        #expect(GameSnapshot.load()?.board == state.board, "Saved from the first reveal")

        let flag = try #require(findHiddenCell(in: state))
        state.toggleFlag(row: flag.row, col: flag.col)
        let relaunched = GameState.restored()
        #expect(relaunched.status == .playing)
        #expect(relaunched.board == state.board)
        #expect(relaunched.flagCount == 1)
        #expect(!relaunched.canReset)

        // Only the finished game ever goes in the daily namespace.
        let daily = GameSnapshot.withStorageKey(GameSnapshot.dailyNamespace) { GameSnapshot.loadAnyDay() }
        #expect(daily == nil)
    }

    @Test("Today's daily is saved with continuous play on too")
    func testTodaysDailyWithContinuousPlay() throws {
        let cleanup = setupCleanPastDailyState(continuousPlay: true)
        defer { cleanup() }

        let state = freshTodaysDaily()
        try playSomeMoves(state)

        let relaunched = GameState.restored()
        #expect(relaunched.puzzleType == .daily)
        #expect(relaunched.board == state.board)
    }

    @Test("A carried-over daily is saved after every move")
    func testCarriedOverDailyAfterSeveralMoves() throws {
        let cleanup = setupCleanPastDailyState(continuousPlay: false)
        defer { cleanup() }

        let yesterday = pastSeed(daysAgo: 1)
        let state = GameState(board: Board(dailySeed: yesterday), dailySeed: yesterday, puzzleType: .daily)
        try playSomeMoves(state)

        let saved = try #require(GameSnapshot.loadAnyDay())
        #expect(saved.dailySeed == yesterday)
        #expect(saved.puzzleType == .daily)
        #expect(saved.board == state.board)
    }

    @Test("Random games and replays still aren't saved")
    func testUnrecordedGamesAreNotSaved() throws {
        let cleanup = setupCleanPastDailyState()
        defer { cleanup() }

        let random = GameState(board: Board(seed: 99), dailySeed: GameState.randomPuzzleSeed(), puzzleType: .random)
        random.reveal(row: 4, col: 4)
        #expect(GameSnapshot.loadAnyDay() == nil)

        let replay = freshTodaysDaily()
        replay.startPractice(seed: pastSeed(daysAgo: 5))
        try makeOpeningMove(replay)
        #expect(GameSnapshot.loadAnyDay() == nil)
        #expect(GameSnapshot.pastDailySeedsInProgress().isEmpty)
    }
}

// MARK: - A random game left for a past day

@Suite("Random game kept for Back to Today", .serialized)
@MainActor
struct ParkedRandomGameTests {
    private func startedRandom() -> GameState {
        let state = GameState(board: Board(seed: 4242), dailySeed: GameState.randomPuzzleSeed(), puzzleType: .random)
        state.reveal(row: 4, col: 4)
        return state
    }

    @Test("A random game under way is there again after visiting a past day")
    func testRandomComesBack() throws {
        let cleanup = setupCleanPastDailyState(continuousPlay: true)
        defer { cleanup() }
        UserDefaults.standard.set(seedFromDate(Date()), forKey: "dailyCompletionSeed")

        let state = startedRandom()
        try #require(state.status == .playing)
        let board = state.board
        let seed = state.dailySeed

        #expect(state.playPastDay(seed: pastSeed(daysAgo: 1)))
        #expect(state.playPastDay(seed: pastSeed(daysAgo: 2)))
        state.returnToToday()

        #expect(state.puzzleType == .random)
        #expect(state.dailySeed == seed)
        #expect(state.board == board)
        #expect(state.status == .playing)
        #expect(GameSnapshot.loadAnyDay() == nil, "Random games are still never written to disk")
    }

    @Test("Today's puzzle comes first once it's a new day, and with continuous play off")
    func testTodayComesFirst() throws {
        let cleanup = setupCleanPastDailyState(continuousPlay: true)
        defer { cleanup() }

        // Today not done: a new day has arrived since the random game was dealt.
        let state = startedRandom()
        #expect(state.playPastDay(seed: pastSeed(daysAgo: 1)))
        state.returnToToday()
        #expect(state.puzzleType == .daily)
        #expect(state.dailySeed == seedFromDate(Date()))

        // Continuous play turned off while away.
        UserDefaults.standard.set(seedFromDate(Date()), forKey: "dailyCompletionSeed")
        let other = startedRandom()
        #expect(other.playPastDay(seed: pastSeed(daysAgo: 1)))
        UserDefaults.standard.set(false, forKey: Constants.SettingsKeys.continuousPlay)
        other.returnToToday()
        #expect(other.puzzleType != .random)
    }
}

// MARK: - The clock

@Suite("Resuming the clock", .serialized)
@MainActor
struct ResumeTimerTests {
    @Test("Resuming a clock that's already running doesn't wind it back to the last second shown")
    func testResumeIsIdempotent() throws {
        let cleanup = setupCleanPastDailyState()
        defer { cleanup() }

        let state = GameState(board: Board(seed: 7), dailySeed: GameState.randomPuzzleSeed(), puzzleType: .random)
        state.reveal(row: 4, col: 4)
        try #require(state.status == .playing)

        runLoopFor(seconds: 1.6)
        state.resumeTimer()
        state.pauseTimer()

        #expect(state.elapsedTime >= 1.5)
    }
}
