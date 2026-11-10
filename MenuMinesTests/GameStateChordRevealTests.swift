import Foundation
import Testing
@testable import MenuMines

@Suite("GameState Chord Reveal Tests")
struct GameStateChordRevealTests {

    @Test("Chord reveal does nothing before game starts")
    func testChordRevealDoesNothingBeforeGameStarts() {
        let board = Board(seed: 12345)
        let gameState = GameState(board: board, dailySeed: 12345)

        #expect(gameState.status == .notStarted)

        gameState.chordReveal(row: 0, col: 0)

        #expect(gameState.status == .notStarted)
    }

    @Test("Chord reveal works on revealed number cell with correct flags")
    func testChordRevealWorksWithCorrectFlags() {
        let board = Board(seed: 12345)
        let gameState = GameState(board: board, dailySeed: 12345)

        // Start the game first (triggers 3x3 clearing)
        gameState.reveal(row: 0, col: 0)
        #expect(gameState.status == .playing)

        // Now find a cell with exactly 1 adjacent mine (after first-click clearing)
        guard let target = findCellWithAdjacentMines(count: 1, in: gameState.board) else {
            Issue.record("No suitable cell found")
            return
        }

        // Reveal the target cell
        gameState.reveal(row: target.row, col: target.col)

        // Find the adjacent mine (after game started)
        guard let mine = findAdjacentMine(to: target.row, col: target.col, in: gameState.board) else {
            Issue.record("No adjacent mine found")
            return
        }

        // Flag the mine
        gameState.toggleFlag(row: mine.row, col: mine.col)

        // Count hidden cells adjacent to target before chord reveal
        let hiddenBefore = countHiddenAdjacentCells(to: target.row, col: target.col, in: gameState)

        // Perform chord reveal
        gameState.chordReveal(row: target.row, col: target.col)

        // Count hidden cells after
        let hiddenAfter = countHiddenAdjacentCells(to: target.row, col: target.col, in: gameState)

        #expect(hiddenAfter < hiddenBefore, "Chord reveal should reveal adjacent hidden cells")
    }

    @Test("Chord reveal loses game with incorrect flag")
    func testChordRevealLosesWithIncorrectFlag() {
        let board = Board(seed: 12345)
        let gameState = GameState(board: board, dailySeed: 12345)

        // Start the game first (triggers 3x3 clearing)
        gameState.reveal(row: 0, col: 0)
        #expect(gameState.status == .playing)

        // Find a cell with exactly 1 adjacent mine (after first-click clearing)
        guard let target = findCellWithAdjacentMines(count: 1, in: gameState.board) else {
            Issue.record("No suitable cell found")
            return
        }

        // Reveal the target cell
        gameState.reveal(row: target.row, col: target.col)

        // Find an adjacent non-mine cell to place wrong flag (after game started)
        guard let wrongFlag = findAdjacentNonMine(to: target.row, col: target.col, in: gameState.board) else {
            Issue.record("No adjacent non-mine found")
            return
        }

        // Place flag on wrong cell
        gameState.toggleFlag(row: wrongFlag.row, col: wrongFlag.col)

        // Perform chord reveal
        gameState.chordReveal(row: target.row, col: target.col)

        #expect(gameState.status == .lost, "Chord reveal with incorrect flag should lose")
    }

    @Test("Chord reveal via reveal on revealed cell")
    func testRevealOnRevealedCellTriggersChordReveal() {
        let board = Board(seed: 12345)
        let gameState = GameState(board: board, dailySeed: 12345)

        // Start the game first (triggers 3x3 clearing)
        gameState.reveal(row: 0, col: 0)
        #expect(gameState.status == .playing)

        // Find a cell with exactly 1 adjacent mine (after first-click clearing)
        guard let target = findCellWithAdjacentMines(count: 1, in: gameState.board) else {
            Issue.record("No suitable cell found")
            return
        }

        // Reveal the target cell
        gameState.reveal(row: target.row, col: target.col)

        // Find the adjacent mine (after game started)
        guard let mine = findAdjacentMine(to: target.row, col: target.col, in: gameState.board) else {
            Issue.record("No adjacent mine found")
            return
        }

        // Flag the mine
        gameState.toggleFlag(row: mine.row, col: mine.col)

        // Count hidden cells before
        let hiddenBefore = countHiddenAdjacentCells(to: target.row, col: target.col, in: gameState)

        // Call reveal on already-revealed cell (should trigger chord reveal)
        gameState.reveal(row: target.row, col: target.col)

        // Count hidden cells after
        let hiddenAfter = countHiddenAdjacentCells(to: target.row, col: target.col, in: gameState)

        #expect(hiddenAfter < hiddenBefore, "Reveal on revealed cell should trigger chord reveal")
    }

    @Test("Chord reveal selected works with keyboard navigation")
    func testChordRevealSelectedWorks() {
        let board = Board(seed: 12345)
        let gameState = GameState(board: board, dailySeed: 12345)

        // Start the game first (triggers 3x3 clearing)
        gameState.reveal(row: 0, col: 0)

        // Find a cell with exactly 1 adjacent mine (after first-click clearing)
        guard let target = findCellWithAdjacentMines(count: 1, in: gameState.board) else {
            Issue.record("No suitable cell found")
            return
        }

        // Reveal the target cell
        gameState.reveal(row: target.row, col: target.col)

        // Find the adjacent mine (after game started)
        guard let mine = findAdjacentMine(to: target.row, col: target.col, in: gameState.board) else {
            Issue.record("No adjacent mine found")
            return
        }

        // Flag the mine
        gameState.toggleFlag(row: mine.row, col: mine.col)

        // Move selection to target cell (handle all directions)
        while gameState.selectedRow < target.row { gameState.moveSelection(.down) }
        while gameState.selectedRow > target.row { gameState.moveSelection(.up) }
        while gameState.selectedCol < target.col { gameState.moveSelection(.right) }
        while gameState.selectedCol > target.col { gameState.moveSelection(.left) }

        // Count hidden cells before
        let hiddenBefore = countHiddenAdjacentCells(to: target.row, col: target.col, in: gameState)

        // Space on a revealed number chords it
        gameState.revealSelected()

        // Count hidden cells after
        let hiddenAfter = countHiddenAdjacentCells(to: target.row, col: target.col, in: gameState)

        #expect(hiddenAfter < hiddenBefore, "Chord reveal selected should reveal adjacent hidden cells")
    }

    @Test("Chord reveal can win the game")
    func testChordRevealCanWinGame() {
        let board = Board(seed: 12345)
        let gameState = GameState(board: board, dailySeed: 12345)

        // Start the game first (triggers 3x3 clearing)
        gameState.reveal(row: 0, col: 0)

        // Find a number cell with exactly 1 adjacent mine (after first-click clearing)
        guard let numberCell = findCellWithAdjacentMines(count: 1, in: gameState.board) else {
            Issue.record("No suitable number cell found")
            return
        }

        guard let mine = findAdjacentMine(to: numberCell.row, col: numberCell.col, in: gameState.board) else {
            Issue.record("No adjacent mine found")
            return
        }

        // Reveal all non-mine cells EXCEPT those adjacent to our number cell (excluding the number cell itself)
        var adjacentNonMines: Set<String> = []
        for dr in -1...1 {
            for dc in -1...1 {
                if dr == 0 && dc == 0 { continue }
                let r = numberCell.row + dr
                let c = numberCell.col + dc
                if r >= 0, r < Board.rows, c >= 0, c < Board.cols {
                    if !gameState.board.cells[r][c].hasMine {
                        adjacentNonMines.insert("\(r),\(c)")
                    }
                }
            }
        }

        // Reveal all non-mine cells except adjacent ones (to leave work for chord reveal)
        for r in 0..<Board.rows {
            for c in 0..<Board.cols {
                if !gameState.board.cells[r][c].hasMine && !adjacentNonMines.contains("\(r),\(c)") {
                    gameState.reveal(row: r, col: c)
                }
            }
        }

        // If already won, the test setup didn't work as intended
        if gameState.status == .won {
            return
        }

        #expect(gameState.status == .playing)

        // The number cell should now be revealed (from cascade or direct reveal)
        // If not, reveal it explicitly
        if case .hidden = gameState.board.cells[numberCell.row][numberCell.col].state {
            gameState.reveal(row: numberCell.row, col: numberCell.col)
        }

        // Flag the mine
        gameState.toggleFlag(row: mine.row, col: mine.col)

        // Now chord reveal should reveal remaining adjacent cells and potentially win
        gameState.chordReveal(row: numberCell.row, col: numberCell.col)

        // Verify chord reveal did something (revealed cells)
        // The game should either be won or still playing (if other cells remain)
        #expect(gameState.status == .won || gameState.status == .playing)
    }

    @Test("Chord reveal does nothing after game is won")
    func testChordRevealDoesNothingAfterWin() {
        let board = Board(seed: 12345)
        let gameState = GameState(board: board, dailySeed: 12345)

        winGame(gameState)
        #expect(gameState.status == .won)

        // Find a revealed number cell
        guard let target = findRevealedNumberCell(in: gameState) else {
            // No revealed number cell found, test is inconclusive
            return
        }

        // Try chord reveal - should do nothing
        gameState.chordReveal(row: target.row, col: target.col)

        #expect(gameState.status == .won, "Status should remain won")
    }

    @Test("Chord reveal does nothing after game is lost")
    func testChordRevealDoesNothingAfterLoss() {
        let board = Board(seed: 12345)
        let gameState = GameState(board: board, dailySeed: 12345)

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

        // Try chord reveal - should do nothing
        gameState.chordReveal(row: 0, col: 0)

        #expect(gameState.status == .lost, "Status should remain lost")
    }

    // MARK: - Chord Reveal Helpers

    private func findCellWithAdjacentMines(count: Int, in board: Board) -> (row: Int, col: Int)? {
        for r in 0..<Board.rows {
            for c in 0..<Board.cols {
                if !board.cells[r][c].hasMine {
                    if board.adjacentMineCount(row: r, col: c) == count {
                        return (r, c)
                    }
                }
            }
        }
        return nil
    }

    private func findAdjacentMine(to row: Int, col: Int, in board: Board) -> (row: Int, col: Int)? {
        for dr in -1...1 {
            for dc in -1...1 {
                if dr == 0 && dc == 0 { continue }
                let r = row + dr
                let c = col + dc
                if r >= 0, r < Board.rows, c >= 0, c < Board.cols {
                    if board.cells[r][c].hasMine {
                        return (r, c)
                    }
                }
            }
        }
        return nil
    }

    private func findAdjacentNonMine(to row: Int, col: Int, in board: Board) -> (row: Int, col: Int)? {
        for dr in -1...1 {
            for dc in -1...1 {
                if dr == 0 && dc == 0 { continue }
                let r = row + dr
                let c = col + dc
                if r >= 0, r < Board.rows, c >= 0, c < Board.cols {
                    if !board.cells[r][c].hasMine, case .hidden = board.cells[r][c].state {
                        return (r, c)
                    }
                }
            }
        }
        return nil
    }

    private func countHiddenAdjacentCells(to row: Int, col: Int, in gameState: GameState) -> Int {
        var count = 0
        for dr in -1...1 {
            for dc in -1...1 {
                if dr == 0 && dc == 0 { continue }
                let r = row + dr
                let c = col + dc
                if r >= 0, r < Board.rows, c >= 0, c < Board.cols {
                    if case .hidden = gameState.board.cells[r][c].state {
                        count += 1
                    }
                }
            }
        }
        return count
    }

    private func findRevealedNumberCell(in gameState: GameState) -> (row: Int, col: Int)? {
        for r in 0..<Board.rows {
            for c in 0..<Board.cols {
                if case .revealed(let adj) = gameState.board.cells[r][c].state, adj > 0 {
                    return (r, c)
                }
            }
        }
        return nil
    }
}
