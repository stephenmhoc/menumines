import Foundation
import Testing
@testable import MenuMines

@Suite("Daily Rollover Tests", .serialized)
struct DailyRolloverTests {

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    private func clearAllUserDefaults() {
        // These tests are about carrying a game over midnight, which relies on this being off.
        UserDefaults.standard.set(false, forKey: Constants.SettingsKeys.continuousPlay)
        GameSnapshot.clear()
        GameSnapshot.withStorageKey(GameSnapshot.dailyNamespace) { GameSnapshot.clear() }
        UserDefaults.standard.removeObject(forKey: "dailyCompletionSeed")
        UserDefaults.standard.removeObject(forKey: "dailyStatsRecordedSeed")
        let todaySeed = seedFromDate(Date())
        UserDefaults.standard.removeObject(forKey: "dailyStats_\(todaySeed)")
        if let previousSeed = previousDailySeed() {
            UserDefaults.standard.removeObject(forKey: "dailyStats_\(previousSeed)")
        }
    }

    private func tearDown() {
        clearAllUserDefaults()
        UserDefaults.standard.removeObject(forKey: Constants.SettingsKeys.continuousPlay)
    }

    private func previousDailySeed() -> Int64? {
        let todaySeed = seedFromDate(Date())
        guard let today = dateFromSeed(todaySeed),
              let previousDay = utcCalendar.date(byAdding: .day, value: -1, to: today) else {
            return nil
        }
        return seedFromDate(previousDay)
    }

    private func findSafeCell(in board: Board) -> (row: Int, col: Int)? {
        for r in 0..<Board.rows {
            for c in 0..<Board.cols {
                if !board.cells[r][c].hasMine {
                    return (r, c)
                }
            }
        }
        return nil
    }

    /// The first covered cell, optionally limited to cells with or without a mine.
    private func firstHiddenCell(in board: Board, mine: Bool?) -> (row: Int, col: Int)? {
        for r in 0..<Board.rows {
            for c in 0..<Board.cols {
                let cell = board.cells[r][c]
                guard cell.state == .hidden else { continue }
                if let mine, cell.hasMine != mine { continue }
                return (r, c)
            }
        }
        return nil
    }

    private func findMineCell(in board: Board) -> (row: Int, col: Int)? {
        for r in 0..<Board.rows {
            for c in 0..<Board.cols {
                if board.cells[r][c].hasMine {
                    return (r, c)
                }
            }
        }
        return nil
    }

    private func winGame(_ gameState: GameState) {
        for r in 0..<Board.rows {
            for c in 0..<Board.cols {
                if !gameState.board.cells[r][c].hasMine {
                    gameState.reveal(row: r, col: c)
                }
            }
        }
    }

    private func withIsolatedSnapshot<T>(_ testName: String = #function, _ body: () throws -> T) rethrows -> T {
        try GameSnapshot.withStorageKey("DailyRolloverTests.\(testName)", body)
    }

    // MARK: - GameSnapshot.loadAnyDay Tests

    @Test("loadAnyDay returns snapshot from any day")
    func testLoadAnyDayReturnsSnapshotFromAnyDay() {
        withIsolatedSnapshot {
            clearAllUserDefaults()
            defer { tearDown() }

            let board = Board(seed: 12345)
            let yesterdaySeed = yesterdaySeed()
            let snapshot = GameSnapshot(
                board: board,
                status: .playing,
                elapsedTime: 50.0,
                flagCount: 2,
                selectedRow: 3,
                selectedCol: 4,
                dailySeed: yesterdaySeed
            )
            snapshot.save()

            let loaded = GameSnapshot.loadAnyDay()
            #expect(loaded != nil, "loadAnyDay should return snapshot regardless of date")
            #expect(loaded?.dailySeed == yesterdaySeed, "Snapshot should have yesterday's seed")
            #expect(loaded?.status == .playing, "Snapshot should preserve status")
        }
    }

    @Test("loadAnyDay returns nil when no snapshot exists")
    func testLoadAnyDayReturnsNilWhenNoSnapshot() {
        withIsolatedSnapshot {
            clearAllUserDefaults()
            defer { tearDown() }

            let loaded = GameSnapshot.loadAnyDay()
            #expect(loaded == nil, "loadAnyDay should return nil when no snapshot exists")
        }
    }

    // MARK: - Rollover on restored() Tests

    @Test("restored() returns fresh game when snapshot is from previous day and game was not started")
    func testRestoredRollsOverWhenNotStarted() {
        withIsolatedSnapshot {
            clearAllUserDefaults()
            defer { tearDown() }

            let board = Board(seed: 12345)
            let yesterdaySeed = yesterdaySeed()
            let snapshot = GameSnapshot(
                board: board,
                status: .notStarted,
                elapsedTime: 0,
                flagCount: 0,
                selectedRow: 0,
                selectedCol: 0,
                dailySeed: yesterdaySeed
            )
            snapshot.save()

            let restored = GameState.restored()

            let todaySeed = seedFromDate(Date())
            #expect(restored.status == .notStarted, "Should be not started")
            // Board should be today's board, not yesterday's
            let expectedBoard = Board(dailySeed: todaySeed)
            #expect(restored.board == expectedBoard, "Should have today's board")
        }
    }

    @Test("restored() returns fresh game when snapshot is from previous day and game was won")
    func testRestoredRollsOverWhenWon() {
        withIsolatedSnapshot {
            clearAllUserDefaults()
            defer { tearDown() }

            let board = Board(seed: 12345)
            let yesterdaySeed = yesterdaySeed()
            let snapshot = GameSnapshot(
                board: board,
                status: .won,
                elapsedTime: 100.0,
                flagCount: 5,
                selectedRow: 4,
                selectedCol: 4,
                dailySeed: yesterdaySeed
            )
            snapshot.save()

            let restored = GameState.restored()

            #expect(restored.status == .notStarted, "Should be not started (rolled over)")
            #expect(restored.elapsedTime == 0, "Elapsed time should be 0")
            #expect(restored.flagCount == 0, "Flag count should be 0")
        }
    }

    @Test("restored() returns fresh game when snapshot is from previous day and game was lost")
    func testRestoredRollsOverWhenLost() {
        withIsolatedSnapshot {
            clearAllUserDefaults()
            defer { tearDown() }

            let board = Board(seed: 12345)
            let yesterdaySeed = yesterdaySeed()
            let snapshot = GameSnapshot(
                board: board,
                status: .lost,
                elapsedTime: 50.0,
                flagCount: 3,
                selectedRow: 2,
                selectedCol: 2,
                dailySeed: yesterdaySeed
            )
            snapshot.save()

            let restored = GameState.restored()

            #expect(restored.status == .notStarted, "Should be not started (rolled over)")
            #expect(restored.elapsedTime == 0, "Elapsed time should be 0")
        }
    }

    @Test("restored() keeps previous day's game when game was in progress")
    func testRestoredDelaysRolloverWhenInProgress() {
        withIsolatedSnapshot {
            clearAllUserDefaults()
            defer { tearDown() }

            let board = Board(seed: 12345)
            let yesterdaySeed = yesterdaySeed()
            let snapshot = GameSnapshot(
                board: board,
                status: .playing,
                elapsedTime: 75.0,
                flagCount: 0,
                selectedRow: 5,
                selectedCol: 6,
                dailySeed: yesterdaySeed
            )
            snapshot.save()

            let restored = GameState.restored()

            #expect(restored.status == .playing, "Should still be playing (rollover delayed)")
            #expect(restored.elapsedTime == 75.0, "Elapsed time should be preserved")
            #expect(restored.flagCount == 0, "Flag count should come from the board")
            #expect(restored.selectedRow == 5, "Selected row should be preserved")
            #expect(restored.selectedCol == 6, "Selected col should be preserved")
            #expect(restored.board == board, "Board should be preserved")
        }
    }

    @Test("restored() restores today's snapshot normally")
    func testRestoredRestoresTodaysSnapshot() {
        withIsolatedSnapshot {
            clearAllUserDefaults()
            defer { tearDown() }

            let board = Board(seed: 12345)
            let todaySeed = seedFromDate(Date())
            let snapshot = GameSnapshot(
                board: board,
                status: .playing,
                elapsedTime: 42.0,
                flagCount: 0,
                selectedRow: 1,
                selectedCol: 2,
                dailySeed: todaySeed
            )
            snapshot.save()

            let restored = GameState.restored()

            #expect(restored.status == .playing, "Should be playing")
            #expect(restored.elapsedTime == 42.0, "Elapsed time should be preserved")
            #expect(restored.selectedCol == 2, "Selection should be preserved")
        }
    }

    // MARK: - checkForDailyRollover Tests

    @Test("checkForDailyRollover does nothing when already on today's puzzle")
    func testCheckRolloverDoesNothingForTodaysPuzzle() {
        clearAllUserDefaults()
        defer { tearDown() }

        let todaySeed = seedFromDate(Date())
        let board = Board(dailySeed: todaySeed)
        let gameState = GameState(board: board, dailySeed: todaySeed)
        gameState.reveal(row: 0, col: 0)

        let statusBefore = gameState.status
        let elapsedBefore = gameState.elapsedTime

        gameState.checkForDailyRollover()

        #expect(gameState.status == statusBefore, "Status should not change")
        #expect(gameState.elapsedTime == elapsedBefore, "Elapsed time should not change")
    }

    @Test("checkForDailyRollover does nothing when game is in progress")
    func testCheckRolloverDoesNothingWhenInProgress() {
        clearAllUserDefaults()
        defer { tearDown() }

        // Create a game with yesterday's seed that's in progress
        let yesterdaySeed = yesterdaySeed()
        let board = Board(seed: yesterdaySeed)
        let gameState = GameState(board: board, dailySeed: yesterdaySeed)
        gameState.reveal(row: 0, col: 0)

        #expect(gameState.status == .playing)

        let boardBefore = gameState.board

        gameState.checkForDailyRollover()

        #expect(gameState.status == .playing, "Should still be playing")
        #expect(gameState.board == boardBefore, "Board should not change")
    }

    @Test("checkForDailyRollover rolls over after previously delayed in-progress game completes")
    func testCheckRolloverAfterDelayedGameCompletes() {
        clearAllUserDefaults()
        defer { tearDown() }

        guard let previousSeed = previousDailySeed() else {
            Issue.record("Failed to construct previous UTC daily seed")
            return
        }

        let gameState = GameState(board: Board(seed: previousSeed), dailySeed: previousSeed)

        guard let safe = findSafeCell(in: gameState.board) else {
            Issue.record("No safe cell found")
            return
        }
        gameState.reveal(row: safe.row, col: safe.col)
        #expect(gameState.status == .playing)

        gameState.checkForDailyRollover()
        #expect(gameState.dailySeed == previousSeed, "Rollover should be delayed while playing")

        winGame(gameState)
        #expect(gameState.status == .won)

        gameState.checkForDailyRollover()

        #expect(gameState.dailySeed == seedFromDate(Date()), "Completed stale game should roll over on the next check")
        #expect(gameState.status == .notStarted)
    }

    @Test("checkForDailyRollover triggers rollover when game is not in progress")
    func testCheckRolloverTriggersRolloverWhenNotInProgress() {
        clearAllUserDefaults()
        defer { tearDown() }

        // Create a game with yesterday's seed that's won
        let yesterdaySeed = yesterdaySeed()
        let board = Board(seed: yesterdaySeed)
        let gameState = GameState(board: board, dailySeed: yesterdaySeed)

        // Simulate a won game
        for r in 0..<Board.rows {
            for c in 0..<Board.cols {
                if !gameState.board.cells[r][c].hasMine {
                    gameState.reveal(row: r, col: c)
                }
            }
        }
        #expect(gameState.status == .won)

        gameState.checkForDailyRollover()

        #expect(gameState.status == .notStarted, "Should be reset to not started")
        #expect(gameState.elapsedTime == 0, "Elapsed time should be 0")
        #expect(gameState.flagCount == 0, "Flag count should be 0")

        // Should have today's board
        let todaySeed = seedFromDate(Date())
        let expectedBoard = Board(dailySeed: todaySeed)
        #expect(gameState.board == expectedBoard, "Should have today's board")
    }

    @Test("checkForDailyRollover triggers rollover when game was lost")
    func testCheckRolloverTriggersRolloverWhenLost() {
        clearAllUserDefaults()
        defer { tearDown() }

        // Create a game with yesterday's seed
        let yesterdaySeed = yesterdaySeed()
        let board = Board(seed: yesterdaySeed)
        let gameState = GameState(board: board, dailySeed: yesterdaySeed)

        // Start and lose the game
        guard let safe = findSafeCell(in: gameState.board) else {
            Issue.record("No safe cell found")
            return
        }
        gameState.reveal(row: safe.row, col: safe.col)

        guard let mine = findMineCell(in: gameState.board) else {
            Issue.record("No mine found")
            return
        }
        gameState.reveal(row: mine.row, col: mine.col)
        #expect(gameState.status == .lost)

        gameState.checkForDailyRollover()

        #expect(gameState.status == .notStarted, "Should be reset to not started")
        #expect(gameState.elapsedTime == 0, "Elapsed time should be 0")
    }

    @Test("checkForDailyRollover triggers rollover when game was not started")
    func testCheckRolloverTriggersRolloverWhenNotStarted() {
        clearAllUserDefaults()
        defer { tearDown() }

        // Create a game with yesterday's seed that was never started
        let yesterdaySeed = yesterdaySeed()
        let board = Board(seed: yesterdaySeed)
        let gameState = GameState(board: board, dailySeed: yesterdaySeed)

        #expect(gameState.status == .notStarted)

        gameState.checkForDailyRollover()

        #expect(gameState.status == .notStarted, "Should still be not started")
        #expect(gameState.elapsedTime == 0, "Elapsed time should be 0")

        // Should have today's board (different from yesterday's)
        let todaySeed = seedFromDate(Date())
        let expectedBoard = Board(dailySeed: todaySeed)
        #expect(gameState.board == expectedBoard, "Should have today's board")
    }

    @Test("checkForDailyRollover replaces idle random puzzle when today's daily is incomplete")
    func testCheckRolloverReplacesIdleRandomPuzzleWhenDailyIncomplete() {
        clearAllUserDefaults()
        defer { tearDown() }

        let randomSeed: Int64 = -12345
        let gameState = GameState(
            board: Board(seed: randomSeed),
            dailySeed: randomSeed,
            puzzleType: .random
        )

        gameState.checkForDailyRollover()

        let todaySeed = seedFromDate(Date())
        #expect(gameState.puzzleType == .daily, "Idle random puzzle should yield to today's daily")
        #expect(gameState.dailySeed == todaySeed, "Game should be on today's seed")
        #expect(gameState.status == .notStarted, "New daily should not be started")
        #expect(gameState.board == Board(dailySeed: todaySeed), "Board should be today's daily board")
    }

    @Test("checkForDailyRollover delays active random puzzle until completion")
    func testCheckRolloverDelaysActiveRandomPuzzleUntilCompletion() {
        clearAllUserDefaults()
        defer { tearDown() }

        let randomSeed: Int64 = -67890
        let gameState = GameState(
            board: Board(seed: randomSeed),
            dailySeed: randomSeed,
            puzzleType: .random
        )

        guard let safe = findSafeCell(in: gameState.board) else {
            Issue.record("No safe cell found")
            return
        }

        gameState.reveal(row: safe.row, col: safe.col)
        #expect(gameState.status == .playing)

        gameState.checkForDailyRollover()

        #expect(gameState.puzzleType == .random, "Active random puzzle should continue")
        #expect(gameState.dailySeed == randomSeed, "Random seed should be preserved while playing")

        gameState.status = .won
        gameState.checkForDailyRollover()

        let todaySeed = seedFromDate(Date())
        #expect(gameState.puzzleType == .daily, "Completed random puzzle should yield to today's daily")
        #expect(gameState.dailySeed == todaySeed, "Game should move to today's seed after random completion")
        #expect(gameState.status == .notStarted, "New daily should not be started")
    }

    // MARK: - Scenario Integration Tests

    @Test("Scenario: Paused in-progress game persists across day boundary")
    func testScenarioPausedGamePersistsAcrossDayBoundary() {
        clearAllUserDefaults()
        defer { tearDown() }

        // 1. User starts playing on day 1
        let day1Seed = yesterdaySeed()
        let day1Board = Board(seed: day1Seed)
        let gameState = GameState(board: day1Board, dailySeed: day1Seed)

        // Start the game. Which cells are covered depends on the date's board, so pick them
        // rather than hardcoding coordinates that today's opening may already have revealed.
        guard let safe = firstHiddenCell(in: gameState.board, mine: false) else {
            Issue.record("No covered safe cell found")
            return
        }
        gameState.reveal(row: safe.row, col: safe.col)
        guard let covered = firstHiddenCell(in: gameState.board, mine: nil) else {
            Issue.record("No covered cell left to flag")
            return
        }
        gameState.toggleFlag(row: covered.row, col: covered.col)
        #expect(gameState.status == .playing)

        // 2. User closes popover (simulated by pauseTimer and save)
        gameState.pauseTimer()
        gameState.save()

        // 3. Day changes to day 2 - simulated by restored() loading the saved game
        let restoredState = GameState.restored()

        // Game should persist because it was in progress
        #expect(restoredState.status == .playing, "Game should still be in progress")
        #expect(restoredState.flagCount == 1, "Flag count should be preserved")
        #expect(restoredState.board == gameState.board, "Board should be from day 1")

        // 4. User opens popover on day 2
        restoredState.checkForDailyRollover()
        restoredState.resumeTimer()

        // Game should STILL persist because it's still in progress
        #expect(restoredState.status == .playing, "Game should continue from day 1")
    }

    @Test("Scenario: Completed game rolls over on next day")
    func testScenarioCompletedGameRollsOverOnNextDay() {
        clearAllUserDefaults()
        defer { tearDown() }

        // 1. User completes game on day 1
        let day1Seed = yesterdaySeed()
        let day1Board = Board(seed: day1Seed)
        let gameState = GameState(board: day1Board, dailySeed: day1Seed)

        winGame(gameState)
        #expect(gameState.status == .won)

        // 2. User closes popover (simulated by save)
        gameState.save()

        // 3. Day changes to day 2 - simulated by restored()
        let restoredState = GameState.restored()

        // Game should roll over because it was completed
        #expect(restoredState.status == .notStarted, "Should be fresh game for day 2")

        // Should have today's board
        let todaySeed = seedFromDate(Date())
        let todayBoard = Board(dailySeed: todaySeed)
        #expect(restoredState.board == todayBoard, "Should have day 2's board")
    }

    @Test("Scenario: In-progress game rolls over after completion on next popover open")
    func testScenarioInProgressGameRollsOverAfterCompletion() {
        clearAllUserDefaults()
        defer { tearDown() }

        // 1. User has in-progress game from day 1
        let day1Seed = yesterdaySeed()
        let day1Board = Board(seed: day1Seed)
        let gameState = GameState(board: day1Board, dailySeed: day1Seed)

        gameState.reveal(row: 0, col: 0)
        #expect(gameState.status == .playing)

        // Save as in-progress
        gameState.save()

        // 2. Day 2: Restore (should keep day 1 game)
        let restoredState = GameState.restored()
        #expect(restoredState.status == .playing, "Should restore in-progress game")

        // 3. User completes the day 1 game on day 2
        winGame(restoredState)
        #expect(restoredState.status == .won)
        restoredState.save()

        // 4. User closes and reopens popover on day 2
        // Simulate by calling checkForDailyRollover
        restoredState.checkForDailyRollover()

        // Should now roll over since game is complete
        #expect(restoredState.status == .notStarted, "Should roll over after game completed")

        // Should have today's board
        let todaySeed = seedFromDate(Date())
        let todayBoard = Board(dailySeed: todaySeed)
        #expect(restoredState.board == todayBoard, "Should have today's board")
    }
}
