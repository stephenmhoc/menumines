import Foundation
import GameplayKit

/// Result of revealing a cell.
enum RevealResult: Equatable {
    case safe(cellsRevealed: Int)
    case mine
}

/// The 9x9 Minesweeper game board.
struct Board: Equatable, Codable {
    static let rows = 9
    static let cols = 9
    static let mineCount = 12

    private(set) var cells: [[Cell]]

    private enum CodingKeys: String, CodingKey {
        case cells
    }

    /// Creates a board with pre-existing cells (used for persistence restoration).
    /// - Parameter cells: The cell grid to use.
    init(cells: [[Cell]]) {
        precondition(cells.count == Board.rows, "Board must have \(Board.rows) rows")
        precondition(cells.allSatisfy { $0.count == Board.cols }, "Each row must have \(Board.cols) columns")
        self.cells = cells
    }

    /// Creates a new board with mines placed deterministically based on the seed.
    /// - Parameter seed: The seed for deterministic mine placement.
    init(seed: Int64) {
        self.init(seed: seed, keepingClear: [])
    }

    /// Creates the canonical board for a daily seed, already opened at its safe cell.
    ///
    /// Every player gets this exact board. That is only possible because the opening is
    /// baked in at generation time rather than cleared on the player's first click:
    /// relocating mines around wherever someone happened to click made the layout depend on
    /// that click, so two people playing "the same" daily were playing different boards and
    /// their shared grids never matched.
    /// - Parameter dailySeed: The daily seed, in `YYYYMMDD` form.
    init(dailySeed: Int64) {
        let opening = Board.openingCell(forSeed: dailySeed)
        self.init(seed: dailySeed, keepingClear: Board.positionsSurrounding(opening))
        _ = reveal(row: opening.row, col: opening.col)
    }

    /// The cell every player starts from on a given day.
    ///
    /// Kept off the edges so the opening cascade has room to reveal a useful area.
    static func openingCell(forSeed seed: Int64) -> (row: Int, col: Int) {
        let rng = GKLinearCongruentialRandomSource(seed: UInt64(bitPattern: seed &* 31))
        return (
            row: 1 + rng.nextInt(upperBound: Board.rows - 2),
            col: 1 + rng.nextInt(upperBound: Board.cols - 2)
        )
    }

    /// The opening cell and its neighbours, which must stay mine-free so the opening
    /// reveals a zero-adjacent cascade rather than a lone numbered cell.
    private static func positionsSurrounding(_ cell: (row: Int, col: Int)) -> Set<Int> {
        var positions = Set<Int>()
        for dr in -1...1 {
            for dc in -1...1 {
                let r = cell.row + dr
                let c = cell.col + dc
                if r >= 0, r < Board.rows, c >= 0, c < Board.cols {
                    positions.insert(r * Board.cols + c)
                }
            }
        }
        return positions
    }

    private init(seed: Int64, keepingClear clearPositions: Set<Int>) {
        cells = (0..<Board.rows).map { _ in
            (0..<Board.cols).map { _ in
                Cell(state: .hidden, hasMine: false)
            }
        }

        let rng = GKLinearCongruentialRandomSource(seed: UInt64(bitPattern: seed))

        var minePositions = Set<Int>()
        let totalCells = Board.rows * Board.cols
        let placeable = totalCells - clearPositions.count
        precondition(Board.mineCount <= placeable, "Cannot place \(Board.mineCount) mines in \(placeable) cells")

        while minePositions.count < Board.mineCount {
            let position = rng.nextInt(upperBound: totalCells)
            guard !clearPositions.contains(position) else { continue }
            minePositions.insert(position)
        }

        for position in minePositions {
            let row = position / Board.cols
            let col = position % Board.cols
            cells[row][col] = Cell(state: .hidden, hasMine: true)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedCells = try container.decode([[Cell]].self, forKey: .cells)

        guard decodedCells.count == Board.rows else {
            throw DecodingError.dataCorruptedError(
                forKey: .cells,
                in: container,
                debugDescription: "Expected \(Board.rows) rows, got \(decodedCells.count)"
            )
        }
        guard decodedCells.allSatisfy({ $0.count == Board.cols }) else {
            throw DecodingError.dataCorruptedError(
                forKey: .cells,
                in: container,
                debugDescription: "Expected \(Board.cols) columns in each row"
            )
        }

        self.cells = decodedCells
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(cells, forKey: .cells)
    }

    /// Reveals the cell at the given position with flood-fill cascade for zero-adjacent cells.
    /// - Returns: `.mine` if the cell contains a mine, `.safe(cellsRevealed:)` otherwise.
    mutating func reveal(row: Int, col: Int) -> RevealResult {
        guard row >= 0, row < Board.rows, col >= 0, col < Board.cols else {
            return .safe(cellsRevealed: 0)
        }
        guard case .hidden = cells[row][col].state else {
            return .safe(cellsRevealed: 0)
        }

        if cells[row][col].hasMine {
            cells[row][col].state = .revealed(adjacentMines: 0)
            cells[row][col].isExploded = true
            return .mine
        }

        // Flood-fill reveal using a stack
        var stack = [(row, col)]
        var cellsRevealed = 0

        while let (r, c) = stack.popLast() {
            // Skip if out of bounds
            guard r >= 0, r < Board.rows, c >= 0, c < Board.cols else { continue }
            // Skip if not hidden (already revealed or flagged)
            guard case .hidden = cells[r][c].state else { continue }
            // Skip mines
            guard !cells[r][c].hasMine else { continue }

            let adjacent = adjacentMineCount(row: r, col: c)
            cells[r][c].state = .revealed(adjacentMines: adjacent)
            cellsRevealed += 1

            // If zero adjacent mines, add all 8 neighbors to the stack
            if adjacent == 0 {
                for dr in -1...1 {
                    for dc in -1...1 {
                        if dr == 0 && dc == 0 { continue }
                        stack.append((r + dr, c + dc))
                    }
                }
            }
        }

        return .safe(cellsRevealed: cellsRevealed)
    }

    /// Toggles the flag state of a hidden cell.
    mutating func toggleFlag(row: Int, col: Int) {
        guard row >= 0, row < Board.rows, col >= 0, col < Board.cols else { return }

        switch cells[row][col].state {
        case .hidden:
            cells[row][col].state = .flagged
        case .flagged:
            cells[row][col].state = .hidden
        case .revealed:
            break
        }
    }

    /// Marks the cell as the one that exploded (the clicked mine).
    mutating func markExploded(row: Int, col: Int) {
        guard row >= 0, row < Board.rows, col >= 0, col < Board.cols else { return }
        cells[row][col].isExploded = true
    }

    /// Reveals all mines on the board (used when game is lost).
    /// Preserves flagged mines so correct flags remain visible.
    /// Does not mark them as exploded - only the clicked mine gets that flag.
    mutating func revealAllMines() {
        for r in 0..<Board.rows {
            for c in 0..<Board.cols {
                if cells[r][c].hasMine && !cells[r][c].isExploded {
                    if case .flagged = cells[r][c].state { continue }
                    cells[r][c].state = .revealed(adjacentMines: 0)
                }
            }
        }
    }

    /// Counts the number of flagged cells on the board.
    var flagCount: Int {
        cells.flatMap { $0 }.filter {
            if case .flagged = $0.state { return true }
            return false
        }.count
    }

    /// Opens every safe cell (used to show a win that wasn't played on this board).
    mutating func revealAllSafeCells() {
        for r in 0..<Board.rows {
            for c in 0..<Board.cols where !cells[r][c].hasMine {
                cells[r][c].state = .revealed(adjacentMines: adjacentMineCount(row: r, col: c))
            }
        }
    }

    /// Flags all unflagged mine cells (used when game is won).
    mutating func flagAllMines() {
        for r in 0..<Board.rows {
            for c in 0..<Board.cols {
                if cells[r][c].hasMine {
                    if case .hidden = cells[r][c].state {
                        cells[r][c].state = .flagged
                    }
                }
            }
        }
    }

    /// Relocates a mine from the given position to a random empty cell.
    /// Used for first-click safety.
    mutating func relocateMine(from row: Int, col: Int) {
        guard row >= 0, row < Board.rows, col >= 0, col < Board.cols else { return }
        guard cells[row][col].hasMine else { return }

        // Find empty cells
        var emptyCells: [(Int, Int)] = []
        for r in 0..<Board.rows {
            for c in 0..<Board.cols {
                if !cells[r][c].hasMine && (r != row || c != col) {
                    emptyCells.append((r, c))
                }
            }
        }

        guard let target = emptyCells.randomElement() else { return }

        // Move the mine
        cells[row][col] = Cell(state: .hidden, hasMine: false)
        cells[target.0][target.1] = Cell(state: .hidden, hasMine: true)
    }

    /// Clears mines from a 3x3 area around the given position.
    /// Mines are relocated deterministically to empty cells outside this area.
    /// Used for first-click opening guarantee.
    /// - Parameters:
    ///   - row: Center row of the area to clear
    ///   - col: Center column of the area to clear
    ///   - seed: Board seed for deterministic relocation
    mutating func clearAreaForOpening(centerRow row: Int, centerCol col: Int, seed: Int64) {
        // Create deterministic RNG from board seed + click position
        let relocationSeed = UInt64(bitPattern: seed ^ Int64(row * 31 + col) ^ 0x4d4d_4f52)
        let rng = GKLinearCongruentialRandomSource(seed: relocationSeed)

        // Collect positions in 3x3 area (sorted for determinism)
        var clearPositions: [(Int, Int)] = []
        for dr in -1...1 {
            for dc in -1...1 {
                let r = row + dr
                let c = col + dc
                if r >= 0, r < Board.rows, c >= 0, c < Board.cols {
                    clearPositions.append((r, c))
                }
            }
        }

        // Find empty cells outside clear zone (sorted for determinism)
        var targetCells: [(Int, Int)] = []
        for r in 0..<Board.rows {
            for c in 0..<Board.cols {
                let inClearZone = clearPositions.contains { $0.0 == r && $0.1 == c }
                if !inClearZone && !cells[r][c].hasMine {
                    targetCells.append((r, c))
                }
            }
        }

        // Fisher-Yates shuffle with seeded RNG for deterministic ordering
        for i in stride(from: targetCells.count - 1, through: 1, by: -1) {
            let j = rng.nextInt(upperBound: i + 1)
            targetCells.swapAt(i, j)
        }

        // Relocate each mine in clear zone (in sorted order for determinism)
        var targetIndex = 0
        for (r, c) in clearPositions {
            if cells[r][c].hasMine {
                guard targetIndex < targetCells.count else { continue }
                let target = targetCells[targetIndex]
                cells[r][c] = Cell(state: .hidden, hasMine: false)
                cells[target.0][target.1] = Cell(state: .hidden, hasMine: true)
                targetIndex += 1
            }
        }
    }

    /// Returns the count of mines in adjacent cells (including diagonals).
    func adjacentMineCount(row: Int, col: Int) -> Int {
        countAdjacentCells(row: row, col: col) { $0.hasMine }
    }

    /// Returns the count of flagged cells adjacent to the given position.
    func adjacentFlagCount(row: Int, col: Int) -> Int {
        countAdjacentCells(row: row, col: col) { cell in
            if case .flagged = cell.state { return true }
            return false
        }
    }

    private func countAdjacentCells(row: Int, col: Int, matching predicate: (Cell) -> Bool) -> Int {
        var count = 0
        for dr in -1...1 {
            for dc in -1...1 {
                if dr == 0 && dc == 0 { continue }
                let r = row + dr
                let c = col + dc
                if r >= 0, r < Board.rows, c >= 0, c < Board.cols {
                    if predicate(cells[r][c]) {
                        count += 1
                    }
                }
            }
        }
        return count
    }

    /// Performs a chord reveal on a revealed number cell.
    /// If the adjacent flag count matches the cell's number, reveals all unflagged adjacent cells.
    /// - Returns: `.mine` if any revealed cell contains a mine, `.safe(cellsRevealed:)` otherwise.
    mutating func chordReveal(row: Int, col: Int) -> RevealResult {
        guard row >= 0, row < Board.rows, col >= 0, col < Board.cols else {
            return .safe(cellsRevealed: 0)
        }

        guard case .revealed(let adjacentMines) = cells[row][col].state, adjacentMines > 0 else {
            return .safe(cellsRevealed: 0)
        }

        let flagCount = adjacentFlagCount(row: row, col: col)
        guard flagCount == adjacentMines else {
            return .safe(cellsRevealed: 0)
        }

        var totalRevealed = 0
        for dr in -1...1 {
            for dc in -1...1 {
                if dr == 0 && dc == 0 { continue }
                let r = row + dr
                let c = col + dc
                guard r >= 0, r < Board.rows, c >= 0, c < Board.cols else { continue }
                guard case .hidden = cells[r][c].state else { continue }

                switch reveal(row: r, col: c) {
                case .mine:
                    return .mine
                case .safe(let count):
                    totalRevealed += count
                }
            }
        }

        return .safe(cellsRevealed: totalRevealed)
    }
}
