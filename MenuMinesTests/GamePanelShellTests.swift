import AppKit
import Testing
@testable import MenuMines

/// The menu bar shell around the board: key equivalents, the icon, opening and closing the
/// panel, and the app's windows. Part of the game panel suite, so these run in turn with the
/// other tests that own the panel.
extension GamePanelTests {
    @Test("Command-W closes the panel like Escape")
    func commandWCloses() async throws {
        let cleanup = setupCleanPersistenceState(continuousPlay: true)
        defer { cleanup() }

        let state = todaysDaily()
        let controller = try await openPanel(for: state)
        defer { controller.close() }
        try selectSafeCell(in: state)
        try await press(Key.space, in: controller)

        try await pressCommand(Key.commandW, in: controller)

        #expect(!controller.isOpen)
        #expect(state.isPaused)
    }

    @Test("Command-R resets a game that can be reset")
    func commandRResets() async throws {
        let cleanup = setupCleanPersistenceState(continuousPlay: true)
        defer { cleanup() }

        // A replay of an earlier day, which can always be reset.
        let seed = seedFromDate(Date().addingTimeInterval(-86_400))
        let state = GameState(board: Board(dailySeed: seed), dailySeed: seed, puzzleType: .practice)
        let controller = try await openPanel(for: state)
        defer { controller.close() }
        try selectSafeCell(in: state)
        try await press(Key.space, in: controller)
        #expect(state.status == .playing)

        try await pressCommand(Key.commandR, in: controller)

        #expect(state.status == .notStarted)
        #expect(controller.isOpen)
    }

    @Test("Command-comma opens Settings from the panel")
    func commandCommaOpensSettings() async throws {
        let cleanup = setupCleanPersistenceState(continuousPlay: true)
        defer { cleanup() }

        let controller = try await openPanel(for: todaysDaily())
        defer { controller.close() }

        try await pressCommand(Key.commandComma, in: controller)

        let window = NSApp.windows.first { $0.isVisible && $0.title == AppWindows.settingsTitle }
        #expect(window != nil)
        #expect(!controller.isOpen)
        window?.close()
        try await settle()
    }

    @Test("The main menu carries Settings, Close and Quit for the app's windows")
    func mainMenuHasStandardShortcuts() throws {
        let menu = try #require(NSApp.mainMenu)
        func items(in menu: NSMenu) -> [NSMenuItem] {
            menu.items.flatMap { [$0] + ($0.submenu.map(items(in:)) ?? []) }
        }
        let all = items(in: menu)
        for key in [",", "w", "q"] {
            let item = all.first { $0.keyEquivalent == key && $0.keyEquivalentModifierMask == .command }
            #expect(item != nil, "No Command-\(key) in the main menu")
        }
    }

    // MARK: - Icon presses

    private func event(_ type: NSEvent.EventType, modifiers: NSEvent.ModifierFlags) throws -> NSEvent {
        if type == .keyDown {
            return try #require(NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: modifiers,
                timestamp: now,
                windowNumber: 0,
                context: nil,
                characters: " ",
                charactersIgnoringModifiers: " ",
                isARepeat: false,
                keyCode: Key.space.code
            ))
        }
        return try #require(NSEvent.mouseEvent(
            with: type,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: now,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))
    }

    @Test("Only a right-click or a Control-click asks for the icon's menu")
    func menuRequests() throws {
        #expect(StatusItemController.isMenuRequest(try event(.rightMouseDown, modifiers: [])))
        #expect(StatusItemController.isMenuRequest(try event(.leftMouseDown, modifiers: .control)))
        #expect(!StatusItemController.isMenuRequest(try event(.leftMouseDown, modifiers: [])))
        // VoiceOver presses the icon with Control-Option held.
        #expect(!StatusItemController.isMenuRequest(try event(.keyDown, modifiers: [.control, .option])))
        #expect(!StatusItemController.isMenuRequest(nil))
    }

    @Test("A keyboard press on the icon with Control held opens the game, not the menu")
    func voiceOverPressOpens() async throws {
        let cleanup = setupCleanPersistenceState(continuousPlay: true)
        defer { cleanup() }

        let controller = StatusItemController(gameState: todaysDaily())
        defer { controller.close() }

        controller.handlePress(try event(.keyDown, modifiers: [.control, .option]))
        #expect(controller.isOpen)
    }

    // MARK: - Opening and closing

    @Test("The shortcut and a relaunch open the panel, and the shortcut closes it again")
    func toggleAndReopen() async throws {
        let cleanup = setupCleanPersistenceState(continuousPlay: true)
        defer { cleanup() }

        let controller = StatusItemController(gameState: todaysDaily())
        defer { controller.close() }

        controller.toggle()
        #expect(controller.isOpen)
        controller.toggle()
        #expect(!controller.isOpen)

        controller.openForReopen()
        #expect(controller.isOpen)
        try await takeKeyboard(for: controller)
    }

    @Test("Closing stops the clock at once and the panel fades out after")
    func closeFades() async throws {
        let cleanup = setupCleanPersistenceState(continuousPlay: true)
        defer { cleanup() }

        let state = todaysDaily()
        let controller = try await openPanel(for: state)
        defer { controller.close() }
        try selectSafeCell(in: state)
        try await press(Key.space, in: controller)

        controller.close()
        #expect(!controller.isOpen)
        #expect(state.isPaused)
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            #expect(controller.panel.isVisible)
        }

        try await Task.sleep(for: .seconds(StatusItemController.fadeOutDuration + 0.3))
        #expect(!controller.panel.isVisible)
        #expect(controller.panel.alphaValue == 1)
    }

    @Test("Opening again while the panel fades out puts it straight back")
    func reopenDuringFade() async throws {
        let cleanup = setupCleanPersistenceState(continuousPlay: true)
        defer { cleanup() }

        let state = todaysDaily()
        let controller = try await openPanel(for: state)
        defer { controller.close() }

        try await takeKeyboard(for: controller)
        controller.close()
        controller.open()
        #expect(controller.isOpen)
        #expect(controller.panel.isVisible)
        try await Task.sleep(for: .seconds(StatusItemController.fadeOutDuration + 0.3))

        // The overtaken fade mustn't take the panel away when it ends. Another app taking
        // activation during a test run closes it properly, which is a different matter.
        if controller.isOpen {
            #expect(controller.panel.isVisible)
            #expect(controller.panel.alphaValue == 1)
        } else {
            #expect(!controller.panel.isVisible || controller.panel.isClosing)
        }
    }

    @Test("The panel opens instantly and shows tooltips though the app isn't active")
    func panelConfiguration() {
        let panel = GamePanel()
        #expect(panel.animationBehavior == .none)
        #expect(panel.allowsToolTipsWhenApplicationIsInactive)
    }

    // MARK: - Windows

    func openWindow(_ open: () -> Void, titled title: String) async throws -> NSWindow {
        open()
        try await settle()
        return try #require(NSApp.windows.first { $0.isVisible && $0.title == title })
    }

    @Test("Windows can't be minimised, and open over a full-screen app on its Space")
    func windowBehaviour() async throws {
        let cleanup = setupCleanPersistenceState(continuousPlay: true)
        defer { cleanup() }

        let opens: [(() -> Void, String)] = [
            (AppWindows.showSettings, AppWindows.settingsTitle),
            (AboutWindow.show, String(localized: "about_menu_item")),
            ({ AppWindows.showStats(gameState: todaysDaily()) }, String(localized: "stats_window_title"))
        ]
        for (open, title) in opens {
            let window = try await openWindow(open, titled: title)
            #expect(!window.styleMask.contains(.miniaturizable), "\(title) can be minimised")
            #expect(window.collectionBehavior.contains(.moveToActiveSpace))
            #expect(window.collectionBehavior.contains(.fullScreenAuxiliary))
            window.close()
            try await settle()
        }
    }

    @Test("Settings opens where it was last left")
    func settingsRemembersPosition() async throws {
        let cleanup = setupCleanPersistenceState(continuousPlay: true)
        defer { cleanup() }
        let title = AppWindows.settingsTitle

        let first = try await openWindow(AppWindows.showSettings, titled: title)
        let visible = try #require(first.screen?.visibleFrame)
        let target = NSPoint(x: visible.minX + 40, y: visible.maxY - 40)
        first.setFrameTopLeftPoint(target)
        first.close()
        try await settle()

        let second = try await openWindow(AppWindows.showSettings, titled: title)
        defer { second.close() }
        #expect(second !== first)
        #expect(abs(second.frame.minX - target.x) < 1)
        #expect(abs(second.frame.maxY - target.y) < 1)
    }

    @Test("Command-comma opens Settings from Stats")
    func commandCommaFromWindow() async throws {
        let cleanup = setupCleanPersistenceState(continuousPlay: true)
        defer { cleanup() }

        let stats = try await openWindow(
            { AppWindows.showStats(gameState: todaysDaily()) },
            titled: String(localized: "stats_window_title")
        )
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: now,
            windowNumber: stats.windowNumber,
            context: nil,
            characters: ",",
            charactersIgnoringModifiers: ",",
            isARepeat: false,
            keyCode: Key.commandComma.code
        ))
        #expect(NSApp.mainMenu?.performKeyEquivalent(with: event) == true)
        try await settle()

        let settings = NSApp.windows.first { $0.isVisible && $0.title == AppWindows.settingsTitle }
        #expect(settings != nil)
        settings?.close()
        stats.close()
        try await settle()
    }

    // MARK: - Menu and icon

    @Test("The icon's menu has the gear menu's app-wide items")
    func statusMenuItems() {
        let controller = StatusItemController(gameState: todaysDaily())
        let titles = controller.makeMenu().items.filter { !$0.isSeparatorItem }.map(\.title)
        var expected = [
            String(localized: "daily_history_menu_item"),
            String(localized: "stats_menu_item"),
            String(localized: "settings_menu_item")
        ]
        if UpdateManager.isUpdateSupported {
            expected.append(String(localized: "check_for_updates_menu_item"))
        }
        expected += [String(localized: "about_menu_item"), String(localized: "quit_menu_item")]
        #expect(titles == expected)
    }

    @Test("Every icon state draws as a template image that fits the menu bar")
    func iconImages() throws {
        let states: [MenuBarIconState] = [.normal, .incomplete, .playing, .paused, .complete, .lost]
        for state in states {
            for showingResult in [true, false] {
                let image = try #require(StatusIconImage.make(for: state, showingResult: showingResult))
                #expect(image.isTemplate)
                #expect(image.size.height <= NSStatusBar.system.thickness)
                #expect(image.size.width <= NSStatusBar.system.thickness)
            }
        }
    }

    // MARK: - Position

    /// Where the panel should be, from the icon as it is now.
    func expectPanelUnderIcon(_ controller: StatusItemController, _ path: String) {
        let frame = controller.panel.frame
        let expected = StatusItemController.panelOrigin(
            for: frame.size,
            under: controller.iconAnchor,
            fallbackScreen: (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
        )
        #expect(abs(frame.minX - expected.x) < 1, "\(path): x is \(frame.minX), expected \(expected.x)")
        #expect(abs(frame.minY - expected.y) < 1, "\(path): y is \(frame.minY), expected \(expected.y)")

        guard let icon = controller.iconAnchor else { return }
        // Top edge just under the icon, and centred on it unless that would run off screen.
        let top = min(icon.frame.minY, icon.screen.maxY)
        #expect(abs(frame.maxY - (top - StatusItemController.margin)) < 1, "\(path)")
        if frame.minX > icon.screen.minX + StatusItemController.margin + 1,
           frame.maxX < icon.screen.maxX - StatusItemController.margin - 1 {
            #expect(abs(frame.midX - icon.frame.midX) < 1, "\(path)")
        }
    }

    @Test("The panel opens directly under the icon, whichever way it's opened")
    func opensUnderIcon() async throws {
        let cleanup = setupCleanPersistenceState(continuousPlay: true)
        defer { cleanup() }

        let controller = StatusItemController(gameState: todaysDaily())
        defer { controller.close() }
        try await settle()

        controller.handlePress(try iconClick(at: now))
        #expect(controller.isOpen)
        expectPanelUnderIcon(controller, "click")
        controller.close()
        try await settle()

        controller.toggle()
        expectPanelUnderIcon(controller, "shortcut")
        controller.close()
        try await settle()

        controller.openFromWindow()
        expectPanelUnderIcon(controller, "from a window")
        controller.close()
        try await settle()

        controller.openForReopen()
        expectPanelUnderIcon(controller, "relaunch")
    }

    @Test("Placement hangs the panel under the icon, clamps it to the screen, and falls back only without an icon")
    func placement() {
        let screen = NSRect(x: 0, y: 0, width: 1440, height: 875)
        let size = NSSize(width: 300, height: 372)
        let margin = StatusItemController.margin

        let icon = NSRect(x: 1000, y: 875, width: 22, height: 24)
        let under = StatusItemController.panelOrigin(for: size, under: (icon, screen), fallbackScreen: nil)
        #expect(under.y + size.height == icon.minY - margin)
        #expect(under.x + size.width / 2 == icon.midX)

        let nearEdge = NSRect(x: 1410, y: 875, width: 22, height: 24)
        let clamped = StatusItemController.panelOrigin(for: size, under: (nearEdge, screen), fallbackScreen: nil)
        #expect(clamped.x + size.width == screen.maxX - margin)
        #expect(clamped.y + size.height == nearEdge.minY - margin)

        // A second screen to the left, with the icon on it.
        let left = NSRect(x: -1920, y: 0, width: 1920, height: 1055)
        let leftIcon = NSRect(x: -400, y: 1055, width: 22, height: 24)
        let onLeft = StatusItemController.panelOrigin(for: size, under: (leftIcon, left), fallbackScreen: screen)
        #expect(onLeft.x + size.width / 2 == leftIcon.midX)
        #expect(onLeft.y + size.height == leftIcon.minY - margin)

        let fallback = StatusItemController.panelOrigin(for: size, under: nil, fallbackScreen: screen)
        #expect(fallback.x + size.width / 2 == screen.midX)
        #expect(fallback.y + size.height == screen.maxY - margin)
    }
}
