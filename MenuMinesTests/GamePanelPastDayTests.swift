import AppKit
import Testing
@testable import MenuMines

/// Getting to a past day: from Daily History, and from the offer under a finished board.
/// Part of the game panel suite, so these run in turn with the other tests that own the panel.
extension GamePanelTests {
    private var statsWindow: NSWindow? {
        NSApp.windows.first { $0.isVisible && $0.title == String(localized: "stats_window_title") }
    }

    /// No results and no past dailies in progress, so yesterday is a day to be played.
    private func setupUnplayedHistory() -> () -> Void {
        let cleanup = setupCleanPersistenceState(continuousPlay: true)
        let clearProgress = {
            for seed in GameSnapshot.pastDailySeedsInProgress() {
                GameSnapshot.clearPastDaily(seed: seed)
            }
        }
        clearProgress()
        StatsStore.shared.reset()

        return {
            cleanup()
            clearProgress()
            StatsStore.shared.reset()
            UserDefaults.standard.removeObject(forKey: "statsResetAt")
        }
    }

    @Test("Daily History opens Stats on the calendar, even when Stats is already open")
    func dailyHistoryTurnsToCalendar() async throws {
        let cleanup = setupUnplayedHistory()
        defer { cleanup() }

        let state = todaysDaily()
        AppWindows.showStats(gameState: state)
        try await settle()
        #expect(AppWindows.statsNavigation.tab == .summary)

        AppWindows.showDailyHistory(gameState: state)
        try await settle()
        #expect(AppWindows.statsNavigation.tab == .history)
        #expect(NSApp.windows.filter { $0.isVisible && $0.title == String(localized: "stats_window_title") }.count == 1)

        // Asking for Stats again doesn't take the player off the calendar they're looking at.
        AppWindows.showStats(gameState: state)
        #expect(AppWindows.statsNavigation.tab == .history)

        try #require(statsWindow).close()
        try await settle()
        AppWindows.showStats(gameState: state)
        try await settle()
        #expect(AppWindows.statsNavigation.tab == .summary, "A new Stats window starts on the summary")
        try #require(statsWindow).close()
    }

    @Test("The calendar is there to pick from before any game has been finished")
    func calendarShowsWithNoResults() async throws {
        let cleanup = setupUnplayedHistory()
        defer { cleanup() }
        try #require(!StatsStore.shared.hasResults)

        AppWindows.showStats(gameState: todaysDaily())
        try await settle()
        let emptyHeight = try #require(statsWindow).contentLayoutRect.height
        try #require(statsWindow).close()
        try await settle()

        AppWindows.showDailyHistory(gameState: todaysDaily())
        try await settle()
        let window = try #require(statsWindow)
        #expect(window.contentLayoutRect.height > emptyHeight + 60, "A month of days, not the empty message")
        window.close()
    }

    @Test("Picking a past day closes Stats and opens the panel on that board, with the keys going to it")
    func pickingPastDayOpensPanel() async throws {
        let cleanup = setupUnplayedHistory()
        defer { cleanup() }

        let state = todaysDaily()
        let controller = StatusItemController(gameState: state)
        defer { controller.close() }
        let yesterday = yesterdaySeed()

        AppWindows.showDailyHistory(gameState: state)
        try await settle()
        try #require(statsWindow != nil)
        #expect(!controller.isOpen)

        AppWindows.playPastDay(seed: yesterday, gameState: state)
        try await settle()

        #expect(statsWindow == nil, "Stats gets out of the way")
        #expect(controller.isOpen)
        #expect(state.puzzleType == .pastDaily)
        #expect(state.dailySeed == yesterday)
        // Stats being closed mustn't hide the app, which would take the panel with it.
        try await settle()
        #expect(controller.isOpen)
        if NSApp.isActive {
            #expect(controller.panel.isKeyWindow, "The keyboard goes from Stats straight to the board")
        }

        let start = (row: state.selectedRow, col: state.selectedCol)
        try await press(Key.right, in: controller)
        try await press(Key.down, in: controller)
        #expect(state.selectedCol == start.col + 1)
        #expect(state.selectedRow == start.row + 1)

        try selectSafeCell(in: state)
        try await press(Key.space, in: controller)
        #expect(state.status == .playing)
        #expect(state.puzzleType == .pastDaily)
        #expect(!state.isPaused, "The clock runs while the panel is up")
    }

    @Test("A day that can't be played leaves Stats where it is")
    func pickingUnavailableDayDoesNothing() async throws {
        let cleanup = setupUnplayedHistory()
        defer { cleanup() }

        let state = todaysDaily()
        let controller = StatusItemController(gameState: state)
        defer { controller.close() }

        AppWindows.showDailyHistory(gameState: state)
        try await settle()
        AppWindows.playPastDay(seed: 2026_01_30, gameState: state)
        AppWindows.playPastDay(seed: seedFromDate(Date()), gameState: state)
        try await settle()

        #expect(!controller.isOpen)
        #expect(state.puzzleType == .daily)
        try #require(statsWindow).close()
    }

    @Test("The panel can be opened again after one opened from Stats is closed")
    func panelReopensAfterPickingPastDay() async throws {
        let cleanup = setupUnplayedHistory()
        defer { cleanup() }

        let state = todaysDaily()
        let controller = StatusItemController(gameState: state)
        defer { controller.close() }

        AppWindows.showDailyHistory(gameState: state)
        try await settle()
        AppWindows.playPastDay(seed: yesterdaySeed(), gameState: state)
        try await settle()
        try selectSafeCell(in: state)
        try await press(Key.space, in: controller)
        try #require(state.status == .playing)

        try await press(Key.escape, in: controller)
        #expect(!controller.isOpen)
        #expect(state.isPaused)
        #expect(state.pastDailySeedsInProgress == [yesterdaySeed()], "Closing the panel saves the game")
        try await settle()

        try await takeKeyboard(for: controller)
        #expect(controller.isOpen)
        #expect(state.puzzleType == .pastDaily, "The past daily is still on the board")
        #expect(!state.isPaused)
    }

    @Test("Finishing today's puzzle offers a missed day under the board, and the panel grows to fit it")
    func missedDayOfferAppears() async throws {
        let cleanup = setupUnplayedHistory()
        defer { cleanup() }

        let state = todaysDaily()
        let controller = try await openPanel(for: state)
        defer { controller.close() }
        let before = controller.panel.frame
        try #require(before.height > 300)

        winGame(state)
        try #require(state.status == .won)
        try await settle()
        try await settle()

        let after = controller.panel.frame
        #expect(state.nextMissedDaySeed == yesterdaySeed())
        #expect(after.height == before.height + 34, "One more row, and the space above it")
        #expect(after.maxY == before.maxY, "It grows downwards, staying under the icon")
        #expect(after.minX == before.minX)
        #expect(controller.panel.contentView?.fittingSize.height == after.height)
    }

    @Test("The offer isn't made while today's puzzle is still to play, or when no day is missed")
    func missedDayOfferIsWithheld() async throws {
        let cleanup = setupUnplayedHistory()
        defer { cleanup() }

        // Today's puzzle not finished: nothing is offered, even over a finished past day.
        let unfinished = todaysDaily()
        unfinished.playPastDay(seed: yesterdaySeed())
        let mine = try #require(findMineCell(in: unfinished.board))
        unfinished.reveal(row: mine.row, col: mine.col)
        try #require(unfinished.status == .lost)
        let first = try await openPanel(for: unfinished)
        let plainHeight = first.panel.frame.height
        first.close()
        try await settle()

        let fresh = try await openPanel(for: todaysDaily())
        #expect(fresh.panel.frame.height == plainHeight, "A finished past day adds no row while today waits")
        fresh.close()
        try await settle()

        // Today finished: the row is there from the moment the panel opens.
        let finished = todaysDaily()
        winGame(finished)
        try #require(finished.status == .won)
        try await settle()
        let offered = try await openPanel(for: finished)
        #expect(offered.panel.frame.height == plainHeight + 34)
        offered.close()
    }

    @Test("Taking the offer puts the missed day on the board, and the panel shrinks back")
    func takingMissedDayOffer() async throws {
        let cleanup = setupUnplayedHistory()
        defer { cleanup() }

        let state = todaysDaily()
        winGame(state)
        try #require(state.status == .won)
        try await settle()
        let controller = try await openPanel(for: state)
        defer { controller.close() }
        let offered = controller.panel.frame

        // What the button and the gear menu item do.
        let missed = try #require(state.nextMissedDaySeed)
        #expect(state.playPastDay(seed: missed))
        state.resumeTimer()
        try await settle()
        try await settle()

        #expect(state.puzzleType == .pastDaily)
        #expect(controller.panel.frame.height == offered.height - 34)
        #expect(controller.panel.frame.maxY == offered.maxY)

        let start = state.selectedCol
        try await press(Key.right, in: controller)
        #expect(state.selectedCol == start + 1, "The board has the keyboard for the new game")
    }
}
