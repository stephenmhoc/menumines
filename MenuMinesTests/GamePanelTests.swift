import AppKit
import Testing
@testable import MenuMines

/// Runs against a real panel and real key events, because keyboard play depends on focus
/// landing on the board, which no amount of testing `GameState` can show.
@Suite("Game panel", .serialized)
@MainActor
struct GamePanelTests {
    enum Key {
        static let right: (code: UInt16, characters: String) = (124, "\u{F703}")
        static let down: (code: UInt16, characters: String) = (125, "\u{F701}")
        static let space: (code: UInt16, characters: String) = (49, " ")
        static let returnKey: (code: UInt16, characters: String) = (36, "\r")
        static let flag: (code: UInt16, characters: String) = (3, "f")
        static let escape: (code: UInt16, characters: String) = (53, "\u{1B}")
        static let commandW: (code: UInt16, characters: String) = (13, "w")
        static let commandR: (code: UInt16, characters: String) = (15, "r")
        static let commandComma: (code: UInt16, characters: String) = (43, ",")
    }

    /// Sends a key with Command held through the application, which is where key equivalents
    /// are dispatched from.
    func pressCommand(_ key: (code: UInt16, characters: String), in controller: StatusItemController) async throws {
        try await pressThroughApp(key, modifiers: .command, in: controller)
    }

    /// Sends a key through the application, as a real key press arrives, so key equivalents
    /// such as a default button's Return get their turn before the focused view.
    func pressThroughApp(
        _ key: (code: UInt16, characters: String),
        modifiers: NSEvent.ModifierFlags = [],
        in controller: StatusItemController
    ) async throws {
        try await takeKeyboard(for: controller)

        let event = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: controller.panel.windowNumber,
            context: nil,
            characters: key.characters,
            charactersIgnoringModifiers: key.characters,
            isARepeat: false,
            keyCode: key.code
        ))
        NSApp.sendEvent(event)
        try await settle()
    }

    func press(_ key: (code: UInt16, characters: String), in controller: StatusItemController) async throws {
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
    func takeKeyboard(for controller: StatusItemController) async throws {
        // A panel fading out is still key for a moment, but it's closed.
        for _ in 0..<20 where !(controller.panel.isKeyWindow && controller.isOpen) {
            controller.open()
            controller.panel.makeKey()
            try await settle()
        }
        try #require(controller.panel.isKeyWindow && controller.isOpen)
    }

    func settle() async throws {
        try await Task.sleep(for: .milliseconds(150))
    }

    func openPanel(for state: GameState) async throws -> StatusItemController {
        let controller = StatusItemController(gameState: state)
        controller.open()
        try await settle()
        return controller
    }

    func todaysDaily() -> GameState {
        let seed = seedFromDate(Date())
        return GameState(board: Board(dailySeed: seed), dailySeed: seed, puzzleType: .daily)
    }

    /// Moves the selection to a cell that's safe to reveal and doesn't finish the game.
    func selectSafeCell(in state: GameState) throws {
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

    /// A mouse-down with no window, as a click that went to another process is seen from here.
    func iconClick(at timestamp: TimeInterval, location: NSPoint = .zero) throws -> NSEvent {
        try #require(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: location,
            modifierFlags: [],
            timestamp: timestamp,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))
    }

    var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    @Test("A click on the icon closes the open panel")
    func iconClickCloses() async throws {
        let cleanup = setupCleanPersistenceState(continuousPlay: true)
        defer { cleanup() }

        let controller = try await openPanel(for: todaysDaily())
        defer { controller.close() }

        controller.handlePress(try iconClick(at: now))

        #expect(!controller.isOpen)
    }

    /// The icon lives in a window the system owns, so its click is also a click elsewhere,
    /// and that can close the panel before the press is delivered.
    @Test("A click on the icon leaves the panel closed when something else closed it first")
    func iconClickDoesNotReopen() async throws {
        let cleanup = setupCleanPersistenceState(continuousPlay: true)
        defer { cleanup() }

        let controller = try await openPanel(for: todaysDaily())
        defer { controller.close() }

        let click = try iconClick(at: now)
        controller.close()
        controller.handlePress(click)
        #expect(!controller.isOpen)

        try await settle()
        controller.handlePress(try iconClick(at: now))
        #expect(controller.isOpen)
    }

    @Test("A click on the icon opens the panel after it was closed some other way")
    func iconClickOpensAfterClose() async throws {
        let cleanup = setupCleanPersistenceState(continuousPlay: true)
        defer { cleanup() }

        let controller = try await openPanel(for: todaysDaily())
        defer { controller.close() }

        controller.close()
        try await settle()
        controller.handlePress(try iconClick(at: now))
        #expect(controller.isOpen)

        // Two clicks waiting together: the first closes, the second opens again.
        let first = try iconClick(at: now)
        let second = try iconClick(at: now)
        controller.handlePress(first)
        #expect(!controller.isOpen)
        controller.handlePress(second)
        #expect(controller.isOpen)
    }

    @Test("Only a click inside the icon's frame counts as one on the icon")
    func clicksAreMatchedToIcon() async throws {
        let cleanup = setupCleanPersistenceState(continuousPlay: true)
        defer { cleanup() }

        let controller = try await openPanel(for: todaysDaily())
        defer { controller.close() }

        #expect(!controller.isOnIcon(try iconClick(at: now, location: NSPoint(x: -10_000, y: -10_000))))

        // The menu bar animates a new item in, and its window has no height until it lands.
        for _ in 0..<20 where (controller.iconFrame?.height ?? 0) == 0 {
            try await settle()
        }
        let icon = try #require(controller.iconFrame)
        #expect(controller.isOnIcon(try iconClick(at: now, location: NSPoint(x: icon.midX, y: icon.midY))))
    }

    @Test("Every window opens at the size of its content")
    func windowsFitTheirContent() async throws {
        let cleanup = setupCleanPersistenceState(continuousPlay: true)
        defer { cleanup() }

        let opens: [() -> Void] = [
            AppWindows.showSettings,
            AboutWindow.show,
            { AppWindows.showStats(gameState: todaysDaily()) }
        ]

        for open in opens {
            open()
            try await settle()
            let window = try #require(NSApp.windows.first { $0.isVisible && $0.styleMask.contains(.titled) })
            #expect(window.contentLayoutRect.height >= 200, "\(window.title) is \(window.contentLayoutRect.height)pt tall")
            window.close()
            try await settle()
        }
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
