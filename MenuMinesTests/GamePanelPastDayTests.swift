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

    @Test("Resuming a past daily from Stats while the panel is already up keeps its clock running")
    func resumingPastDailyWithPanelOpenRunsClock() async throws {
        let cleanup = setupUnplayedHistory()
        defer { cleanup() }

        let state = todaysDaily()
        let controller = try await openPanel(for: state)
        defer { controller.close() }
        let yesterday = yesterdaySeed()

        // Start yesterday's past daily, then go back to today, all in the open panel.
        #expect(state.playPastDay(seed: yesterday))
        state.resumeTimer()
        try selectSafeCell(in: state)
        state.revealSelected()
        try #require(state.status == .playing)
        state.returnToToday()
        state.resumeTimer()
        try #require(controller.isOpen)

        // A calendar tile activated from the keyboard or VoiceOver: the panel never closes, so
        // it never appears again either.
        AppWindows.playPastDay(seed: yesterday, gameState: state)
        try await settle()
        #expect(controller.isOpen)
        #expect(state.puzzleType == .pastDaily)
        #expect(state.status == .playing)
        #expect(!state.isPaused, "The clock runs while the panel is up")

        let before = state.elapsedTime
        try await Task.sleep(for: .milliseconds(1_300))
        try selectSafeCell(in: state)
        state.revealSelected()
        state.pauseTimer()
        #expect(state.elapsedTime >= before + 1.2, "Time spent on the resumed game counts")
    }

    @Test("Picking a past daily with the panel closed leaves the clock to the panel")
    func pickingPastDailyWithPanelClosedOpensBeforeTiming() async throws {
        let cleanup = setupUnplayedHistory()
        defer { cleanup() }

        let state = todaysDaily()
        state.playPastDay(seed: yesterdaySeed())
        try selectSafeCell(in: state)
        state.revealSelected()
        state.pauseTimer()
        state.returnToToday()

        // No controller to show the panel, so nothing is on screen.
        AppWindows.onShowGame = nil
        AppWindows.isGameShowing = { false }
        AppWindows.playPastDay(seed: yesterdaySeed(), gameState: state)

        #expect(state.puzzleType == .pastDaily)
        #expect(state.isPaused, "Nothing times a game that isn't on screen")
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

        controller.open()
        try await takeKeyboard(for: controller)
        #expect(controller.isOpen)
        #expect(state.puzzleType == .pastDaily, "The past daily is still on the board")
        #expect(!state.isPaused)
    }
}
