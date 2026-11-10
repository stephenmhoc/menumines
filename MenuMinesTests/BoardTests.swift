import XCTest
@testable import MenuMines

final class BoardTests: XCTestCase {

    // MARK: - Story 3A: Seeded Mine Placement

    func testSameSeedProducesSameBoard() {
        let board1 = Board(seed: 20240315)
        let board2 = Board(seed: 20240315)

        XCTAssertEqual(board1.cells, board2.cells)
    }

    func testDifferentSeedsProduceDifferentBoards() {
        let board1 = Board(seed: 20240315)
        let board2 = Board(seed: 20240316)

        XCTAssertNotEqual(board1.cells, board2.cells)
    }

    func testAllCellsStartHidden() {
        let board = Board(seed: 12345)

        for row in board.cells {
            for cell in row {
                XCTAssertEqual(cell.state, .hidden)
            }
        }
    }

    func testBoardHasCorrectDimensions() {
        let board = Board(seed: 12345)

        XCTAssertEqual(board.cells.count, 9)
        for row in board.cells {
            XCTAssertEqual(row.count, 9)
        }
    }

    func testMultipleSeedsAllHaveCorrectMineCount() {
        let seeds: [Int64] = [1, 100, 20240101, 20241231, 99999999]

        for seed in seeds {
            let board = Board(seed: seed)
            var mineCount = 0
            for row in board.cells {
                for cell in row where cell.hasMine {
                    mineCount += 1
                }
            }
            XCTAssertEqual(mineCount, Board.mineCount, "Board with seed \(seed) should have exactly \(Board.mineCount) mines")
        }
    }

    func testNoCellsStartExploded() {
        let board = Board(seed: 12345)

        for row in board.cells {
            for cell in row {
                XCTAssertFalse(cell.isExploded)
            }
        }
    }

    func testEdgeCaseSeeds() {
        let extremeSeeds: [Int64] = [Int64.min, -1, 0, Int64.max]

        for seed in extremeSeeds {
            let board = Board(seed: seed)
            let mineCount = board.cells.flatMap { $0 }.filter(\.hasMine).count
            XCTAssertEqual(mineCount, Board.mineCount, "Seed \(seed) should produce exactly \(Board.mineCount) mines")
        }
    }

    // MARK: - Story 4A: Reveal Logic with Cascade

    func testRevealCellWithMineReturnsMine() {
        var board = Board(seed: 12345)

        // Find a cell with a mine
        var mineRow = 0, mineCol = 0
        outer: for r in 0..<9 {
            for c in 0..<9 {
                if board.cells[r][c].hasMine {
                    mineRow = r
                    mineCol = c
                    break outer
                }
            }
        }

        let result = board.reveal(row: mineRow, col: mineCol)
        XCTAssertEqual(result, .mine)
    }

    func testRevealCellWithAdjacentMinesRevealsOneCell() {
        var board = Board(seed: 12345)

        // Find a cell next to a mine (has adjacent mines > 0) but isn't a mine
        var targetRow = -1, targetCol = -1
        outer: for r in 0..<9 {
            for c in 0..<9 {
                if !board.cells[r][c].hasMine {
                    let adjacent = board.adjacentMineCount(row: r, col: c)
                    if adjacent > 0 {
                        targetRow = r
                        targetCol = c
                        break outer
                    }
                }
            }
        }

        guard targetRow >= 0 else {
            XCTFail("Could not find a cell with adjacent mines")
            return
        }

        let result = board.reveal(row: targetRow, col: targetCol)

        if case .safe(let count) = result {
            XCTAssertEqual(count, 1, "Revealing cell with adjacent mines should reveal exactly 1 cell")
        } else {
            XCTFail("Expected .safe result")
        }

        if case .revealed(let adj) = board.cells[targetRow][targetCol].state {
            XCTAssertGreaterThan(adj, 0)
        } else {
            XCTFail("Cell should be revealed")
        }
    }

    func testRevealCellWithZeroAdjacentMinesCascades() {
        var board = Board(seed: 12345)

        // Find a cell with 0 adjacent mines
        var targetRow = -1, targetCol = -1
        outer: for r in 0..<9 {
            for c in 0..<9 {
                if !board.cells[r][c].hasMine {
                    let adjacent = board.adjacentMineCount(row: r, col: c)
                    if adjacent == 0 {
                        targetRow = r
                        targetCol = c
                        break outer
                    }
                }
            }
        }

        guard targetRow >= 0 else {
            XCTFail("Could not find a cell with zero adjacent mines")
            return
        }

        let result = board.reveal(row: targetRow, col: targetCol)

        if case .safe(let count) = result {
            XCTAssertGreaterThan(count, 1, "Revealing cell with 0 adjacent mines should cascade")
        } else {
            XCTFail("Expected .safe result")
        }
    }

    func testRevealAlreadyRevealedCellReturnsZero() {
        var board = Board(seed: 12345)

        // Find a non-mine cell
        var targetRow = 0, targetCol = 0
        outer: for r in 0..<9 {
            for c in 0..<9 {
                if !board.cells[r][c].hasMine {
                    targetRow = r
                    targetCol = c
                    break outer
                }
            }
        }

        _ = board.reveal(row: targetRow, col: targetCol)
        let secondResult = board.reveal(row: targetRow, col: targetCol)

        XCTAssertEqual(secondResult, .safe(cellsRevealed: 0))
    }

    func testRevealFlaggedCellReturnsZero() {
        var board = Board(seed: 12345)

        // Find a non-mine cell
        var targetRow = 0, targetCol = 0
        outer: for r in 0..<9 {
            for c in 0..<9 {
                if !board.cells[r][c].hasMine {
                    targetRow = r
                    targetCol = c
                    break outer
                }
            }
        }

        board.toggleFlag(row: targetRow, col: targetCol)
        let result = board.reveal(row: targetRow, col: targetCol)

        XCTAssertEqual(result, .safe(cellsRevealed: 0))
    }

    func testRevealOutOfBoundsReturnsZero() {
        var board = Board(seed: 12345)

        XCTAssertEqual(board.reveal(row: -1, col: 0), .safe(cellsRevealed: 0))
        XCTAssertEqual(board.reveal(row: 0, col: -1), .safe(cellsRevealed: 0))
        XCTAssertEqual(board.reveal(row: 9, col: 0), .safe(cellsRevealed: 0))
        XCTAssertEqual(board.reveal(row: 0, col: 9), .safe(cellsRevealed: 0))
    }

    func testAdjacentMineCountAtCorner() {
        let board = Board(seed: 12345)

        // Corner cells have at most 3 neighbors
        let count = board.adjacentMineCount(row: 0, col: 0)
        XCTAssertLessThanOrEqual(count, 3)
    }

    func testAdjacentMineCountAtEdge() {
        let board = Board(seed: 12345)

        // Edge cells have at most 5 neighbors
        let count = board.adjacentMineCount(row: 0, col: 4)
        XCTAssertLessThanOrEqual(count, 5)
    }

    func testAdjacentMineCountAtCenter() {
        let board = Board(seed: 12345)

        // Center cells have at most 8 neighbors
        let count = board.adjacentMineCount(row: 4, col: 4)
        XCTAssertLessThanOrEqual(count, 8)
    }

    func testCascadeDoesNotRevealMines() {
        var board = Board(seed: 12345)

        // Reveal all non-mine cells with cascade
        for r in 0..<9 {
            for c in 0..<9 {
                if !board.cells[r][c].hasMine {
                    _ = board.reveal(row: r, col: c)
                }
            }
        }

        // Verify no mine cells were revealed by cascade
        for r in 0..<9 {
            for c in 0..<9 {
                if board.cells[r][c].hasMine {
                    XCTAssertEqual(board.cells[r][c].state, .hidden, "Mine at (\(r),\(c)) should remain hidden")
                }
            }
        }
    }

    // MARK: - First-Click Opening Guarantee

    func testClearAreaForOpeningRemovesMinesFromClickedCell() {
        var board = Board(seed: 12345)

        // Find a cell with a mine in center area for testing
        var mineRow = -1, mineCol = -1
        outer: for r in 1..<8 {
            for c in 1..<8 {
                if board.cells[r][c].hasMine {
                    mineRow = r
                    mineCol = c
                    break outer
                }
            }
        }

        guard mineRow >= 0 else {
            XCTFail("No mine found in center area")
            return
        }

        board.clearAreaForOpening(centerRow: mineRow, centerCol: mineCol, seed: 12345)

        XCTAssertFalse(board.cells[mineRow][mineCol].hasMine,
                       "Clicked cell should have no mine after clearing")
    }

    func testClearAreaForOpeningRemovesMinesFromNeighbors() {
        var board = Board(seed: 12345)

        board.clearAreaForOpening(centerRow: 4, centerCol: 4, seed: 12345)

        // Check all 9 cells in 3x3 have no mines
        for dr in -1...1 {
            for dc in -1...1 {
                let r = 4 + dr
                let c = 4 + dc
                XCTAssertFalse(board.cells[r][c].hasMine,
                               "Cell at (\(r),\(c)) should have no mine")
            }
        }
    }

    func testClearAreaForOpeningPreservesTotalMineCount() {
        var board = Board(seed: 12345)

        let mineCountBefore = board.cells.flatMap { $0 }.filter(\.hasMine).count

        board.clearAreaForOpening(centerRow: 4, centerCol: 4, seed: 12345)

        let mineCountAfter = board.cells.flatMap { $0 }.filter(\.hasMine).count

        XCTAssertEqual(mineCountBefore, mineCountAfter,
                       "Total mine count should remain \(Board.mineCount)")
    }

    func testClearAreaForOpeningWorksAtCorner() {
        var board = Board(seed: 12345)

        board.clearAreaForOpening(centerRow: 0, centerCol: 0, seed: 12345)

        // Check 2x2 area at corner (only valid neighbors)
        XCTAssertFalse(board.cells[0][0].hasMine)
        XCTAssertFalse(board.cells[0][1].hasMine)
        XCTAssertFalse(board.cells[1][0].hasMine)
        XCTAssertFalse(board.cells[1][1].hasMine)

        // Verify mine count preserved
        let mineCount = board.cells.flatMap { $0 }.filter(\.hasMine).count
        XCTAssertEqual(mineCount, Board.mineCount)
    }

    func testClearAreaForOpeningWorksAtEdge() {
        var board = Board(seed: 12345)

        board.clearAreaForOpening(centerRow: 0, centerCol: 4, seed: 12345)

        // Check 2x3 area at top edge
        for c in 3...5 {
            XCTAssertFalse(board.cells[0][c].hasMine)
            XCTAssertFalse(board.cells[1][c].hasMine)
        }

        // Verify mine count preserved
        let mineCount = board.cells.flatMap { $0 }.filter(\.hasMine).count
        XCTAssertEqual(mineCount, Board.mineCount)
    }

    func testClearAreaForOpeningGuaranteesZeroAdjacentMines() {
        var board = Board(seed: 12345)

        board.clearAreaForOpening(centerRow: 4, centerCol: 4, seed: 12345)

        let adjacentMines = board.adjacentMineCount(row: 4, col: 4)
        XCTAssertEqual(adjacentMines, 0,
                       "Clicked cell should have 0 adjacent mines to trigger cascade")
    }

    func testClearAreaForOpeningRelocatesMinesOutsideClearZone() {
        var board = Board(seed: 12345)

        board.clearAreaForOpening(centerRow: 4, centerCol: 4, seed: 12345)

        // All mines should be outside the 3x3 zone
        var minesOutside = 0
        for r in 0..<Board.rows {
            for c in 0..<Board.cols {
                let inClearZone = (r >= 3 && r <= 5 && c >= 3 && c <= 5)
                if !inClearZone && board.cells[r][c].hasMine {
                    minesOutside += 1
                }
            }
        }

        XCTAssertEqual(minesOutside, Board.mineCount,
                       "All mines should be outside the clear zone")
    }

    func testClearAreaForOpeningIsDeterministic() {
        // Two boards with same seed, cleared at same position, should be identical
        var board1 = Board(seed: 12345)
        var board2 = Board(seed: 12345)

        board1.clearAreaForOpening(centerRow: 4, centerCol: 4, seed: 12345)
        board2.clearAreaForOpening(centerRow: 4, centerCol: 4, seed: 12345)

        XCTAssertEqual(board1.cells, board2.cells,
                       "Same seed + same click position should produce identical boards")
    }

    func testClearAreaForOpeningDifferentClickPositionsProduceDifferentBoards() {
        // Different click positions should produce different relocation
        var board1 = Board(seed: 12345)
        var board2 = Board(seed: 12345)

        board1.clearAreaForOpening(centerRow: 0, centerCol: 0, seed: 12345)
        board2.clearAreaForOpening(centerRow: 8, centerCol: 8, seed: 12345)

        // The boards should differ (different mines relocated to different places)
        XCTAssertNotEqual(board1.cells, board2.cells,
                          "Different click positions should produce different boards")
    }

    func testRevealingMineMarksOnlyThatCellExploded() {
        var board = Board(seed: 12345)

        guard let mine = findMineCell(in: board) else {
            XCTFail("No mine found")
            return
        }

        XCTAssertEqual(board.reveal(row: mine.row, col: mine.col), .mine)

        for r in 0..<Board.rows {
            for c in 0..<Board.cols {
                XCTAssertEqual(board.cells[r][c].isExploded, r == mine.row && c == mine.col)
            }
        }
    }

    // MARK: - Story 27: Chord Reveal

    func testAdjacentFlagCountWithNoFlags() {
        let board = Board(seed: 12345)

        // No flags placed, count should be 0
        let count = board.adjacentFlagCount(row: 4, col: 4)
        XCTAssertEqual(count, 0)
    }

    func testAdjacentFlagCountWithOneFlag() {
        var board = Board(seed: 12345)

        board.toggleFlag(row: 3, col: 3)
        let count = board.adjacentFlagCount(row: 4, col: 4)

        XCTAssertEqual(count, 1)
    }

    func testAdjacentFlagCountWithMultipleFlags() {
        var board = Board(seed: 12345)

        board.toggleFlag(row: 3, col: 3)
        board.toggleFlag(row: 3, col: 4)
        board.toggleFlag(row: 4, col: 3)
        let count = board.adjacentFlagCount(row: 4, col: 4)

        XCTAssertEqual(count, 3)
    }

    func testAdjacentFlagCountIgnoresNonAdjacentFlags() {
        var board = Board(seed: 12345)

        board.toggleFlag(row: 0, col: 0)
        let count = board.adjacentFlagCount(row: 4, col: 4)

        XCTAssertEqual(count, 0)
    }

    func testAdjacentFlagCountAtCorner() {
        var board = Board(seed: 12345)

        board.toggleFlag(row: 0, col: 1)
        board.toggleFlag(row: 1, col: 0)
        board.toggleFlag(row: 1, col: 1)
        let count = board.adjacentFlagCount(row: 0, col: 0)

        XCTAssertEqual(count, 3)
    }

    func testChordRevealOnHiddenCellReturnsZero() {
        var board = Board(seed: 12345)

        let result = board.chordReveal(row: 0, col: 0)
        XCTAssertEqual(result, .safe(cellsRevealed: 0))
    }

    func testChordRevealOnRevealedZeroCellReturnsZero() {
        var board = Board(seed: 12345)

        // Find a cell with 0 adjacent mines and reveal it
        var targetRow = -1, targetCol = -1
        outer: for r in 0..<9 {
            for c in 0..<9 {
                if !board.cells[r][c].hasMine && board.adjacentMineCount(row: r, col: c) == 0 {
                    targetRow = r
                    targetCol = c
                    break outer
                }
            }
        }

        guard targetRow >= 0 else {
            XCTFail("No zero-adjacent cell found")
            return
        }

        _ = board.reveal(row: targetRow, col: targetCol)

        let result = board.chordReveal(row: targetRow, col: targetCol)
        XCTAssertEqual(result, .safe(cellsRevealed: 0))
    }

    func testChordRevealWhenFlagsDoNotMatchReturnsZero() {
        var board = Board(seed: 12345)

        // Find a cell with adjacent mines > 0
        var targetRow = -1, targetCol = -1
        outer: for r in 0..<9 {
            for c in 0..<9 {
                if !board.cells[r][c].hasMine {
                    let adj = board.adjacentMineCount(row: r, col: c)
                    if adj > 0 {
                        targetRow = r
                        targetCol = c
                        break outer
                    }
                }
            }
        }

        guard targetRow >= 0 else {
            XCTFail("No cell with adjacent mines found")
            return
        }

        _ = board.reveal(row: targetRow, col: targetCol)
        // Don't place any flags - flags (0) won't match adjMines (>0)

        let result = board.chordReveal(row: targetRow, col: targetCol)
        XCTAssertEqual(result, .safe(cellsRevealed: 0), "Chord reveal should do nothing when flag count doesn't match")
    }

    func testChordRevealRevealsUnflaggedAdjacentCells() {
        var board = Board(seed: 12345)

        // Find a revealed cell with exactly 1 adjacent mine
        var targetRow = -1, targetCol = -1
        var mineRow = -1, mineCol = -1
        outer: for r in 0..<9 {
            for c in 0..<9 {
                if !board.cells[r][c].hasMine {
                    let adj = board.adjacentMineCount(row: r, col: c)
                    if adj == 1 {
                        // Find the adjacent mine
                        for dr in -1...1 {
                            for dc in -1...1 {
                                if dr == 0 && dc == 0 { continue }
                                let mr = r + dr
                                let mc = c + dc
                                if mr >= 0, mr < 9, mc >= 0, mc < 9 {
                                    if board.cells[mr][mc].hasMine {
                                        targetRow = r
                                        targetCol = c
                                        mineRow = mr
                                        mineCol = mc
                                        break outer
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        guard targetRow >= 0 else {
            XCTFail("No suitable cell found")
            return
        }

        _ = board.reveal(row: targetRow, col: targetCol)
        board.toggleFlag(row: mineRow, col: mineCol)

        let result = board.chordReveal(row: targetRow, col: targetCol)

        if case .safe(let count) = result {
            XCTAssertGreaterThan(count, 0, "Chord reveal should reveal at least one cell")
        } else {
            XCTFail("Expected safe result")
        }
    }

    func testChordRevealReturnsMineIfIncorrectFlag() {
        var board = Board(seed: 12345)

        // Find a revealed cell with exactly 1 adjacent mine
        var targetRow = -1, targetCol = -1
        var wrongFlagRow = -1, wrongFlagCol = -1
        outer: for r in 0..<9 {
            for c in 0..<9 {
                if !board.cells[r][c].hasMine {
                    let adj = board.adjacentMineCount(row: r, col: c)
                    if adj == 1 {
                        // Find a non-mine adjacent cell to place wrong flag
                        for dr in -1...1 {
                            for dc in -1...1 {
                                if dr == 0 && dc == 0 { continue }
                                let nr = r + dr
                                let nc = c + dc
                                if nr >= 0, nr < 9, nc >= 0, nc < 9 {
                                    if !board.cells[nr][nc].hasMine {
                                        targetRow = r
                                        targetCol = c
                                        wrongFlagRow = nr
                                        wrongFlagCol = nc
                                        break outer
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        guard targetRow >= 0, wrongFlagRow >= 0 else {
            XCTFail("No suitable cell found")
            return
        }

        _ = board.reveal(row: targetRow, col: targetCol)
        board.toggleFlag(row: wrongFlagRow, col: wrongFlagCol)

        let result = board.chordReveal(row: targetRow, col: targetCol)

        XCTAssertEqual(result, .mine, "Chord reveal should return .mine when flag is incorrectly placed")
    }

    func testChordRevealOutOfBoundsReturnsZero() {
        var board = Board(seed: 12345)

        XCTAssertEqual(board.chordReveal(row: -1, col: 0), .safe(cellsRevealed: 0))
        XCTAssertEqual(board.chordReveal(row: 0, col: -1), .safe(cellsRevealed: 0))
        XCTAssertEqual(board.chordReveal(row: 9, col: 0), .safe(cellsRevealed: 0))
        XCTAssertEqual(board.chordReveal(row: 0, col: 9), .safe(cellsRevealed: 0))
    }

    func testChordRevealCanTriggerCascade() {
        var board = Board(seed: 12345)

        // Find a revealed cell with 1 adjacent mine where an adjacent cell has 0 mines
        var targetRow = -1, targetCol = -1
        var mineRow = -1, mineCol = -1
        var hasZeroNeighbor = false

        outer: for r in 0..<9 {
            for c in 0..<9 {
                if !board.cells[r][c].hasMine {
                    let adj = board.adjacentMineCount(row: r, col: c)
                    if adj == 1 {
                        // Find the mine
                        for dr in -1...1 {
                            for dc in -1...1 {
                                if dr == 0 && dc == 0 { continue }
                                let mr = r + dr
                                let mc = c + dc
                                if mr >= 0, mr < 9, mc >= 0, mc < 9 {
                                    if board.cells[mr][mc].hasMine {
                                        mineRow = mr
                                        mineCol = mc
                                    }
                                }
                            }
                        }

                        // Check if any non-mine neighbor has 0 adjacent mines
                        for dr in -1...1 {
                            for dc in -1...1 {
                                if dr == 0 && dc == 0 { continue }
                                let nr = r + dr
                                let nc = c + dc
                                if nr >= 0, nr < 9, nc >= 0, nc < 9 {
                                    if !board.cells[nr][nc].hasMine {
                                        if board.adjacentMineCount(row: nr, col: nc) == 0 {
                                            hasZeroNeighbor = true
                                            targetRow = r
                                            targetCol = c
                                            break outer
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        guard targetRow >= 0, mineRow >= 0, hasZeroNeighbor else {
            // This test depends on board layout - skip if no suitable configuration
            return
        }

        _ = board.reveal(row: targetRow, col: targetCol)
        board.toggleFlag(row: mineRow, col: mineCol)

        let result = board.chordReveal(row: targetRow, col: targetCol)

        if case .safe(let count) = result {
            // If we have a zero-neighbor, cascade should reveal more than just immediate neighbors
            XCTAssertGreaterThan(count, 1, "Chord reveal with zero-adjacent neighbor should cascade")
        } else {
            XCTFail("Expected safe result")
        }
    }
}
