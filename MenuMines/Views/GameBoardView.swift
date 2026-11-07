import SwiftUI

struct GameBoardView: View {
    let board: Board
    let gameStatus: GameStatus
    let selectedRow: Int
    let selectedCol: Int
    var showsSelection: Bool = true
    /// The cell marked as a safe place to start, if any.
    var startHint: (row: Int, col: Int)?
    let isFlagMode: Bool
    let onReveal: (Int, Int) -> Void
    let onFlag: (Int, Int) -> Void
    var onHover: (Int, Int, Bool) -> Void = { _, _, _ in }
    var onHoldChanged: (Bool) -> Void = { _ in }
    var onAccessibilityFocus: (Int, Int) -> Void = { _, _ in }

    var body: some View {
        VStack(spacing: 1) {
            ForEach(0..<Board.rows, id: \.self) { row in
                HStack(spacing: 1) {
                    ForEach(0..<Board.cols, id: \.self) { col in
                        CellView(
                            cell: board.cells[row][col],
                            row: row,
                            col: col,
                            gameStatus: gameStatus,
                            isSelected: showsSelection && row == selectedRow && col == selectedCol,
                            isChordReady: isChordReady(row: row, col: col),
                            isStartHint: startHint?.row == row && startHint?.col == col,
                            isFlagMode: isFlagMode,
                            onReveal: {
                                if shouldApplyFlagMode(row: row, col: col) {
                                    onFlag(row, col)
                                } else {
                                    onReveal(row, col)
                                }
                            },
                            onFlag: { onFlag(row, col) },
                            onHover: { onHover(row, col, $0) },
                            onHoldChanged: onHoldChanged,
                            onAccessibilityFocus: { onAccessibilityFocus(row, col) }
                        )
                    }
                }
            }
        }
        .background(Color(nsColor: .separatorColor))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "board_accessibility_label"))
    }

    private func isChordReady(row: Int, col: Int) -> Bool {
        guard gameStatus == .playing else { return false }
        guard case .revealed(let adjacentMines) = board.cells[row][col].state, adjacentMines > 0 else {
            return false
        }
        return board.adjacentFlagCount(row: row, col: col) == adjacentMines
    }

    private func shouldApplyFlagMode(row: Int, col: Int) -> Bool {
        guard isFlagMode, gameStatus == .notStarted || gameStatus == .playing else { return false }

        switch board.cells[row][col].state {
        case .hidden, .flagged:
            return true
        case .revealed:
            return false
        }
    }
}

// MARK: - Preview Helpers

extension Board {
    static func mockForPreview() -> Board {
        var board = Board(seed: 12345)
        // Reveal a few cells to show different states
        _ = board.reveal(row: 0, col: 0)
        _ = board.reveal(row: 1, col: 1)
        _ = board.reveal(row: 2, col: 2)
        board.toggleFlag(row: 3, col: 3)
        return board
    }

    static func mockWithMines() -> Board {
        let board = Board(seed: 12345)
        // Manually set some mines for preview
        // Note: This is a test helper, real mine placement comes from Story 3A
        return board
    }
}

// MARK: - Previews

#Preview("Game Board") {
    GameBoardView(
        board: Board.mockForPreview(),
        gameStatus: .playing,
        selectedRow: 4,
        selectedCol: 4,
        isFlagMode: false,
        onReveal: { _, _ in },
        onFlag: { _, _ in }
    )
    .padding()
}

#Preview("Game Board - Not Started") {
    GameBoardView(
        board: Board(dailySeed: 20240315),
        gameStatus: .notStarted,
        selectedRow: 0,
        selectedCol: 0,
        startHint: Board.openingCell(forSeed: 20240315),
        isFlagMode: false,
        onReveal: { _, _ in },
        onFlag: { _, _ in }
    )
    .padding()
}
