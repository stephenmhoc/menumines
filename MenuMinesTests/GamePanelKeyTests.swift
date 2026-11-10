import AppKit
import Testing
@testable import MenuMines

/// Keys on the board and in the panel's own overlays. Part of the game panel suite, so these
/// run in turn with the other tests that own the panel.
extension GamePanelTests {
    @Test("Return reveals like Space")
    func returnReveals() async throws {
        let cleanup = setupCleanPersistenceState(continuousPlay: true)
        defer { cleanup() }

        let state = todaysDaily()
        let controller = try await openPanel(for: state)
        defer { controller.close() }

        try selectSafeCell(in: state)
        let (row, col) = (state.selectedRow, state.selectedCol)
        try await press(Key.returnKey, in: controller)
        #expect(state.status == .playing)
        #expect(state.board.cells[row][col].state != .hidden)
    }

    @Test("A key after one that closed the panel is reported, not quietly sent to a reopened panel")
    func closedPanelIsReported() async throws {
        let cleanup = setupCleanPersistenceState(continuousPlay: true)
        defer { cleanup() }

        let controller = try await openPanel(for: todaysDaily())
        defer { controller.close() }
        try await press(Key.escape, in: controller)
        try #require(!controller.isOpen)

        await withKnownIssue {
            try await press(Key.right, in: controller)
        }
    }

    @Test("Return and Escape both keep the game when a reset asks first")
    func resetConfirmationDefaultsToCancel() async throws {
        let cleanup = setupCleanPersistenceState(continuousPlay: true)
        let confirmKey = Constants.SettingsKeys.confirmBeforeReset
        let initialConfirm = UserDefaults.standard.object(forKey: confirmKey)
        UserDefaults.standard.set(true, forKey: confirmKey)
        defer {
            cleanup()
            if let initialConfirm {
                UserDefaults.standard.set(initialConfirm, forKey: confirmKey)
            } else {
                UserDefaults.standard.removeObject(forKey: confirmKey)
            }
        }

        let seed = seedFromDate(Date().addingTimeInterval(-86_400))
        let state = GameState(board: Board(dailySeed: seed), dailySeed: seed, puzzleType: .practice)
        let controller = try await openPanel(for: state)
        defer { controller.close() }
        try selectSafeCell(in: state)
        try await press(Key.space, in: controller)
        #expect(state.status == .playing)

        for key in [Key.returnKey, Key.escape] {
            try await pressCommand(Key.commandR, in: controller)
            try await pressThroughApp(key, in: controller)

            #expect(state.status == .playing)
            #expect(controller.isOpen)

            // The board only takes keys again once the confirmation has gone.
            try selectSafeCell(in: state)
            let (row, col) = (state.selectedRow, state.selectedCol)
            try await press(Key.space, in: controller)
            #expect(state.board.cells[row][col].state != .hidden, "after key \(key.code)")
        }
    }

    @Test("The board takes the keyboard back every time a reset confirmation is dismissed")
    func boardKeepsKeyboardAcrossConfirmations() async throws {
        let cleanup = setupCleanPersistenceState(continuousPlay: true)
        let confirmKey = Constants.SettingsKeys.confirmBeforeReset
        let initialConfirm = UserDefaults.standard.object(forKey: confirmKey)
        UserDefaults.standard.set(true, forKey: confirmKey)
        defer {
            cleanup()
            if let initialConfirm {
                UserDefaults.standard.set(initialConfirm, forKey: confirmKey)
            } else {
                UserDefaults.standard.removeObject(forKey: confirmKey)
            }
        }

        // Losing the board's key view only happened some of the time, and more often with
        // the app active, as it is when the panel opens from one of the app's windows.
        NSApp.activate(ignoringOtherApps: true)
        try await settle()

        let seed = seedFromDate(Date().addingTimeInterval(-86_400))
        let state = GameState(board: Board(dailySeed: seed), dailySeed: seed, puzzleType: .practice)
        let controller = try await openPanel(for: state)
        defer { controller.close() }
        try selectSafeCell(in: state)
        try await press(Key.space, in: controller)
        try #require(state.status == .playing)

        for round in 0..<12 {
            let key = round.isMultiple(of: 2) ? Key.returnKey : Key.escape
            try await pressCommand(Key.commandR, in: controller)
            try await pressThroughApp(key, in: controller)
            try #require(state.status == .playing, "round \(round): the confirmation reset the game")

            guard let (row, col) = findHiddenSafeCell(in: state) else { break }
            state.select(row: row, col: col)
            try await press(Key.space, in: controller)
            try #require(
                state.board.cells[row][col].state != .hidden,
                "round \(round): Space after key \(key.code) didn't reach the board"
            )
            guard state.status == .playing else { break }
        }
    }

    private func findHiddenSafeCell(in state: GameState) -> (Int, Int)? {
        for row in 0..<Board.rows {
            for col in 0..<Board.cols {
                let cell = state.board.cells[row][col]
                if case .hidden = cell.state, !cell.hasMine {
                    return (row, col)
                }
            }
        }
        return nil
    }
}
