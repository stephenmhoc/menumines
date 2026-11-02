import Foundation
import Testing
@testable import MenuMines

@Suite("GameState Timer Tests")
struct GameStateTimerTests {

    @Test("Timer starts on first reveal")
    @MainActor
    func testTimerStartsOnFirstReveal() {
        let board = Board(seed: 12345)
        let gameState = GameState(board: board)

        #expect(gameState.status == .notStarted)
        #expect(gameState.elapsedTime == 0)

        gameState.reveal(row: 0, col: 0)

        #expect(gameState.status == .playing)

        // Run RunLoop to let timer fire
        runLoopFor(seconds: 1.2)

        #expect(gameState.elapsedTime >= 1)
    }

    @Test("Timer does not start before first click")
    @MainActor
    func testTimerDoesNotStartBeforeFirstClick() {
        let board = Board(seed: 12345)
        let gameState = GameState(board: board)

        #expect(gameState.status == .notStarted)
        #expect(gameState.elapsedTime == 0)

        // Wait without clicking
        runLoopFor(seconds: 1.2)

        #expect(gameState.elapsedTime == 0, "Timer should not run before first click")
        #expect(gameState.status == .notStarted)
    }

    @Test("Timer stops on win")
    @MainActor
    func testTimerStopsOnWin() {
        let board = Board(seed: 12345)
        let gameState = GameState(board: board)

        winGame(gameState)

        #expect(gameState.status == .won)
        let timeAtWin = gameState.elapsedTime

        runLoopFor(seconds: 1.2)

        #expect(gameState.elapsedTime == timeAtWin, "Timer should stop after winning")
    }

    @Test("Timer stops on lose")
    @MainActor
    func testTimerStopsOnLose() {
        let board = Board(seed: 12345)
        let gameState = GameState(board: board)

        // Make a safe first click to start the game
        guard let safe = findSafeCell(in: gameState.board) else {
            Issue.record("No safe cell found")
            return
        }
        gameState.reveal(row: safe.row, col: safe.col)
        #expect(gameState.status == .playing)

        // Find a mine and click it to lose
        guard let mine = findMineCell(in: gameState.board) else {
            Issue.record("No mine cell found")
            return
        }
        gameState.reveal(row: mine.row, col: mine.col)

        #expect(gameState.status == .lost)
        let timeAtLoss = gameState.elapsedTime

        // Wait and verify timer has stopped
        runLoopFor(seconds: 1.2)

        #expect(gameState.elapsedTime == timeAtLoss, "Timer should stop after losing")
    }

    @Test("Elapsed time is initially zero")
    func testElapsedTimeInitiallyZero() {
        let board = Board(seed: 12345)
        let gameState = GameState(board: board)

        #expect(gameState.elapsedTime == 0)
    }

    @Test("Pause timer stops time increment")
    @MainActor
    func testPauseTimerStopsTimeIncrement() {
        let board = Board(seed: 12345)
        let gameState = GameState(board: board)

        // Start game
        gameState.reveal(row: 0, col: 0)
        #expect(gameState.status == .playing)

        // Wait for timer to tick
        runLoopFor(seconds: 1.2)
        #expect(gameState.elapsedTime >= 1)

        // Pause timer
        gameState.pauseTimer()
        let timeBeforePause = gameState.elapsedTime

        // Wait and verify time doesn't increase
        runLoopFor(seconds: 1.2)

        #expect(gameState.elapsedTime == timeBeforePause, "Timer should not increment while paused")
    }

    @Test("Resume timer continues from paused time")
    @MainActor
    func testResumeTimerContinuesFromPausedTime() {
        let board = Board(seed: 12345)
        let gameState = GameState(board: board)

        // Start game
        gameState.reveal(row: 0, col: 0)
        #expect(gameState.status == .playing)

        // Wait for timer to tick
        runLoopFor(seconds: 1.2)
        let timeBeforePause = gameState.elapsedTime
        #expect(timeBeforePause >= 1)

        // Pause and resume
        gameState.pauseTimer()
        let pausedTime = gameState.elapsedTime
        gameState.resumeTimer()

        // Wait for timer to tick after resume
        runLoopFor(seconds: 1.2)

        #expect(gameState.elapsedTime > pausedTime, "Timer should continue incrementing after resume")
    }

    @Test("Resume timer does nothing if game not playing")
    @MainActor
    func testResumeTimerDoesNothingIfNotPlaying() {
        let board = Board(seed: 12345)
        let gameState = GameState(board: board)

        #expect(gameState.status == .notStarted)
        #expect(gameState.elapsedTime == 0)

        // Try to resume when not playing
        gameState.resumeTimer()

        // Wait and verify timer didn't start
        runLoopFor(seconds: 1.2)

        #expect(gameState.elapsedTime == 0, "Resume should not start timer when game not in .playing status")
    }

    @Test("Resume timer does nothing after win")
    @MainActor
    func testResumeTimerDoesNothingAfterWin() {
        let board = Board(seed: 12345)
        let gameState = GameState(board: board)

        winGame(gameState)

        #expect(gameState.status == .won)
        let timeAtWin = gameState.elapsedTime

        gameState.resumeTimer()

        runLoopFor(seconds: 1.2)

        #expect(gameState.elapsedTime == timeAtWin, "Resume should not restart timer after winning")
    }

    @Test("Resume timer does nothing after loss")
    @MainActor
    func testResumeTimerDoesNothingAfterLoss() {
        let board = Board(seed: 12345)
        let gameState = GameState(board: board)

        // Make a safe first click to start the game
        guard let safe = findSafeCell(in: gameState.board) else {
            Issue.record("No safe cell found")
            return
        }
        gameState.reveal(row: safe.row, col: safe.col)
        #expect(gameState.status == .playing)

        // Find a mine and click it to lose
        guard let mine = findMineCell(in: gameState.board) else {
            Issue.record("No mine cell found")
            return
        }
        gameState.reveal(row: mine.row, col: mine.col)

        #expect(gameState.status == .lost)
        let timeAtLoss = gameState.elapsedTime

        // Try to resume after losing
        gameState.resumeTimer()

        // Wait and verify timer didn't restart
        runLoopFor(seconds: 1.2)

        #expect(gameState.elapsedTime == timeAtLoss, "Resume should not restart timer after losing")
    }

    @Test("Flag does not start timer")
    @MainActor
    func testFlagDoesNotStartTimer() {
        let board = Board(seed: 12345)
        let gameState = GameState(board: board)

        #expect(gameState.status == .notStarted)
        #expect(gameState.elapsedTime == 0)

        // Toggle flag on a cell (should not start timer)
        gameState.toggleFlag(row: 0, col: 0)

        #expect(gameState.status == .notStarted, "Flagging should not start the game")

        // Wait and verify timer didn't start
        runLoopFor(seconds: 1.2)

        #expect(gameState.elapsedTime == 0, "Timer should not run after flagging without revealing")
    }
}
