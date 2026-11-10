import Foundation
import Testing
@testable import MenuMines

// MARK: - Playing a past day

/// Serialized because these share UserDefaults and the shared stats store with each other.
@Suite("Past daily play", .serialized)
@MainActor
struct PastDailyPlayTests {
    @Test("An unplayed past day starts as a past daily on that day's own board")
    func testStartsPastDaily() throws {
        let cleanup = setupCleanPastDailyState()
        defer { cleanup() }

        let yesterday = pastSeed(daysAgo: 1)
        let state = freshTodaysDaily()

        #expect(state.playPastDay(seed: yesterday))

        #expect(state.puzzleType == .pastDaily)
        #expect(state.dailySeed == yesterday)
        #expect(state.status == .notStarted)
        #expect(state.elapsedTime == 0)
        #expect(state.board == Board(dailySeed: yesterday))
        let opening = Board.openingCell(forSeed: yesterday)
        #expect(state.startHint?.row == opening.row)
        #expect(state.startHint?.col == opening.col)
    }

    @Test("Launch day can be played, and the day before it can't")
    func testLaunchBound() {
        let cleanup = setupCleanPastDailyState()
        defer { cleanup() }

        let state = freshTodaysDaily()
        let todaysBoard = state.board

        #expect(!state.playPastDay(seed: 2026_01_30))
        #expect(!state.playPastDay(seed: 2020_01_01))
        #expect(state.puzzleType == .daily)
        #expect(state.board == todaysBoard)

        #expect(state.playPastDay(seed: DailyHistory.launchSeed))
        #expect(state.puzzleType == .pastDaily)
        #expect(state.dailySeed == 2026_01_31)
    }

    @Test("Today, the future and things that aren't dates are refused")
    func testUnavailableDaysAreRefused() {
        let cleanup = setupCleanPastDailyState()
        defer { cleanup() }

        let state = freshTodaysDaily()
        let today = seedFromDate(Date())

        #expect(!state.playPastDay(seed: today))
        #expect(!state.playPastDay(seed: seedFromDate(Date().addingTimeInterval(86_400))))
        #expect(!state.playPastDay(seed: 2026_02_31))
        #expect(!state.playPastDay(seed: -42))

        #expect(state.puzzleType == .daily)
        #expect(state.dailySeed == today)
    }

    @Test("A past daily is played by the daily's rules: a mine is a loss and no mine moves")
    func testNoMineRelocation() throws {
        let cleanup = setupCleanPastDailyState()
        defer { cleanup() }

        let yesterday = pastSeed(daysAgo: 1)
        let mines = minePositions(Board(dailySeed: yesterday))

        let safe = freshTodaysDaily()
        safe.playPastDay(seed: yesterday)
        // Not the marked cell, and right beside a mine if there is one to find.
        let target = try #require(findSafeCell(in: safe.board))
        safe.reveal(row: target.row, col: target.col)
        #expect(minePositions(safe.board) == mines, "The first click must not move a mine")

        clearPastDailyProgress()
        let unlucky = freshTodaysDaily()
        unlucky.playPastDay(seed: yesterday)
        try loseGame(unlucky)
        #expect(minePositions(unlucky.board) == mines, "Opening a mine first is a loss, not a rescue")
    }

    @Test("Flags can go down before the first reveal, and don't start anything")
    func testFlagsBeforeFirstReveal() throws {
        let cleanup = setupCleanPastDailyState()
        defer { cleanup() }

        let yesterday = pastSeed(daysAgo: 1)
        let state = freshTodaysDaily()
        state.playPastDay(seed: yesterday)
        state.toggleFlag(row: 0, col: 0)

        #expect(state.status == .notStarted)
        #expect(state.flagCount == 1)
        #expect(GameSnapshot.pastDailySeedsInProgress().isEmpty, "Nothing is kept until a cell is opened")
    }

    // MARK: No free retries

    @Test("A past daily can't be reset once its first cell is revealed")
    func testNoResetOnceStarted() throws {
        let cleanup = setupCleanPastDailyState()
        defer { cleanup() }

        let state = freshTodaysDaily()
        state.playPastDay(seed: pastSeed(daysAgo: 1))
        #expect(state.canReset, "Nothing has been revealed, so there's nothing to protect")

        try makeOpeningMove(state)
        let board = state.board
        let log = state.playLog

        #expect(!state.canReset)
        state.reset()

        #expect(state.puzzleType == .pastDaily)
        #expect(state.status == .playing)
        #expect(state.board == board)
        #expect(state.playLog == log)
    }

    @Test("The reset lock is the same with continuous play off")
    func testNoResetWithContinuousPlayOff() throws {
        let cleanup = setupCleanPastDailyState(continuousPlay: false)
        defer { cleanup() }

        let state = freshTodaysDaily()
        state.playPastDay(seed: pastSeed(daysAgo: 1))
        try makeOpeningMove(state)

        #expect(!state.canReset)
    }

    @Test("Resetting before the first reveal only takes the flags off")
    func testResetBeforeStarting() {
        let cleanup = setupCleanPastDailyState()
        defer { cleanup() }

        let yesterday = pastSeed(daysAgo: 1)
        let state = freshTodaysDaily()
        state.playPastDay(seed: yesterday)
        state.toggleFlag(row: 0, col: 0)
        state.reset()

        #expect(state.puzzleType == .pastDaily, "Still the recorded game")
        #expect(state.dailySeed == yesterday)
        #expect(state.flagCount == 0)
        #expect(state.board == Board(dailySeed: yesterday))
    }

    @Test("Picking the day again while it's on the board doesn't restart it")
    func testPickingTheSameDayDoesNotRestart() throws {
        let cleanup = setupCleanPastDailyState()
        defer { cleanup() }

        let yesterday = pastSeed(daysAgo: 1)
        let state = freshTodaysDaily()
        state.playPastDay(seed: yesterday)
        try makeOpeningMove(state)
        let board = state.board

        #expect(state.playPastDay(seed: yesterday))

        #expect(state.puzzleType == .pastDaily)
        #expect(state.status == .playing)
        #expect(state.board == board)
    }

    @Test("Resetting a finished past daily replays its board without recording")
    func testResetAfterFinishingIsAReplay() async throws {
        let cleanup = setupCleanPastDailyState()
        defer { cleanup() }

        let yesterday = pastSeed(daysAgo: 1)
        let state = freshTodaysDaily()
        state.playPastDay(seed: yesterday)
        try loseGame(state)
        await waitForRecording()

        #expect(state.canReset)
        state.reset()

        #expect(state.puzzleType == .practice)
        #expect(state.dailySeed == yesterday)
        #expect(state.status == .notStarted)
    }

    @Test("The first reveal is saved at once, so quitting without warning isn't a retry")
    func testFirstRevealIsSavedImmediately() throws {
        let cleanup = setupCleanPastDailyState()
        defer { cleanup() }

        let yesterday = pastSeed(daysAgo: 1)
        let state = freshTodaysDaily()
        state.playPastDay(seed: yesterday)
        try makeOpeningMove(state)
        let board = state.board

        // No save, as if the app had been killed. A new launch starts on today.
        let relaunched = GameState.restored()
        #expect(relaunched.pastDailySeedsInProgress == [yesterday])
        relaunched.playPastDay(seed: yesterday)

        #expect(relaunched.puzzleType == .pastDaily)
        #expect(relaunched.status == .playing)
        #expect(relaunched.board == board)
    }
}
