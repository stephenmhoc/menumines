import Foundation
import Testing
@testable import MenuMines

/// The reset command is named for what it does, so the name has to follow `reset()`.
@Suite("Reset action", .serialized)
@MainActor
struct ResetActionTests {
    @Test("Today's puzzle before the first reveal is restarted, and stays today's")
    func todayRestarts() {
        let cleanup = setupCleanPastDailyState(continuousPlay: true)
        defer { cleanup() }

        let state = freshTodaysDaily()
        #expect(state.resetAction == .restartToday)
        #expect(state.resetAction.title == "Restart")
        state.reset()
        #expect(state.puzzleType == .daily)
    }

    @Test("With today's puzzle done and continuous play on, it's a new game on a random board")
    func continuousPlayIsNewGame() async throws {
        let cleanup = setupCleanPastDailyState(continuousPlay: true)
        defer { cleanup() }

        let state = freshTodaysDaily()
        winGame(state)
        try #require(state.status == .won)
        await waitForRecording()

        #expect(state.resetAction == .newGame)
        #expect(state.resetAction.title == "New Game")
        state.reset()
        #expect(state.puzzleType == .random)
        #expect(state.resetAction == .newGame, "And the next one is a new game too")
    }

    @Test("With continuous play off, a finished day says where more games come from")
    func dailyDoneExplainsTheLock() async throws {
        let cleanup = setupCleanPastDailyState(continuousPlay: false)
        defer { cleanup() }

        let state = freshTodaysDaily()
        winGame(state)
        try #require(state.status == .won)
        await waitForRecording()

        #expect(!state.canReset)
        #expect(state.resetLockedHint.contains("continuous play"))
    }

    @Test("A replay restarts its own board")
    func replayRestarts() async throws {
        let cleanup = setupCleanPastDailyState()
        defer { cleanup() }

        let yesterday = pastSeed(daysAgo: 1)
        StatsStore.shared.merge(dailyResults: [onTheDayResult(yesterday, at: Date().addingTimeInterval(60))])
        let state = freshTodaysDaily()
        #expect(state.playPastDay(seed: yesterday))
        #expect(state.resetAction == .restartReplay)
        #expect(state.resetAction.title == "Restart")
        state.reset()
        #expect(state.puzzleType == .practice)
        #expect(state.dailySeed == yesterday)
    }

    @Test("A finished past daily is played again as a replay")
    func finishedPastDailyReplays() async throws {
        let cleanup = setupCleanPastDailyState()
        defer { cleanup() }

        let yesterday = pastSeed(daysAgo: 1)
        let state = freshTodaysDaily()
        #expect(state.playPastDay(seed: yesterday))
        #expect(state.resetAction == .restartPastDaily)

        try loseGame(state)
        await waitForRecording()
        #expect(state.resetAction == .replayPastDaily)
        state.reset()
        #expect(state.puzzleType == .practice)
    }

    @Test("A daily carried over from yesterday and finished today moves on to today's puzzle")
    func finishedCarriedOverDailyStartsToday() async throws {
        let cleanup = setupCleanPastDailyState(continuousPlay: true)
        let yesterday = pastSeed(daysAgo: 1)
        defer {
            cleanup()
            UserDefaults.standard.removeObject(forKey: "dailyStats_\(yesterday)")
        }

        let state = GameState(board: Board(dailySeed: yesterday), dailySeed: yesterday, puzzleType: .daily)
        try makeOpeningMove(state)
        #expect(state.isCarriedOverDaily)
        winGame(state)
        try #require(state.status == .won)
        await waitForRecording()

        #expect(state.canReset)
        #expect(state.resetAction == .startToday)
        #expect(state.resetAction.title == "New Game")
        state.reset()
        #expect(state.puzzleType == .daily)
        #expect(state.dailySeed == seedFromDate(Date()))
        #expect(state.resetAction == .restartToday, "Now it's today's own board")
    }
}
