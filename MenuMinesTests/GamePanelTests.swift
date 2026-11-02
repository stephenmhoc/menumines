import AppKit
import Testing
@testable import MenuMines

/// Runs against a real panel and real key events, because keyboard play depends on focus
/// landing on the board, which no amount of testing `GameState` can show.
@Suite("Game panel", .serialized)
@MainActor
struct GamePanelTests {
    private enum Key {
        static let right: (code: UInt16, characters: String) = (124, "\u{F703}")
        static let down: (code: UInt16, characters: String) = (125, "\u{F701}")
        static let space: (code: UInt16, characters: String) = (49, " ")
        static let flag: (code: UInt16, characters: String) = (3, "f")
        static let escape: (code: UInt16, characters: String) = (53, "\u{1B}")
    }

    private func press(_ key: (code: UInt16, characters: String), in controller: StatusItemController) async throws {
        try await takeKeyboard(for: controller)

        let event = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: controller.panel.windowNumber,
            context: nil,
            characters: key.characters,
            charactersIgnoringModifiers: key.characters,
            isARepeat: false,
            keyCode: key.code
        ))
        controller.panel.sendEvent(event)
        try await settle()
    }

    /// Another process can take activation from a test run at any moment, more so with the
    /// screen locked. That closes the panel, as it should, but says nothing about the keys.
    private func takeKeyboard(for controller: StatusItemController) async throws {
        for _ in 0..<20 where !controller.panel.isKeyWindow {
            controller.open()
            controller.panel.makeKey()
            try await settle()
        }
        try #require(controller.panel.isKeyWindow)
    }

    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(150))
    }

    private func openPanel(for state: GameState) async throws -> StatusItemController {
        let controller = StatusItemController(gameState: state)
        controller.open()
        try await settle()
        return controller
    }

    private func todaysDaily() -> GameState {
        let seed = seedFromDate(Date())
        return GameState(board: Board(dailySeed: seed), dailySeed: seed, puzzleType: .daily)
    }

    /// Moves the selection to a cell that's safe to reveal and doesn't finish the game.
    private func selectSafeCell(in state: GameState) throws {
        for row in 0..<Board.rows {
            for col in 0..<Board.cols {
                let cell = state.board.cells[row][col]
                if case .hidden = cell.state, !cell.hasMine {
                    state.select(row: row, col: col)
                    return
                }
            }
        }
        Issue.record("The board has no hidden safe cell")
    }

    @Test("Opening takes the keyboard")
    func opensAsKey() async throws {
        let cleanup = setupCleanPersistenceState(continuousPlay: true)
        defer { cleanup() }

        let controller = try await openPanel(for: todaysDaily())
        defer { controller.close() }

        try await takeKeyboard(for: controller)

        #expect(controller.isOpen)
        #expect(controller.panel.styleMask.contains(.nonactivatingPanel))
    }

    @Test("Arrow keys, Space and F reach the board")
    func keysReachBoard() async throws {
        let cleanup = setupCleanPersistenceState(continuousPlay: true)
        defer { cleanup() }

        let state = todaysDaily()
        let controller = try await openPanel(for: state)
        defer { controller.close() }

        let start = (row: state.selectedRow, col: state.selectedCol)
        try await press(Key.right, in: controller)
        try await press(Key.down, in: controller)
        #expect(state.selectedCol == start.col + 1)
        #expect(state.selectedRow == start.row + 1)

        try selectSafeCell(in: state)
        try await press(Key.space, in: controller)
        #expect(state.status == .playing)

        try selectSafeCell(in: state)
        try await press(Key.flag, in: controller)
        #expect(state.flagCount == 1)
    }

    @Test("Escape closes the panel, and closing pauses the game clock")
    func escapeCloses() async throws {
        let cleanup = setupCleanPersistenceState(continuousPlay: true)
        defer { cleanup() }

        let state = todaysDaily()
        let controller = try await openPanel(for: state)
        try selectSafeCell(in: state)
        try await press(Key.space, in: controller)
        #expect(state.status == .playing)
        #expect(!state.isPaused)

        try await press(Key.escape, in: controller)

        #expect(!controller.isOpen)
        #expect(state.isPaused)
    }

    @Test("Reopening resumes the clock")
    func reopeningResumes() async throws {
        let cleanup = setupCleanPersistenceState(continuousPlay: true)
        defer { cleanup() }

        let state = todaysDaily()
        let controller = try await openPanel(for: state)
        defer { controller.close() }
        try selectSafeCell(in: state)
        try await press(Key.space, in: controller)
        controller.close()
        try await settle()

        try await takeKeyboard(for: controller)

        #expect(!state.isPaused)
    }

    @Test("Opening a window moves the panel out of the way and brings the window forward")
    func windowsComeForward() async throws {
        let cleanup = setupCleanPersistenceState(continuousPlay: true)
        defer { cleanup() }

        let controller = try await openPanel(for: todaysDaily())

        AppWindows.showSettings()
        try await settle()

        #expect(!controller.isOpen)
        let window = try #require(NSApp.windows.first { $0.isVisible && $0.styleMask.contains(.titled) })
        if NSApp.isActive {
            #expect(window.isKeyWindow)
        }
        window.close()
    }
}
