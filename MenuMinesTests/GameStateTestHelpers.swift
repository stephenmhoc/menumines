import Foundation
import Testing
@testable import MenuMines

// MARK: - Shared Test Helpers

/// Helper to run the main RunLoop for a duration, allowing Timer to fire
func runLoopFor(seconds: TimeInterval) {
    let deadline = Date(timeIntervalSinceNow: seconds)
    while Date() < deadline {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
    }
}

/// Yesterday's daily seed. Subtracting one from today's isn't a date on the 1st of a month.
func yesterdaySeed() -> Int64 {
    seedFromDate(Date().addingTimeInterval(-86_400))
}

/// Helper to find the first safe (non-mine) cell in a board
func findSafeCell(in board: Board) -> (row: Int, col: Int)? {
    for r in 0..<Board.rows {
        for c in 0..<Board.cols {
            if !board.cells[r][c].hasMine {
                return (r, c)
            }
        }
    }
    return nil
}

/// Helper to find the first mine cell in a board
func findMineCell(in board: Board) -> (row: Int, col: Int)? {
    for r in 0..<Board.rows {
        for c in 0..<Board.cols {
            if board.cells[r][c].hasMine {
                return (r, c)
            }
        }
    }
    return nil
}

/// Helper to win the game by revealing all non-mine cells
func winGame(_ gameState: GameState) {
    for r in 0..<Board.rows {
        for c in 0..<Board.cols {
            if !gameState.board.cells[r][c].hasMine {
                gameState.reveal(row: r, col: c)
            }
        }
    }
}

/// Helper to verify all cells are hidden
func expectAllCellsHidden(in gameState: GameState) {
    for r in 0..<Board.rows {
        for c in 0..<Board.cols {
            #expect(gameState.board.cells[r][c].state == .hidden)
        }
    }
}

/// Helper to find the first hidden cell in a game state
func findHiddenCell(in gameState: GameState) -> (row: Int, col: Int)? {
    for r in 0..<Board.rows {
        for c in 0..<Board.cols {
            if case .hidden = gameState.board.cells[r][c].state {
                return (r, c)
            }
        }
    }
    return nil
}

/// Helper to count revealed cells in a board
func countRevealedCells(in board: Board) -> Int {
    var count = 0
    for row in board.cells {
        for cell in row {
            if case .revealed = cell.state {
                count += 1
            }
        }
    }
    return count
}

/// Helper to set up clean persistence state for testing.
/// Clears all snapshots and optionally sets continuous play.
/// Returns a cleanup closure to restore original state in defer block.
func setupCleanPersistenceState(continuousPlay: Bool? = nil) -> () -> Void {
    let settingKey = Constants.SettingsKeys.continuousPlay
    let initialSettingValue = UserDefaults.standard.object(forKey: settingKey)
    let todaySeed = seedFromDate(Date())

    // Clear all persistence state
    GameSnapshot.clear()
    GameSnapshot.withStorageKey(GameSnapshot.dailyNamespace) { GameSnapshot.clear() }
    UserDefaults.standard.removeObject(forKey: "dailyCompletionSeed")
    UserDefaults.standard.removeObject(forKey: "dailyStatsRecordedSeed")
    UserDefaults.standard.removeObject(forKey: "dailyStats_\(todaySeed)")

    // Set continuous play if specified
    if let continuousPlay = continuousPlay {
        UserDefaults.standard.set(continuousPlay, forKey: settingKey)
    }

    // Return cleanup closure
    return {
        GameSnapshot.clear()
        GameSnapshot.withStorageKey(GameSnapshot.dailyNamespace) { GameSnapshot.clear() }
        if let initial = initialSettingValue {
            UserDefaults.standard.set(initial, forKey: settingKey)
        } else {
            UserDefaults.standard.removeObject(forKey: settingKey)
        }
        UserDefaults.standard.removeObject(forKey: "dailyCompletionSeed")
        UserDefaults.standard.removeObject(forKey: "dailyStatsRecordedSeed")
        UserDefaults.standard.removeObject(forKey: "dailyStats_\(todaySeed)")
    }
}
