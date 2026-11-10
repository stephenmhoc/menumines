import Foundation
import Testing
@testable import MenuMines

// MARK: - Persistence Tests with UserDefaults (Serialized)
// These tests use shared UserDefaults storage and must run serially to avoid interference

@Suite("GameState Persistence Tests", .serialized)
struct GameStatePersistenceTests {

    private func withIsolatedSnapshot<T>(_ testName: String = #function, _ body: () throws -> T) rethrows -> T {
        try GameSnapshot.withStorageKey("GameStatePersistenceTests.\(testName)", body)
    }

    @Test("GameSnapshot save and load works")
    func testGameSnapshotSaveLoad() {
        withIsolatedSnapshot {
            GameSnapshot.clear()
            defer { GameSnapshot.clear() }

            let board = Board(seed: 12345)
            let todaySeed = seedFromDate(Date())
            let snapshot = GameSnapshot(
                board: board,
                status: .playing,
                elapsedTime: 99.0,
                flagCount: 5,
                selectedRow: 3,
                selectedCol: 4,
                dailySeed: todaySeed
            )

            snapshot.save()

            guard let loaded = GameSnapshot.load() else {
                Issue.record("Snapshot should be loadable")
                return
            }

            #expect(loaded.board == snapshot.board)
            #expect(loaded.status == snapshot.status)
            #expect(loaded.elapsedTime == snapshot.elapsedTime)
            #expect(loaded.flagCount == snapshot.flagCount)
            #expect(loaded.selectedRow == snapshot.selectedRow)
            #expect(loaded.selectedCol == snapshot.selectedCol)
            #expect(loaded.dailySeed == snapshot.dailySeed)
        }
    }

    @Test("GameSnapshot load returns nil for stale date")
    func testGameSnapshotStaleDate() {
        GameSnapshot.clear()
        defer { GameSnapshot.clear() }

        let board = Board(seed: 12345)
        // Use yesterday's seed
        let staleSeed = yesterdaySeed()
        let snapshot = GameSnapshot(
            board: board,
            status: .playing,
            elapsedTime: 50.0,
            flagCount: 2,
            selectedRow: 1,
            selectedCol: 1,
            dailySeed: staleSeed
        )

        snapshot.save()

        let loaded = GameSnapshot.load()
        #expect(loaded == nil, "Snapshot with stale date should not load")

        // Verify it was cleared
        let loadedAgain = GameSnapshot.load()
        #expect(loadedAgain == nil, "Stale snapshot should be cleared after load attempt")
    }

    @Test("GameSnapshot load returns nil when no snapshot exists")
    func testGameSnapshotLoadNil() {
        GameSnapshot.clear()
        defer { GameSnapshot.clear() }

        let loaded = GameSnapshot.load()
        #expect(loaded == nil)
    }

    @Test("GameState save creates snapshot for playing state")
    func testGameStateSaveCreatesSnapshot() {
        GameSnapshot.clear()
        defer { GameSnapshot.clear() }

        let board = Board(seed: 12345)
        let gameState = GameState(board: board)

        // Start the game
        gameState.reveal(row: 0, col: 0)
        #expect(gameState.status == .playing)

        // Find and flag a hidden cell (after first-click clearing may reveal some cells)
        var flagRow = 0, flagCol = 0
        outer: for r in 0..<Board.rows {
            for c in 0..<Board.cols {
                if case .hidden = gameState.board.cells[r][c].state {
                    gameState.toggleFlag(row: r, col: c)
                    flagRow = r
                    flagCol = c
                    break outer
                }
            }
        }

        // Move selection to flagged cell position
        while gameState.selectedRow < flagRow { gameState.moveSelection(.down) }
        while gameState.selectedCol < flagCol { gameState.moveSelection(.right) }

        gameState.save()

        guard let loaded = GameSnapshot.load() else {
            Issue.record("Snapshot should exist after save")
            return
        }

        #expect(loaded.status == .playing)
        #expect(loaded.flagCount == 1)
        #expect(loaded.selectedRow == flagRow)
        #expect(loaded.selectedCol == flagCol)
    }

    @Test("GameState save persists won status")
    func testGameStateSavePersistsWonStatus() {
        GameSnapshot.clear()
        defer { GameSnapshot.clear() }

        let board = Board(seed: 12345)
        let gameState = GameState(board: board)

        // Start and save
        gameState.reveal(row: 0, col: 0)
        gameState.save()
        #expect(GameSnapshot.load() != nil, "Snapshot should exist while playing")

        // Win the game
        winGame(gameState)
        #expect(gameState.status == .won)

        // Save after win should persist won status
        gameState.save()
        guard let loaded = GameSnapshot.load() else {
            Issue.record("Snapshot should exist after win")
            return
        }
        #expect(loaded.status == .won, "Snapshot should have won status")
    }

    @Test("GameState save persists lost status")
    func testGameStateSavePersistsLostStatus() {
        GameSnapshot.clear()
        defer { GameSnapshot.clear() }

        let board = Board(seed: 12345)
        let gameState = GameState(board: board)

        // Start and save
        guard let safe = findSafeCell(in: gameState.board) else {
            Issue.record("No safe cell found")
            return
        }
        gameState.reveal(row: safe.row, col: safe.col)
        gameState.save()
        #expect(GameSnapshot.load() != nil, "Snapshot should exist while playing")

        // Lose the game
        guard let mine = findMineCell(in: gameState.board) else {
            Issue.record("No mine found")
            return
        }
        gameState.reveal(row: mine.row, col: mine.col)
        #expect(gameState.status == .lost)

        // Save after loss should persist lost status
        gameState.save()
        guard let loaded = GameSnapshot.load() else {
            Issue.record("Snapshot should exist after loss")
            return
        }
        #expect(loaded.status == .lost, "Snapshot should have lost status")
    }

    @Test("GameState save does nothing for notStarted state")
    func testGameStateSaveDoesNothingNotStarted() {
        GameSnapshot.clear()
        defer { GameSnapshot.clear() }

        let board = Board(seed: 12345)
        let gameState = GameState(board: board)

        #expect(gameState.status == .notStarted)

        gameState.save()
        #expect(GameSnapshot.load() == nil, "Snapshot should not be created for notStarted state")
    }

    @Test("GameState reset clears snapshot")
    func testGameStateResetClearsSnapshot() {
        GameSnapshot.clear()
        UserDefaults.standard.removeObject(forKey: "dailyCompletionSeed")
        defer {
            GameSnapshot.clear()
            UserDefaults.standard.removeObject(forKey: "dailyCompletionSeed")
        }

        let board = Board(seed: 12345)
        let gameState = GameState(board: board, dailySeed: yesterdaySeed())

        // Start and save (but don't complete)
        gameState.reveal(row: 0, col: 0)
        gameState.save()
        #expect(GameSnapshot.loadAnyDay() != nil, "Snapshot should exist while playing")

        // Reset (allowed because a game carried over from yesterday isn't ranked)
        gameState.reset()
        #expect(GameSnapshot.loadAnyDay() == nil, "Snapshot should be cleared after reset")
    }

    @Test("GameState restored creates fresh game when no snapshot")
    func testGameStateRestoredFreshGame() {
        GameSnapshot.clear()
        UserDefaults.standard.removeObject(forKey: "dailyCompletionSeed")
        UserDefaults.standard.removeObject(forKey: "dailyStatsRecordedSeed")
        let todaySeed = seedFromDate(Date())
        UserDefaults.standard.removeObject(forKey: "dailyStats_\(todaySeed)")
        defer {
            GameSnapshot.clear()
            UserDefaults.standard.removeObject(forKey: "dailyCompletionSeed")
            UserDefaults.standard.removeObject(forKey: "dailyStatsRecordedSeed")
            UserDefaults.standard.removeObject(forKey: "dailyStats_\(todaySeed)")
        }

        GameSnapshot.withStorageKey(GameSnapshot.dailyNamespace) { GameSnapshot.clear() }
        let gameState = GameState.restored()

        #expect(gameState.status == .notStarted)
        #expect(gameState.elapsedTime == 0)
        #expect(gameState.flagCount == 0)
        #expect(gameState.selectedRow == 0)
        #expect(gameState.selectedCol == 0)
    }

    @Test("GameState restored restores from snapshot")
    func testGameStateRestoredFromSnapshot() {
        GameSnapshot.clear()
        let settingKey = Constants.SettingsKeys.continuousPlay
        let initialSettingValue = UserDefaults.standard.object(forKey: settingKey)
        defer {
            GameSnapshot.clear()
            if let initial = initialSettingValue {
                UserDefaults.standard.set(initial, forKey: settingKey)
            } else {
                UserDefaults.standard.removeObject(forKey: settingKey)
            }
        }

        // Ensure continuousPlay is OFF so restore returns the saved state
        UserDefaults.standard.set(false, forKey: settingKey)

        // Create and save a game state
        let originalBoard = Board(seed: 12345)
        let originalState = GameState(board: originalBoard)
        originalState.reveal(row: 0, col: 0)

        // Find and flag a hidden cell (after first-click clearing may reveal some cells)
        var flagRow = 0, flagCol = 0
        outer: for r in 0..<Board.rows {
            for c in 0..<Board.cols {
                if case .hidden = originalState.board.cells[r][c].state {
                    originalState.toggleFlag(row: r, col: c)
                    flagRow = r
                    flagCol = c
                    break outer
                }
            }
        }

        // Move selection to flagged cell
        while originalState.selectedRow < flagRow { originalState.moveSelection(.down) }
        while originalState.selectedCol < flagCol { originalState.moveSelection(.right) }

        originalState.save()

        // Restore
        let restoredState = GameState.restored()

        #expect(restoredState.status == .playing)
        #expect(restoredState.flagCount == 1)
        #expect(restoredState.selectedRow == flagRow)
        #expect(restoredState.selectedCol == flagCol)
        #expect(restoredState.board.cells[flagRow][flagCol].state == .flagged)
    }

    @Test("GameState restored does not restore stale snapshot when game was completed")
    func testGameStateRestoredIgnoresStaleSnapshot() {
        GameSnapshot.clear()
        GameSnapshot.withStorageKey(GameSnapshot.dailyNamespace) { GameSnapshot.clear() }
        UserDefaults.standard.removeObject(forKey: "dailyCompletionSeed")
        UserDefaults.standard.removeObject(forKey: "dailyStatsRecordedSeed")
        let todaySeed = seedFromDate(Date())
        UserDefaults.standard.removeObject(forKey: "dailyStats_\(todaySeed)")
        defer {
            GameSnapshot.clear()
            UserDefaults.standard.removeObject(forKey: "dailyCompletionSeed")
            UserDefaults.standard.removeObject(forKey: "dailyStatsRecordedSeed")
            UserDefaults.standard.removeObject(forKey: "dailyStats_\(todaySeed)")
        }

        // Create a snapshot with yesterday's seed and a completed game (won)
        // Completed games should roll over to today's puzzle
        let board = Board(seed: 12345)
        let staleSeed = yesterdaySeed()
        let staleSnapshot = GameSnapshot(
            board: board,
            status: .won, // Completed game should trigger rollover
            elapsedTime: 100.0,
            flagCount: 5,
            selectedRow: 4,
            selectedCol: 4,
            dailySeed: staleSeed
        )
        staleSnapshot.save()

        // Restore should create fresh game for today
        let restoredState = GameState.restored()

        #expect(restoredState.status == .notStarted)
        #expect(restoredState.elapsedTime == 0)
        #expect(restoredState.flagCount == 0)
    }

    // MARK: - Continuous Play Tests

    @Test("Reset after daily completion with continuous play enabled starts random puzzle")
    func testResetAfterDailyStartsRandomWithContinuousPlay() {
        let settingKey = Constants.SettingsKeys.continuousPlay
        let initialSettingValue = UserDefaults.standard.object(forKey: settingKey)
        UserDefaults.standard.removeObject(forKey: "dailyCompletionSeed")
        UserDefaults.standard.removeObject(forKey: "dailyStatsRecordedSeed")
        let todaySeed = seedFromDate(Date())
        UserDefaults.standard.removeObject(forKey: "dailyStats_\(todaySeed)")
        defer {
            if let initial = initialSettingValue {
                UserDefaults.standard.set(initial, forKey: settingKey)
            } else {
                UserDefaults.standard.removeObject(forKey: settingKey)
            }
            UserDefaults.standard.removeObject(forKey: "dailyCompletionSeed")
            UserDefaults.standard.removeObject(forKey: "dailyStatsRecordedSeed")
            UserDefaults.standard.removeObject(forKey: "dailyStats_\(todaySeed)")
        }

        // Enable continuous play
        UserDefaults.standard.set(true, forKey: settingKey)

        let board = Board(seed: 12345)
        let gameState = GameState(board: board)

        // Complete the daily puzzle
        winGame(gameState)
        #expect(gameState.status == .won)
        #expect(gameState.puzzleType == .daily)

        // Reset should start a random puzzle
        gameState.reset()

        #expect(gameState.status == .notStarted)
        #expect(gameState.puzzleType == .random, "Reset after daily completion should start random puzzle")
    }

    @Test("Reset is blocked after daily completion when continuous play disabled")
    func testResetBlockedAfterDailyWhenContinuousPlayDisabled() {
        let settingKey = Constants.SettingsKeys.continuousPlay
        let initialSettingValue = UserDefaults.standard.object(forKey: settingKey)
        UserDefaults.standard.removeObject(forKey: "dailyCompletionSeed")
        UserDefaults.standard.removeObject(forKey: "dailyStatsRecordedSeed")
        let todaySeed = seedFromDate(Date())
        UserDefaults.standard.removeObject(forKey: "dailyStats_\(todaySeed)")
        defer {
            if let initial = initialSettingValue {
                UserDefaults.standard.set(initial, forKey: settingKey)
            } else {
                UserDefaults.standard.removeObject(forKey: settingKey)
            }
            UserDefaults.standard.removeObject(forKey: "dailyCompletionSeed")
            UserDefaults.standard.removeObject(forKey: "dailyStatsRecordedSeed")
            UserDefaults.standard.removeObject(forKey: "dailyStats_\(todaySeed)")
        }

        // Disable continuous play
        UserDefaults.standard.set(false, forKey: settingKey)

        let board = Board(seed: 12345)
        let gameState = GameState(board: board)

        winGame(gameState)
        #expect(gameState.status == .won)
        #expect(gameState.canReset == false)
        let elapsedAfterWin = gameState.elapsedTime

        // Reset should be blocked
        gameState.reset()

        #expect(gameState.status == .won)
        #expect(gameState.elapsedTime == elapsedAfterWin)
    }

    @Test("Disabling continuous play while on random puzzle restores daily state")
    func testDisablingContinuousPlayRestoresDaily() {
        GameSnapshot.clear()
        let settingKey = Constants.SettingsKeys.continuousPlay
        let initialSettingValue = UserDefaults.standard.object(forKey: settingKey)
        UserDefaults.standard.removeObject(forKey: "dailyCompletionSeed")
        UserDefaults.standard.removeObject(forKey: "dailyStatsRecordedSeed")
        let todaySeed = seedFromDate(Date())
        UserDefaults.standard.removeObject(forKey: "dailyStats_\(todaySeed)")
        defer {
            GameSnapshot.clear()
            if let initial = initialSettingValue {
                UserDefaults.standard.set(initial, forKey: settingKey)
            } else {
                UserDefaults.standard.removeObject(forKey: settingKey)
            }
            UserDefaults.standard.removeObject(forKey: "dailyCompletionSeed")
            UserDefaults.standard.removeObject(forKey: "dailyStatsRecordedSeed")
            UserDefaults.standard.removeObject(forKey: "dailyStats_\(todaySeed)")
        }

        // Enable continuous play
        UserDefaults.standard.set(true, forKey: settingKey)

        let board = Board(seed: 12345)
        let gameState = GameState(board: board)

        // Complete the daily puzzle
        winGame(gameState)
        #expect(gameState.status == .won)
        #expect(gameState.puzzleType == .daily)
        let dailyElapsedTime = gameState.elapsedTime

        // Reset to start a random puzzle
        gameState.reset()
        #expect(gameState.puzzleType == .random, "Should be on random puzzle after reset")
        #expect(gameState.status == .notStarted)

        // Now disable continuous play
        UserDefaults.standard.set(false, forKey: settingKey)

        // Check setting - should restore daily state
        gameState.checkContinuousPlaySetting()

        #expect(gameState.puzzleType == .daily, "Should be back on daily puzzle")
        #expect(gameState.status == .won, "Should show completed daily state")
        #expect(gameState.elapsedTime == dailyElapsedTime, "Should have original elapsed time")
        #expect(gameState.canReset == false, "Reset should be locked")
    }

    @Test("Reset before daily completion starts daily puzzle")
    func testResetBeforeDailyStartsDaily() {
        let settingKey = Constants.SettingsKeys.continuousPlay
        let initialSettingValue = UserDefaults.standard.object(forKey: settingKey)
        UserDefaults.standard.removeObject(forKey: "dailyCompletionSeed")
        defer {
            if let initial = initialSettingValue {
                UserDefaults.standard.set(initial, forKey: settingKey)
            } else {
                UserDefaults.standard.removeObject(forKey: settingKey)
            }
            UserDefaults.standard.removeObject(forKey: "dailyCompletionSeed")
        }

        // Enable continuous play
        UserDefaults.standard.set(true, forKey: settingKey)

        let board = Board(seed: 12345)
        let gameState = GameState(board: board, dailySeed: yesterdaySeed())

        // Start but don't complete
        guard let safe = findSafeCell(in: gameState.board) else {
            Issue.record("No safe cell found")
            return
        }
        gameState.reveal(row: safe.row, col: safe.col)
        #expect(gameState.status == .playing)

        // Reset should give a fresh daily puzzle
        gameState.reset()

        #expect(gameState.status == .notStarted)
        #expect(gameState.puzzleType == .daily, "Reset before completion should give daily puzzle")
    }

    // MARK: - Stats Recording Tests

    @Test("Stats are recorded on win")
    func testStatsRecordedOnWin() {
        UserDefaults.standard.removeObject(forKey: "dailyCompletionSeed")
        UserDefaults.standard.removeObject(forKey: "dailyStatsRecordedSeed")
        let todaySeed = seedFromDate(Date())
        UserDefaults.standard.removeObject(forKey: "dailyStats_\(todaySeed)")
        defer {
            UserDefaults.standard.removeObject(forKey: "dailyCompletionSeed")
            UserDefaults.standard.removeObject(forKey: "dailyStatsRecordedSeed")
            UserDefaults.standard.removeObject(forKey: "dailyStats_\(todaySeed)")
        }

        let board = Board(seed: 12345)
        let gameState = GameState(board: board)

        winGame(gameState)

        #expect(hasStatsBeenRecorded(forSeed: seedFromDate(Date())), "Stats should be recorded after winning")

        let stats = getStats(forSeed: seedFromDate(Date()))
        #expect(stats != nil, "Stats should be retrievable")
        #expect(stats?.won == true, "Stats should indicate win")
    }

    @Test("Daily completion is recorded against the active puzzle seed")
    func testDailyCompletionUsesActivePuzzleSeed() {
        let todaySeed = seedFromDate(Date())
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        guard let today = dateFromSeed(todaySeed),
              let previousDay = calendar.date(byAdding: .day, value: -1, to: today) else {
            Issue.record("Failed to construct previous UTC day")
            return
        }
        let previousSeed = seedFromDate(previousDay)

        UserDefaults.standard.removeObject(forKey: "dailyCompletionSeed")
        UserDefaults.standard.removeObject(forKey: "dailyStatsRecordedSeed")
        UserDefaults.standard.removeObject(forKey: "dailyStats_\(todaySeed)")
        UserDefaults.standard.removeObject(forKey: "dailyStats_\(previousSeed)")
        defer {
            UserDefaults.standard.removeObject(forKey: "dailyCompletionSeed")
            UserDefaults.standard.removeObject(forKey: "dailyStatsRecordedSeed")
            UserDefaults.standard.removeObject(forKey: "dailyStats_\(todaySeed)")
            UserDefaults.standard.removeObject(forKey: "dailyStats_\(previousSeed)")
        }

        let gameState = GameState(board: Board(seed: previousSeed), dailySeed: previousSeed)

        winGame(gameState)

        #expect(
            isDailyPuzzleComplete(forSeed: seedFromDate(previousDay)),
            "Previous puzzle seed should be marked complete"
        )
        #expect(!isDailyPuzzleComplete(), "Today's puzzle should not be marked complete")
        #expect(hasStatsBeenRecorded(forSeed: previousSeed), "Stats should be recorded for previous seed")
        #expect(getStats(forSeed: previousSeed)?.won == true, "Previous seed stats should reflect the win")
        #expect(getStats(forSeed: todaySeed) == nil, "No stats should be written under today's seed")
    }

    @Test("Stats are recorded on loss")
    func testStatsRecordedOnLoss() {
        UserDefaults.standard.removeObject(forKey: "dailyCompletionSeed")
        UserDefaults.standard.removeObject(forKey: "dailyStatsRecordedSeed")
        let todaySeed = seedFromDate(Date())
        UserDefaults.standard.removeObject(forKey: "dailyStats_\(todaySeed)")
        defer {
            UserDefaults.standard.removeObject(forKey: "dailyCompletionSeed")
            UserDefaults.standard.removeObject(forKey: "dailyStatsRecordedSeed")
            UserDefaults.standard.removeObject(forKey: "dailyStats_\(todaySeed)")
        }

        let board = Board(seed: 12345)
        let gameState = GameState(board: board)

        // Start game
        guard let safe = findSafeCell(in: gameState.board) else {
            Issue.record("No safe cell found")
            return
        }
        gameState.reveal(row: safe.row, col: safe.col)

        // Lose the game
        guard let mine = findMineCell(in: gameState.board) else {
            Issue.record("No mine found")
            return
        }
        gameState.reveal(row: mine.row, col: mine.col)

        #expect(hasStatsBeenRecorded(forSeed: seedFromDate(Date())), "Stats should be recorded after losing")

        let stats = getStats(forSeed: seedFromDate(Date()))
        #expect(stats != nil, "Stats should be retrievable")
        #expect(stats?.won == false, "Stats should indicate loss")
    }

    @Test("Stats are only recorded once per day")
    func testStatsDedupe() {
        UserDefaults.standard.removeObject(forKey: "dailyStatsRecordedSeed")
        let todaySeed = seedFromDate(Date())
        UserDefaults.standard.removeObject(forKey: "dailyStats_\(todaySeed)")
        defer {
            UserDefaults.standard.removeObject(forKey: "dailyStatsRecordedSeed")
            UserDefaults.standard.removeObject(forKey: "dailyStats_\(todaySeed)")
        }

        // First recording
        let recorded1 = recordStats(forSeed: seedFromDate(Date()), won: true, elapsedTime: 100.0, flagCount: 5)
        #expect(recorded1 == true, "First recording should succeed")

        // Second recording should be ignored
        let recorded2 = recordStats(forSeed: seedFromDate(Date()), won: false, elapsedTime: 200.0, flagCount: 10)
        #expect(recorded2 == false, "Second recording should be rejected")

        // Stats should reflect first recording
        let stats = getStats(forSeed: seedFromDate(Date()))
        #expect(stats?.won == true, "Stats should reflect first recording")
        #expect(stats?.elapsedTime == 100.0, "Elapsed time should be from first recording")
        #expect(stats?.flagCount == 5, "Flag count should be from first recording")
    }

    // MARK: - Error Recovery Tests

    @Test("Restored state recovers from stats when snapshot missing but daily complete")
    func testRestoredRecoverFromStats() {
        let cleanup = setupCleanPersistenceState(continuousPlay: false)
        defer { cleanup() }

        // Mark daily complete and record stats, but don't save snapshot (nor daily namespace)
        markDailyPuzzleComplete(forSeed: seedFromDate(Date()))
        _ = recordStats(forSeed: seedFromDate(Date()), won: true, elapsedTime: 123.0, flagCount: 7)

        // Restore should recover from stats (fallback when no snapshots exist)
        let restoredState = GameState.restored()

        #expect(restoredState.status == .won, "Should restore won status from stats")
        #expect(restoredState.elapsedTime == 123.0, "Should restore elapsed time from stats")
        #expect(restoredState.flagCount == 7, "Should restore flag count from stats")
    }

    @Test("Restored state falls back to fresh game when no snapshot and no stats")
    func testRestoredFallbackFreshGame() {
        GameSnapshot.clear()
        UserDefaults.standard.removeObject(forKey: "dailyCompletionSeed")
        UserDefaults.standard.removeObject(forKey: "dailyStatsRecordedSeed")
        let todaySeed = seedFromDate(Date())
        UserDefaults.standard.removeObject(forKey: "dailyStats_\(todaySeed)")
        defer {
            GameSnapshot.clear()
            UserDefaults.standard.removeObject(forKey: "dailyCompletionSeed")
            UserDefaults.standard.removeObject(forKey: "dailyStatsRecordedSeed")
            UserDefaults.standard.removeObject(forKey: "dailyStats_\(todaySeed)")
        }

        let restoredState = GameState.restored()

        #expect(restoredState.status == .notStarted, "Should restore to notStarted")
        #expect(restoredState.elapsedTime == 0, "Should have zero elapsed time")
        #expect(restoredState.flagCount == 0, "Should have zero flags")
    }

    // MARK: - Daily Completion Tests (Win and Loss)

    @Test("Daily puzzle marked complete on win")
    func testDailyCompleteOnWin() {
        UserDefaults.standard.removeObject(forKey: "dailyCompletionSeed")
        defer { UserDefaults.standard.removeObject(forKey: "dailyCompletionSeed") }

        let board = Board(seed: 12345)
        let gameState = GameState(board: board)

        #expect(!isDailyPuzzleComplete(), "Daily should not be complete before win")

        winGame(gameState)

        #expect(isDailyPuzzleComplete(), "Daily should be complete after win")
    }

    @Test("Daily puzzle marked complete on loss")
    func testDailyCompleteOnLoss() {
        UserDefaults.standard.removeObject(forKey: "dailyCompletionSeed")
        UserDefaults.standard.removeObject(forKey: "dailyStatsRecordedSeed")
        let todaySeed = seedFromDate(Date())
        UserDefaults.standard.removeObject(forKey: "dailyStats_\(todaySeed)")
        defer {
            UserDefaults.standard.removeObject(forKey: "dailyCompletionSeed")
            UserDefaults.standard.removeObject(forKey: "dailyStatsRecordedSeed")
            UserDefaults.standard.removeObject(forKey: "dailyStats_\(todaySeed)")
        }

        let board = Board(seed: 12345)
        let gameState = GameState(board: board)

        // Start game
        guard let safe = findSafeCell(in: gameState.board) else {
            Issue.record("No safe cell found")
            return
        }
        gameState.reveal(row: safe.row, col: safe.col)

        #expect(!isDailyPuzzleComplete(), "Daily should not be complete while playing")

        // Lose the game
        guard let mine = findMineCell(in: gameState.board) else {
            Issue.record("No mine found")
            return
        }
        gameState.reveal(row: mine.row, col: mine.col)

        #expect(isDailyPuzzleComplete(), "Daily should be complete after loss")
    }

    // MARK: - Reset Tests (require serialized due to UserDefaults)

    @Test("Reset restores initial state")
    func testResetRestoresInitialState() {
        UserDefaults.standard.removeObject(forKey: "dailyCompletionSeed")
        defer { UserDefaults.standard.removeObject(forKey: "dailyCompletionSeed") }

        let board = Board(seed: 12345)
        let gameState = GameState(board: board, dailySeed: yesterdaySeed())

        // Play the game (don't complete it)
        gameState.reveal(row: 0, col: 0)

        // Find and flag a hidden cell (after first-click clearing may reveal some cells)
        var flagged = false
        for r in 0..<Board.rows {
            for c in 0..<Board.cols {
                if case .hidden = gameState.board.cells[r][c].state {
                    gameState.toggleFlag(row: r, col: c)
                    flagged = true
                    break
                }
            }
            if flagged { break }
        }

        #expect(gameState.status == .playing)
        #expect(gameState.flagCount == 1)

        gameState.reset()

        #expect(gameState.status == .notStarted)
        #expect(gameState.elapsedTime == 0)
        #expect(gameState.flagCount == 0)
        #expect(gameState.selectedRow == 0)
        #expect(gameState.selectedCol == 0)
    }

    @Test("Reset restores the canonical starting board")
    func testResetRestoresAllCellsToHidden() {
        UserDefaults.standard.removeObject(forKey: "dailyCompletionSeed")
        defer { UserDefaults.standard.removeObject(forKey: "dailyCompletionSeed") }

        let board = Board(seed: 12345)
        let gameState = GameState(board: board, dailySeed: yesterdaySeed())

        gameState.reveal(row: 0, col: 0)
        gameState.reveal(row: 1, col: 1)

        gameState.reset()

        // A reset daily is back to its canonical starting position: fully covered, with the
        // same mines and the same marked safe opening as every other player.
        #expect(gameState.board == Board(dailySeed: gameState.dailySeed),
                "Reset should restore the day's canonical starting board")
    }

    @Test("isPaused is false after reset")
    @MainActor
    func testIsPausedFalseAfterReset() {
        UserDefaults.standard.removeObject(forKey: "dailyCompletionSeed")
        defer { UserDefaults.standard.removeObject(forKey: "dailyCompletionSeed") }

        let board = Board(seed: 12345)
        let gameState = GameState(board: board, dailySeed: yesterdaySeed())

        gameState.reveal(row: 0, col: 0)
        gameState.pauseTimer()
        #expect(gameState.isPaused == true)

        gameState.reset()

        #expect(gameState.isPaused == false)
    }

    // MARK: - Board State Persistence Tests

    @Test("Winning a game saves board state with revealed cells")
    func testWinSavesBoardStateWithRevealedCells() {
        GameSnapshot.clear()
        UserDefaults.standard.removeObject(forKey: "dailyCompletionSeed")
        UserDefaults.standard.removeObject(forKey: "dailyStatsRecordedSeed")
        let todaySeed = seedFromDate(Date())
        UserDefaults.standard.removeObject(forKey: "dailyStats_\(todaySeed)")
        defer {
            GameSnapshot.clear()
            UserDefaults.standard.removeObject(forKey: "dailyCompletionSeed")
            UserDefaults.standard.removeObject(forKey: "dailyStatsRecordedSeed")
            UserDefaults.standard.removeObject(forKey: "dailyStats_\(todaySeed)")
        }

        let board = Board(seed: 12345)
        let gameState = GameState(board: board)

        // Win the game
        winGame(gameState)
        #expect(gameState.status == .won)

        // Verify snapshot was saved
        guard let snapshot = GameSnapshot.load() else {
            Issue.record("Snapshot should exist after winning")
            return
        }

        // Verify the board in snapshot has revealed cells (not all hidden)
        var revealedCount = 0
        for row in snapshot.board.cells {
            for cell in row {
                if case .revealed = cell.state {
                    revealedCount += 1
                }
            }
        }

        #expect(revealedCount > 0, "Snapshot should contain revealed cells")
        #expect(snapshot.status == .won, "Snapshot should have won status")
    }

    @Test("Losing a game saves board state with exploded mine")
    func testLoseSavesBoardStateWithExplodedMine() {
        GameSnapshot.clear()
        UserDefaults.standard.removeObject(forKey: "dailyCompletionSeed")
        UserDefaults.standard.removeObject(forKey: "dailyStatsRecordedSeed")
        let todaySeed = seedFromDate(Date())
        UserDefaults.standard.removeObject(forKey: "dailyStats_\(todaySeed)")
        defer {
            GameSnapshot.clear()
            UserDefaults.standard.removeObject(forKey: "dailyCompletionSeed")
            UserDefaults.standard.removeObject(forKey: "dailyStatsRecordedSeed")
            UserDefaults.standard.removeObject(forKey: "dailyStats_\(todaySeed)")
        }

        let board = Board(seed: 12345)
        let gameState = GameState(board: board)

        // Start game with a safe cell
        guard let safe = findSafeCell(in: gameState.board) else {
            Issue.record("No safe cell found")
            return
        }
        gameState.reveal(row: safe.row, col: safe.col)

        // Lose by clicking a mine
        guard let mine = findMineCell(in: gameState.board) else {
            Issue.record("No mine found")
            return
        }
        gameState.reveal(row: mine.row, col: mine.col)
        #expect(gameState.status == .lost)

        // Verify snapshot was saved
        guard let snapshot = GameSnapshot.load() else {
            Issue.record("Snapshot should exist after losing")
            return
        }

        // Verify the board in snapshot has the exploded mine
        #expect(snapshot.board.cells[mine.row][mine.col].isExploded, "Exploded mine should be saved")
        #expect(snapshot.status == .lost, "Snapshot should have lost status")
    }

    @Test("Restored game after win preserves board state with revealed cells")
    func testRestoredAfterWinPreservesBoardState() {
        GameSnapshot.clear()
        let settingKey = Constants.SettingsKeys.continuousPlay
        let initialSettingValue = UserDefaults.standard.object(forKey: settingKey)
        UserDefaults.standard.removeObject(forKey: "dailyCompletionSeed")
        UserDefaults.standard.removeObject(forKey: "dailyStatsRecordedSeed")
        let todaySeed = seedFromDate(Date())
        UserDefaults.standard.removeObject(forKey: "dailyStats_\(todaySeed)")
        defer {
            GameSnapshot.clear()
            if let initial = initialSettingValue {
                UserDefaults.standard.set(initial, forKey: settingKey)
            } else {
                UserDefaults.standard.removeObject(forKey: settingKey)
            }
            UserDefaults.standard.removeObject(forKey: "dailyCompletionSeed")
            UserDefaults.standard.removeObject(forKey: "dailyStatsRecordedSeed")
            UserDefaults.standard.removeObject(forKey: "dailyStats_\(todaySeed)")
        }

        // Ensure continuousPlay is OFF so restore returns the saved state
        UserDefaults.standard.set(false, forKey: settingKey)

        let board = Board(seed: 12345)
        let gameState = GameState(board: board)

        // Win the game
        winGame(gameState)
        #expect(gameState.status == .won)

        // Count revealed cells in original game
        var originalRevealedCount = 0
        for row in gameState.board.cells {
            for cell in row {
                if case .revealed = cell.state {
                    originalRevealedCount += 1
                }
            }
        }

        // Restore from snapshot
        let restoredState = GameState.restored()

        // Count revealed cells in restored game
        var restoredRevealedCount = 0
        for row in restoredState.board.cells {
            for cell in row {
                if case .revealed = cell.state {
                    restoredRevealedCount += 1
                }
            }
        }

        #expect(restoredState.status == .won, "Restored state should be won")
        #expect(restoredRevealedCount == originalRevealedCount, "Restored board should have same revealed cells")
        #expect(restoredState.board == gameState.board, "Restored board should match original")
    }

    @Test("Restored game after loss preserves board state with exploded mine")
    func testRestoredAfterLossPreservesBoardState() {
        GameSnapshot.clear()
        let settingKey = Constants.SettingsKeys.continuousPlay
        let initialSettingValue = UserDefaults.standard.object(forKey: settingKey)
        UserDefaults.standard.removeObject(forKey: "dailyCompletionSeed")
        UserDefaults.standard.removeObject(forKey: "dailyStatsRecordedSeed")
        let todaySeed = seedFromDate(Date())
        UserDefaults.standard.removeObject(forKey: "dailyStats_\(todaySeed)")
        defer {
            GameSnapshot.clear()
            if let initial = initialSettingValue {
                UserDefaults.standard.set(initial, forKey: settingKey)
            } else {
                UserDefaults.standard.removeObject(forKey: settingKey)
            }
            UserDefaults.standard.removeObject(forKey: "dailyCompletionSeed")
            UserDefaults.standard.removeObject(forKey: "dailyStatsRecordedSeed")
            UserDefaults.standard.removeObject(forKey: "dailyStats_\(todaySeed)")
        }

        // Ensure continuousPlay is OFF so restore returns the saved state
        UserDefaults.standard.set(false, forKey: settingKey)

        let board = Board(seed: 12345)
        let gameState = GameState(board: board)

        // Start game
        guard let safe = findSafeCell(in: gameState.board) else {
            Issue.record("No safe cell found")
            return
        }
        gameState.reveal(row: safe.row, col: safe.col)

        // Lose the game
        guard let mine = findMineCell(in: gameState.board) else {
            Issue.record("No mine found")
            return
        }
        gameState.reveal(row: mine.row, col: mine.col)
        #expect(gameState.status == .lost)

        // Restore from snapshot
        let restoredState = GameState.restored()

        #expect(restoredState.status == .lost, "Restored state should be lost")
        #expect(restoredState.board.cells[mine.row][mine.col].isExploded, "Restored board should have exploded mine")
        #expect(restoredState.board == gameState.board, "Restored board should match original")
    }

    @Test("Completed game with flags preserves flag positions after restore")
    func testRestoredPreservesFlagPositions() {
        GameSnapshot.clear()
        let settingKey = Constants.SettingsKeys.continuousPlay
        let initialSettingValue = UserDefaults.standard.object(forKey: settingKey)
        UserDefaults.standard.removeObject(forKey: "dailyCompletionSeed")
        UserDefaults.standard.removeObject(forKey: "dailyStatsRecordedSeed")
        let todaySeed = seedFromDate(Date())
        UserDefaults.standard.removeObject(forKey: "dailyStats_\(todaySeed)")
        defer {
            GameSnapshot.clear()
            if let initial = initialSettingValue {
                UserDefaults.standard.set(initial, forKey: settingKey)
            } else {
                UserDefaults.standard.removeObject(forKey: settingKey)
            }
            UserDefaults.standard.removeObject(forKey: "dailyCompletionSeed")
            UserDefaults.standard.removeObject(forKey: "dailyStatsRecordedSeed")
            UserDefaults.standard.removeObject(forKey: "dailyStats_\(todaySeed)")
        }

        // Ensure continuousPlay is OFF so restore returns the saved state
        UserDefaults.standard.set(false, forKey: settingKey)

        let board = Board(seed: 12345)
        let gameState = GameState(board: board)

        // Start the game first to trigger first-click clearing
        gameState.reveal(row: 0, col: 0)

        // Find and flag some mines (after first-click clearing)
        var flaggedPositions: [(row: Int, col: Int)] = []
        for r in 0..<Board.rows {
            for c in 0..<Board.cols {
                if gameState.board.cells[r][c].hasMine && flaggedPositions.count < 3 {
                    gameState.toggleFlag(row: r, col: c)
                    flaggedPositions.append((r, c))
                }
            }
        }

        // Win the game - all mines get auto-flagged
        winGame(gameState)
        #expect(gameState.status == .won)
        #expect(gameState.flagCount == Board.mineCount, "All mines should be flagged on win")

        // Restore from snapshot
        let restoredState = GameState.restored()

        // Verify user-placed flag positions are preserved (as part of all mines being flagged)
        for pos in flaggedPositions {
            #expect(restoredState.board.cells[pos.row][pos.col].state == .flagged,
                   "Flag at (\(pos.row), \(pos.col)) should be preserved")
        }
        #expect(restoredState.flagCount == Board.mineCount, "All mines should remain flagged after restore")
    }

    // MARK: - Continuous Play Persistence Tests (GamePersistenceCoordinator)

    @Test("continuousPlay ON + in-progress daily restores that game")
    func testContinuousPlayOnInProgressGetsFreshDaily() {
        GameSnapshot.clear()
        let settingKey = Constants.SettingsKeys.continuousPlay
        let initialSettingValue = UserDefaults.standard.object(forKey: settingKey)
        UserDefaults.standard.removeObject(forKey: "dailyCompletionSeed")
        UserDefaults.standard.removeObject(forKey: "dailyStatsRecordedSeed")
        let todaySeed = seedFromDate(Date())
        UserDefaults.standard.removeObject(forKey: "dailyStats_\(todaySeed)")
        defer {
            GameSnapshot.clear()
            if let initial = initialSettingValue {
                UserDefaults.standard.set(initial, forKey: settingKey)
            } else {
                UserDefaults.standard.removeObject(forKey: settingKey)
            }
            UserDefaults.standard.removeObject(forKey: "dailyCompletionSeed")
            UserDefaults.standard.removeObject(forKey: "dailyStatsRecordedSeed")
            UserDefaults.standard.removeObject(forKey: "dailyStats_\(todaySeed)")
        }

        // Enable continuous play
        UserDefaults.standard.set(true, forKey: settingKey)

        // Create an in-progress game and save it
        let board = Board(dailySeed: todaySeed)
        let gameState = GameState(board: board, dailySeed: todaySeed)
        // Today's seed decides where the mines are, so a fixed cell could be one of them.
        let opening = Board.openingCell(forSeed: todaySeed)
        gameState.reveal(row: opening.row, col: opening.col)
        #expect(gameState.status == .playing)
        gameState.save()

        // Verify snapshot exists
        #expect(GameSnapshot.load() != nil, "Snapshot should exist")

        // Continuous play governs what comes after the daily, not whether it survives a relaunch
        let restoredState = GameState.restored()

        #expect(restoredState.status == .playing, "The game under way should come back")
        #expect(restoredState.puzzleType == .daily, "Should be a daily puzzle")
        #expect(restoredState.board == gameState.board, "Should be the same board")
    }

    @Test("continuousPlay ON + completed daily restores fresh random puzzle")
    func testContinuousPlayOnCompletedGetsRandomPuzzle() {
        GameSnapshot.clear()
        let settingKey = Constants.SettingsKeys.continuousPlay
        let initialSettingValue = UserDefaults.standard.object(forKey: settingKey)
        UserDefaults.standard.removeObject(forKey: "dailyCompletionSeed")
        UserDefaults.standard.removeObject(forKey: "dailyStatsRecordedSeed")
        let todaySeed = seedFromDate(Date())
        UserDefaults.standard.removeObject(forKey: "dailyStats_\(todaySeed)")
        defer {
            GameSnapshot.clear()
            if let initial = initialSettingValue {
                UserDefaults.standard.set(initial, forKey: settingKey)
            } else {
                UserDefaults.standard.removeObject(forKey: settingKey)
            }
            UserDefaults.standard.removeObject(forKey: "dailyCompletionSeed")
            UserDefaults.standard.removeObject(forKey: "dailyStatsRecordedSeed")
            UserDefaults.standard.removeObject(forKey: "dailyStats_\(todaySeed)")
        }

        // Enable continuous play
        UserDefaults.standard.set(true, forKey: settingKey)

        // Complete the daily puzzle
        let board = Board(seed: todaySeed)
        let gameState = GameState(board: board, dailySeed: todaySeed)
        winGame(gameState)
        #expect(gameState.status == .won)
        #expect(isDailyPuzzleComplete(), "Daily should be marked complete")

        // Restore with continuousPlay ON after completion should get a random puzzle
        let restoredState = GameState.restored()

        #expect(restoredState.status == .notStarted, "Should start fresh")
        #expect(restoredState.puzzleType == .random, "Should be a random puzzle when daily is complete")
        #expect(restoredState.elapsedTime == 0, "Should have zero elapsed time")
    }

    @Test("continuousPlay OFF + in-progress daily restores exactly")
    func testContinuousPlayOffInProgressRestoresExactly() {
        GameSnapshot.clear()
        let settingKey = Constants.SettingsKeys.continuousPlay
        let initialSettingValue = UserDefaults.standard.object(forKey: settingKey)
        UserDefaults.standard.removeObject(forKey: "dailyCompletionSeed")
        UserDefaults.standard.removeObject(forKey: "dailyStatsRecordedSeed")
        let todaySeed = seedFromDate(Date())
        UserDefaults.standard.removeObject(forKey: "dailyStats_\(todaySeed)")
        defer {
            GameSnapshot.clear()
            if let initial = initialSettingValue {
                UserDefaults.standard.set(initial, forKey: settingKey)
            } else {
                UserDefaults.standard.removeObject(forKey: settingKey)
            }
            UserDefaults.standard.removeObject(forKey: "dailyCompletionSeed")
            UserDefaults.standard.removeObject(forKey: "dailyStatsRecordedSeed")
            UserDefaults.standard.removeObject(forKey: "dailyStats_\(todaySeed)")
        }

        // Disable continuous play
        UserDefaults.standard.set(false, forKey: settingKey)

        // Create an in-progress game and save it
        let board = Board(dailySeed: todaySeed)
        let gameState = GameState(board: board, dailySeed: todaySeed)
        // Today's seed decides where the mines are, so a fixed cell could be one of them.
        let opening = Board.openingCell(forSeed: todaySeed)
        gameState.reveal(row: opening.row, col: opening.col)
        #expect(gameState.status == .playing)

        // Flag a cell
        var flaggedRow = 0, flaggedCol = 0
        outer: for r in 0..<Board.rows {
            for c in 0..<Board.cols {
                if case .hidden = gameState.board.cells[r][c].state {
                    gameState.toggleFlag(row: r, col: c)
                    flaggedRow = r
                    flaggedCol = c
                    break outer
                }
            }
        }

        gameState.save()

        // Restore with continuousPlay OFF should restore exact state
        let restoredState = GameState.restored()

        #expect(restoredState.status == .playing, "Should restore playing status")
        #expect(restoredState.puzzleType == .daily, "Should be daily puzzle")
        #expect(restoredState.flagCount == 1, "Should restore flag count")
        #expect(restoredState.board.cells[flaggedRow][flaggedCol].state == .flagged,
               "Should restore flag position")
    }

    @Test("continuousPlay OFF + completed daily restores win/loss state")
    func testContinuousPlayOffCompletedRestoresState() {
        GameSnapshot.clear()
        let settingKey = Constants.SettingsKeys.continuousPlay
        let initialSettingValue = UserDefaults.standard.object(forKey: settingKey)
        UserDefaults.standard.removeObject(forKey: "dailyCompletionSeed")
        UserDefaults.standard.removeObject(forKey: "dailyStatsRecordedSeed")
        let todaySeed = seedFromDate(Date())
        UserDefaults.standard.removeObject(forKey: "dailyStats_\(todaySeed)")
        defer {
            GameSnapshot.clear()
            if let initial = initialSettingValue {
                UserDefaults.standard.set(initial, forKey: settingKey)
            } else {
                UserDefaults.standard.removeObject(forKey: settingKey)
            }
            UserDefaults.standard.removeObject(forKey: "dailyCompletionSeed")
            UserDefaults.standard.removeObject(forKey: "dailyStatsRecordedSeed")
            UserDefaults.standard.removeObject(forKey: "dailyStats_\(todaySeed)")
        }

        // Disable continuous play
        UserDefaults.standard.set(false, forKey: settingKey)

        // Complete the daily puzzle
        let board = Board(seed: todaySeed)
        let gameState = GameState(board: board, dailySeed: todaySeed)
        winGame(gameState)
        let elapsedTimeAtWin = gameState.elapsedTime
        #expect(gameState.status == .won)

        // Restore with continuousPlay OFF after completion should restore the won state
        let restoredState = GameState.restored()

        #expect(restoredState.status == .won, "Should restore won status")
        #expect(restoredState.puzzleType == .daily, "Should be daily puzzle")
        #expect(restoredState.elapsedTime == elapsedTimeAtWin, "Should restore elapsed time")
    }

    @Test("continuousPlay ON + yesterday's in-progress does not delay rollover")
    func testContinuousPlayOnNoRolloverDelay() {
        GameSnapshot.clear()
        let settingKey = Constants.SettingsKeys.continuousPlay
        let initialSettingValue = UserDefaults.standard.object(forKey: settingKey)
        UserDefaults.standard.removeObject(forKey: "dailyCompletionSeed")
        UserDefaults.standard.removeObject(forKey: "dailyStatsRecordedSeed")
        let todaySeed = seedFromDate(Date())
        let yesterdaySeed = todaySeed - 1
        UserDefaults.standard.removeObject(forKey: "dailyStats_\(todaySeed)")
        UserDefaults.standard.removeObject(forKey: "dailyStats_\(yesterdaySeed)")
        defer {
            GameSnapshot.clear()
            if let initial = initialSettingValue {
                UserDefaults.standard.set(initial, forKey: settingKey)
            } else {
                UserDefaults.standard.removeObject(forKey: settingKey)
            }
            UserDefaults.standard.removeObject(forKey: "dailyCompletionSeed")
            UserDefaults.standard.removeObject(forKey: "dailyStatsRecordedSeed")
            UserDefaults.standard.removeObject(forKey: "dailyStats_\(todaySeed)")
            UserDefaults.standard.removeObject(forKey: "dailyStats_\(yesterdaySeed)")
        }

        // Enable continuous play
        UserDefaults.standard.set(true, forKey: settingKey)

        // Create a snapshot from yesterday with .playing status
        let yesterdayBoard = Board(seed: yesterdaySeed)
        let snapshot = GameSnapshot(
            board: yesterdayBoard,
            status: .playing,
            elapsedTime: 50.0,
            flagCount: 2,
            selectedRow: 3,
            selectedCol: 3,
            dailySeed: yesterdaySeed,
            puzzleType: .daily
        )
        snapshot.save()

        // Restore with continuousPlay ON should NOT delay rollover
        // It should give a fresh daily puzzle for today, not yesterday's in-progress game
        let restoredState = GameState.restored()

        #expect(restoredState.status == .notStarted, "Should start fresh, not restore yesterday's game")
        #expect(restoredState.puzzleType == .daily, "Should be today's daily puzzle")
        #expect(restoredState.elapsedTime == 0, "Should have zero elapsed time")
    }

    // MARK: - Daily Namespace Snapshot Tests

    @Test("Toggling continuous play OFF restores daily snapshot with full board state")
    func testTogglingContinuousPlayOffRestoresDailySnapshot() {
        let cleanup = setupCleanPersistenceState(continuousPlay: true)
        defer { cleanup() }

        let todaySeed = seedFromDate(Date())
        let board = Board(seed: todaySeed)
        let gameState = GameState(board: board, dailySeed: todaySeed)

        // Win the game - this saves to daily namespace
        winGame(gameState)
        #expect(gameState.status == .won)
        #expect(gameState.puzzleType == .daily)

        let revealedCellCount = countRevealedCells(in: gameState.board)
        #expect(revealedCellCount > 0, "Won game should have revealed cells")

        // Reset to start a random puzzle (clears main snapshot)
        gameState.reset()
        #expect(gameState.puzzleType == .random, "Should be on random puzzle after reset")
        #expect(gameState.status == .notStarted)

        // Verify main snapshot was cleared
        #expect(GameSnapshot.load() == nil, "Main snapshot should be cleared after reset to random")

        // Turn continuous play OFF
        UserDefaults.standard.set(false, forKey: Constants.SettingsKeys.continuousPlay)

        // Restore - should get daily snapshot with revealed cells
        let restoredState = GameState.restored()

        #expect(restoredState.status == .won, "Should restore won status")
        #expect(restoredState.puzzleType == .daily, "Should restore daily puzzle type")

        let restoredRevealedCount = countRevealedCells(in: restoredState.board)
        #expect(restoredRevealedCount == revealedCellCount,
               "Restored board should have same revealed cells as completed game")
    }

    @Test("Daily namespace snapshot is cleared on day rollover")
    func testDailyNamespaceClearedOnRollover() {
        let cleanup = setupCleanPersistenceState()
        let todaySeed = seedFromDate(Date())
        let yesterdaySeed = todaySeed - 1
        UserDefaults.standard.removeObject(forKey: "dailyStats_\(yesterdaySeed)")
        defer {
            cleanup()
            UserDefaults.standard.removeObject(forKey: "dailyStats_\(yesterdaySeed)")
        }

        // Create a daily namespace snapshot with yesterday's seed (simulating day rollover scenario)
        let yesterdayBoard = Board(seed: yesterdaySeed)
        let snapshot = GameSnapshot(
            board: yesterdayBoard,
            status: .won,
            elapsedTime: 100.0,
            flagCount: 12,
            selectedRow: 0,
            selectedCol: 0,
            dailySeed: yesterdaySeed,
            puzzleType: .daily
        )
        GameSnapshot.withStorageKey(GameSnapshot.dailyNamespace) {
            snapshot.save()
        }

        // Verify daily namespace has the snapshot
        let savedSnapshot: GameSnapshot? = GameSnapshot.withStorageKey(GameSnapshot.dailyNamespace) {
            GameSnapshot.loadAnyDay()
        }
        #expect(savedSnapshot != nil, "Daily namespace should have snapshot before rollover")
        #expect(savedSnapshot?.dailySeed == yesterdaySeed, "Snapshot should be from yesterday")

        // Create a game state and trigger rollover by opening popover (checkForDailyRollover)
        let board = Board(seed: yesterdaySeed)
        let gameState = GameState(board: board, dailySeed: yesterdaySeed)

        // Simulate popover appearance which triggers rollover check
        gameState.checkForDailyRollover()

        // After rollover, daily namespace should be cleared
        let afterRolloverSnapshot: GameSnapshot? = GameSnapshot.withStorageKey(GameSnapshot.dailyNamespace) {
            GameSnapshot.loadAnyDay()
        }
        #expect(afterRolloverSnapshot == nil, "Daily namespace should be cleared after rollover")
        #expect(gameState.dailySeed == todaySeed, "Game should be on today's seed after rollover")
    }

    @Test("checkContinuousPlaySetting restores daily snapshot with full board state")
    func testCheckContinuousPlaySettingRestoresDailySnapshot() {
        let cleanup = setupCleanPersistenceState(continuousPlay: true)
        defer { cleanup() }

        let todaySeed = seedFromDate(Date())
        let board = Board(seed: todaySeed)
        let gameState = GameState(board: board, dailySeed: todaySeed)

        // Complete the daily puzzle - this saves to daily namespace
        winGame(gameState)
        #expect(gameState.status == .won)

        let revealedCount = countRevealedCells(in: gameState.board)

        // Reset to random puzzle
        gameState.reset()
        #expect(gameState.puzzleType == .random)

        // Disable continuous play
        UserDefaults.standard.set(false, forKey: Constants.SettingsKeys.continuousPlay)

        // Call checkContinuousPlaySetting - should restore daily state with board
        gameState.checkContinuousPlaySetting()

        #expect(gameState.puzzleType == .daily, "Should be back on daily puzzle")
        #expect(gameState.status == .won, "Should have won status")

        let restoredRevealedCount = countRevealedCells(in: gameState.board)
        #expect(restoredRevealedCount == revealedCount,
               "Board should have same revealed cells as original completed game")
    }

    @Test("Multiple random puzzles don't affect daily namespace")
    func testMultipleRandomPuzzlesDontAffectDailyNamespace() {
        let cleanup = setupCleanPersistenceState(continuousPlay: true)
        defer { cleanup() }

        let todaySeed = seedFromDate(Date())
        let board = Board(seed: todaySeed)
        let gameState = GameState(board: board, dailySeed: todaySeed)

        // Complete daily puzzle
        winGame(gameState)
        let dailyElapsedTime = gameState.elapsedTime

        // Verify daily namespace has snapshot
        let afterWinSnapshot: GameSnapshot? = GameSnapshot.withStorageKey(GameSnapshot.dailyNamespace) {
            GameSnapshot.load()
        }
        #expect(afterWinSnapshot != nil, "Daily namespace should have snapshot after win")

        // Play multiple random puzzles
        for _ in 0..<3 {
            gameState.reset()
            #expect(gameState.puzzleType == .random)
            // Start and play the random game a bit
            gameState.reveal(row: 0, col: 0)
        }

        // Daily namespace should still have the original snapshot
        let afterRandomsSnapshot: GameSnapshot? = GameSnapshot.withStorageKey(GameSnapshot.dailyNamespace) {
            GameSnapshot.load()
        }
        #expect(afterRandomsSnapshot != nil, "Daily namespace should still have snapshot after random puzzles")
        #expect(afterRandomsSnapshot?.elapsedTime == dailyElapsedTime,
               "Daily snapshot should preserve original elapsed time")
        #expect(afterRandomsSnapshot?.status == .won, "Daily snapshot should preserve won status")
    }

    // MARK: - Marked Mine Count Tests

    @Test("Marked mine count survives a relaunch")
    func testMarkedMineCountSurvivesRelaunch() {
        let cleanup = setupCleanPersistenceState(continuousPlay: false)
        defer { cleanup() }

        let seed = seedFromDate(Date())
        let gameState = GameState(board: Board(dailySeed: seed), dailySeed: seed)

        // Today's seed decides where the mines are, so a fixed cell could be one of them.
        let opening = Board.openingCell(forSeed: seed)
        gameState.reveal(row: opening.row, col: opening.col)
        #expect(gameState.status == .playing)

        var flagged = 0
        for r in 0..<Board.rows {
            for c in 0..<Board.cols where flagged < 3 {
                if gameState.board.cells[r][c].hasMine {
                    gameState.toggleFlag(row: r, col: c)
                    flagged += 1
                }
            }
        }
        #expect(flagged == 3)

        winGame(gameState)
        #expect(gameState.status == .won)
        #expect(gameState.markedMinesAtWin == 3)

        let shareDate = dateFromSeed(seed) ?? Date()
        let restored = GameState.restored()

        #expect(restored.status == .won)
        #expect(
            restored.markedMinesAtWin == 3,
            "Winning auto-flags every mine, so the player's count has to come from the snapshot"
        )
        #expect(restored.shareText(for: shareDate) == gameState.shareText(for: shareDate))
    }

    @Test("Snapshots written before marked mines were tracked decode to zero")
    func testLegacySnapshotDecodesMarkedMinesToZero() throws {
        let snapshot = GameSnapshot(
            board: Board(seed: 20260101),
            status: .won,
            elapsedTime: 42,
            flagCount: 12,
            selectedRow: 0,
            selectedCol: 0,
            dailySeed: 20260101,
            puzzleType: .daily,
            markedMinesAtWin: 7
        )
        let encoded = try JSONEncoder().encode(snapshot)
        var object = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "markedMinesAtWin")

        let legacy = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(GameSnapshot.self, from: legacy)

        #expect(decoded.markedMinesAtWin == 0)
        #expect(decoded.status == .won)
        #expect(decoded.elapsedTime == 42)
    }
}
