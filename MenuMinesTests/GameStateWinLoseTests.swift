import Foundation
import Testing
@testable import MenuMines

@Suite("GameState Win/Lose Tests")
struct GameStateWinLoseTests {

    @Test("Lose when clicking a mine")
    func testLoseWhenClickingMine() {
        let board = Board(seed: 12345)
        let gameState = GameState(board: board)

        guard let safe = findSafeCell(in: gameState.board) else {
            Issue.record("No safe cell found")
            return
        }
        gameState.reveal(row: safe.row, col: safe.col)
        #expect(gameState.status == .playing)

        guard let mine = findMineCell(in: gameState.board) else {
            Issue.record("No mine found")
            return
        }
        gameState.reveal(row: mine.row, col: mine.col)

        #expect(gameState.status == .lost)
        #expect(gameState.board.cells[mine.row][mine.col].isExploded)
    }

    @Test("Win when all non-mine cells are revealed")
    func testWinWhenAllNonMinesRevealed() {
        let board = Board(seed: 12345)
        let gameState = GameState(board: board)

        winGame(gameState)

        #expect(gameState.status == .won)
    }

    @Test("First click never hits a mine")
    func testFirstClickNeverHitsMine() {
        // Use a seed where we know position (0,0) has a mine
        // Try multiple seeds to find one where (0,0) has a mine
        var testSeed: Int64 = 1
        var foundSeed = false

        for seed in 1...1000 {
            let testBoard = Board(seed: Int64(seed))
            if testBoard.cells[0][0].hasMine {
                testSeed = Int64(seed)
                foundSeed = true
                break
            }
        }

        guard foundSeed else {
            Issue.record("Could not find a seed where (0,0) has a mine")
            return
        }

        // Now test that first click on (0,0) doesn't lose
        let board = Board(seed: testSeed)
        let gameState = GameState(board: board, dailySeed: testSeed, puzzleType: .random)

        // Verify the board originally has a mine at (0,0)
        #expect(board.cells[0][0].hasMine)

        // First click should not result in loss
        gameState.reveal(row: 0, col: 0)

        #expect(gameState.status == .playing, "First click should never lose, mine should be relocated")
        #expect(!gameState.board.cells[0][0].hasMine, "Mine should have been relocated from first click position")
    }

    @Test("First click relocates mine and preserves mine count")
    func testFirstClickRelocatesMinePreservesMineCount() {
        // Find a seed where (0,0) has a mine
        var testSeed: Int64 = 1
        for seed in 1...1000 {
            let testBoard = Board(seed: Int64(seed))
            if testBoard.cells[0][0].hasMine {
                testSeed = Int64(seed)
                break
            }
        }

        let board = Board(seed: testSeed)
        let gameState = GameState(board: board, dailySeed: testSeed, puzzleType: .random)

        // First click on (0,0) which has a mine
        gameState.reveal(row: 0, col: 0)

        // Count mines after first click
        var mineCount = 0
        for r in 0..<Board.rows {
            for c in 0..<Board.cols {
                if gameState.board.cells[r][c].hasMine {
                    mineCount += 1
                }
            }
        }

        #expect(mineCount == Board.mineCount, "Mine count should remain \(Board.mineCount) after first-click relocation")
    }

    @Test("First click always reveals multiple cells (opening)")
    func testFirstClickAlwaysRevealsMultipleCells() {
        // Test across multiple seeds and click positions
        let seeds: [Int64] = [12345, 20240101, 99999, 1, 20261231]
        let positions = [(0, 0), (4, 4), (8, 8), (0, 4), (4, 0)]

        for seed in seeds {
            for (row, col) in positions {
                let board = Board(seed: seed)
                let gameState = GameState(board: board, dailySeed: seed, puzzleType: .random)

                gameState.reveal(row: row, col: col)

                // Count revealed cells
                var revealedCount = 0
                for r in 0..<Board.rows {
                    for c in 0..<Board.cols {
                        if case .revealed = gameState.board.cells[r][c].state {
                            revealedCount += 1
                        }
                    }
                }

                #expect(revealedCount > 1,
                        "First click at (\(row),\(col)) with seed \(seed) should reveal multiple cells, got \(revealedCount)")
            }
        }
    }

    @Test("First click clears 3x3 area of mines")
    func testFirstClickClears3x3Area() {
        let board = Board(seed: 12345)
        let gameState = GameState(board: board, dailySeed: 12345, puzzleType: .random)

        // Click center
        gameState.reveal(row: 4, col: 4)

        // Verify all 9 cells in 3x3 have no mines
        for dr in -1...1 {
            for dc in -1...1 {
                let r = 4 + dr
                let c = 4 + dc
                #expect(!gameState.board.cells[r][c].hasMine,
                        "Cell at (\(r),\(c)) should have no mine after first click")
            }
        }
    }

    @Test("First click produces deterministic board")
    func testFirstClickIsDeterministic() {
        // Same seed + same click position should produce identical boards
        let board1 = Board(seed: 12345)
        let gameState1 = GameState(board: board1, dailySeed: 12345)

        let board2 = Board(seed: 12345)
        let gameState2 = GameState(board: board2, dailySeed: 12345)

        gameState1.reveal(row: 4, col: 4)
        gameState2.reveal(row: 4, col: 4)

        #expect(gameState1.board == gameState2.board,
                "Same seed + same first click should produce identical boards")
    }

    @Test("Flags allowed before first reveal, without starting the game")
    func testFlagsAllowedBeforeFirstReveal() {
        let board = Board(seed: 12345)
        let gameState = GameState(board: board)

        #expect(gameState.status == .notStarted)

        gameState.toggleFlag(row: 0, col: 0)

        #expect(gameState.flagCount == 1, "A right click on a fresh board should place a flag")
        #expect(gameState.board.cells[0][0].state == .flagged)
        #expect(gameState.status == .notStarted, "Only a reveal starts the game")
    }

    @Test("Cannot reveal after game is lost")
    func testCannotRevealAfterGameLost() {
        let board = Board(seed: 12345)
        let gameState = GameState(board: board)

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

        guard let hidden = findHiddenCell(in: gameState) else {
            Issue.record("No hidden cell found")
            return
        }

        gameState.reveal(row: hidden.row, col: hidden.col)
        #expect(gameState.board.cells[hidden.row][hidden.col].state == .hidden, "Should not be able to reveal after losing")
    }

    @Test("Cannot reveal after game is won")
    func testCannotRevealAfterGameWon() {
        let board = Board(seed: 12345)
        let gameState = GameState(board: board)

        winGame(gameState)
        #expect(gameState.status == .won)

        guard let mine = findMineCell(in: gameState.board) else {
            Issue.record("No mine found")
            return
        }

        gameState.reveal(row: mine.row, col: mine.col)
        #expect(gameState.status == .won, "Status should still be won")
    }
}
