import AppKit
import SwiftUI

/// The app's document-style windows: Stats, Settings and About.
///
/// These are built here rather than as SwiftUI scenes so that the app owns each window from
/// the moment it's asked for. MenuMines is an agent app (`LSUIElement`), so it is never the
/// frontmost application on its own, and anything it opens lands behind whatever the player
/// was using unless it's raised, which needs the window to exist.
@MainActor
enum AppWindows {
    /// Called before a window opens, so that the game panel can get out of its way.
    static var onWillShowWindow: (() -> Void)?

    /// Opens the game panel. Set by `StatusItemController`, which owns it.
    static var onShowGame: (() -> Void)?

    /// Whether the game panel is on screen.
    static var isGameShowing: () -> Bool = { false }

    private static var controllers: [String: NSWindowController] = [:]
    private static let statsWindowID = "stats"

    /// Which tab Stats shows. Held here so that asking for Daily History can turn a Stats
    /// window that's already open to the calendar.
    static let statsNavigation = StatsNavigation()

    /// Shows Stats.
    /// - Parameter tab: The tab to turn to. With none, a window that's already open keeps
    ///   its place and a new one starts on the summary.
    static func showStats(gameState: GameState, tab: StatsTab? = nil) {
        let isOpen = controllers[statsWindowID]?.window?.isVisible == true
        if let tab {
            statsNavigation.tab = tab
        } else if !isOpen {
            statsNavigation.tab = .summary
        }

        show(
            id: statsWindowID,
            title: String(localized: "stats_window_title"),
            remembersPosition: true,
            minimumContentSize: statsMinimumContentSize,
            idealContentSize: { StatsWindow.idealContentSize(gameState: gameState, navigation: statsNavigation) },
            hasToolbar: true,
            content: {
                StatsWindow(
                    gameState: gameState,
                    navigation: statsNavigation,
                    onPlayDay: { seed in playPastDay(seed: seed, gameState: gameState) },
                    onContentHeightChange: { height in
                        // Not in the middle of SwiftUI's layout pass, which is where it's heard.
                        DispatchQueue.main.async {
                            if let window = controllers[statsWindowID]?.window {
                                fit(window, toContentHeight: height)
                            }
                        }
                    }
                )
            }
        )
    }

    /// The smallest Statistics' content gets, whatever it reports.
    static let statsMinimumContentSize = NSSize(width: StatsWindow.width, height: 280)

    /// Shows Stats turned to the Daily History calendar, where past days are picked.
    static func showDailyHistory(gameState: GameState) {
        showStats(gameState: gameState, tab: .history)
    }

    /// Takes the player straight to a past day's board: Stats comes down and the game panel
    /// opens on it, with the keyboard on the board.
    ///
    /// The clock is started here as well as by the panel appearing. A tile can be activated
    /// from the keyboard or VoiceOver while the panel is already up, and then nothing appears:
    /// a resumed game would sit paused, and since only the first reveal starts the clock, the
    /// rest of it would be played for free. Starting a running clock again does nothing, and
    /// with the panel closed the clock is left for the panel to start when it opens.
    static func playPastDay(seed: Int64, gameState: GameState) {
        guard gameState.playPastDay(seed: seed) else { return }

        controllers[statsWindowID]?.window?.close()
        onShowGame?()
        if isGameShowing() {
            gameState.resumeTimer()
        }
    }

    /// "MenuMines Settings", as the HIG titles a single-pane settings window, with the name
    /// this build goes by.
    static var settingsTitle: String {
        let name = Bundle.main.appName
        return String(localized: "settings_window_title \(name)")
    }

    static func showSettings() {
        show(
            id: "settings",
            title: settingsTitle,
            remembersPosition: true,
            minimumContentSize: SettingsView.Layout.minimumSize,
            idealContentSize: { SettingsView.idealContentSize },
            content: { SettingsView() }
        )
    }

    /// Brings a window forward, building it if it isn't open. A closed window is built again
    /// rather than reused, so it never shows what was on screen last time.
    ///
    /// The window's size is always set here, never left to the hosting controller: content
    /// that scrolls, such as a grouped `Form`, can report next to no height, which once opened
    /// windows a few points tall. The size comes from `idealContentSize` when the content can
    /// scroll, or the content's fitting size otherwise, and is never below the minimum.
    /// - Parameters:
    ///   - remembersPosition: Whether the window goes back where the player last left it.
    ///     Otherwise, and the first time, it opens in the middle of the screen. Only the
    ///     position comes back, never the saved size.
    ///   - minimumContentSize: The smallest the content area can be.
    ///   - idealContentSize: The size the content wants, measured without scrolling.
    ///   - hasToolbar: Whether the content's `.toolbar` items go in the window's toolbar.
    static func show<Content: View>(
        id: String,
        title: String,
        remembersPosition: Bool = false,
        minimumContentSize: NSSize = NSSize(width: 300, height: 200),
        idealContentSize: (() -> NSSize)? = nil,
        hasToolbar: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        onWillShowWindow?()

        if let window = controllers[id]?.window, window.isVisible {
            raise(window)
            return
        }

        let host = NSHostingController(rootView: content())
        if idealContentSize != nil {
            // Content that scrolls fills whatever size the window is given, and the window's
            // size is ours. Left to the hosting controller, a scroll view's lack of a height
            // could shrink the window to nothing.
            host.sizingOptions = []
        }
        if hasToolbar {
            host.sceneBridgingOptions = [.toolbars]
        }
        let window = NSWindow(contentViewController: host)
        window.title = title
        if hasToolbar {
            window.toolbarStyle = .unified
            // The tabs are the toolbar, centred, and there isn't room for the title beside
            // them. The title is still the window's name in the Window menu and to VoiceOver.
            window.titleVisibility = .hidden
        }
        // Not miniaturizable: an agent app has no Dock icon to bring a minimised window
        // back from, and these are small utility windows that close instead.
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        // Opened from the menu bar, a window joins whatever the player is looking at, even a
        // full-screen app, rather than switching them to another Space.
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        // Activation can be refused, and the window is still raised over the other app's.
        window.allowsToolTipsWhenApplicationIsInactive = true
        window.contentMinSize = minimumContentSize

        // Sized first, because centering uses the height the window has at the time.
        let wanted = idealContentSize?() ?? host.view.fittingSize
        let contentSize = contentSize(wanted: wanted, minimum: minimumContentSize)
        window.setContentSize(contentSize)
        place(window, autosaveName: remembersPosition ? "MenuMines.\(id)" : nil, contentSize: contentSize)

        let controller = NSWindowController(window: window)
        controllers[id] = controller
        controller.showWindow(nil)
        openedAt[ObjectIdentifier(window)] = ProcessInfo.processInfo.systemUptime
        if hasToolbar {
            // A unified toolbar is put in place once the window is up, and covers the top of
            // the content, which is inset below it. The window then grows by that much.
            DispatchQueue.main.async { [weak window] in
                if let window {
                    fit(window, toContentHeight: contentSize.height)
                }
            }
        }
        raise(window)
    }

    /// When each window opened, so that the size it settles at as it opens isn't animated.
    private static var openedAt: [ObjectIdentifier: TimeInterval] = [:]

    /// Grows or shrinks a window to the height its content wants, keeping its top edge where
    /// it is, as a window that changes pane does. Never below its minimum or taller than the
    /// screen. Animated, unless Reduce Motion is on.
    static func fit(_ window: NSWindow, toContentHeight height: CGFloat) {
        guard height.isFinite else { return }
        // In terms of the part of the content the toolbar doesn't cover, so it comes out the
        // same however often it's asked, before the toolbar is in or after.
        let target = min(max(height, window.contentMinSize.height), screenLimitedContentHeight).rounded(.up)
        let delta = target - window.contentLayoutRect.height
        guard abs(delta) >= 1 else { return }

        var frame = window.frame
        frame.origin.y -= delta
        frame.size.height += delta
        // Growing off the bottom of the screen, it moves up instead.
        if let visible = (window.screen ?? NSScreen.main)?.visibleFrame, frame.minY < visible.minY {
            frame.origin.y = visible.minY
        }
        let openedAt = openedAt[ObjectIdentifier(window)]
        let isSettled = openedAt.map { ProcessInfo.processInfo.systemUptime - $0 > 0.5 } ?? true
        let animate = window.isVisible && isSettled && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        window.setFrame(frame, display: true, animate: animate)
    }

    /// The content size a window opens at: what the content wants, no smaller than the
    /// minimum, and no taller than fits on the screen.
    static func contentSize(wanted: NSSize, minimum: NSSize) -> NSSize {
        let width = wanted.width.isFinite ? max(wanted.width, minimum.width) : minimum.width
        let height = wanted.height.isFinite ? max(wanted.height, minimum.height) : minimum.height
        return NSSize(width: width.rounded(.up), height: min(height, screenLimitedContentHeight).rounded(.up))
    }

    /// The tallest a window's content can be and still fit on the screen under its title bar.
    static var screenLimitedContentHeight: CGFloat {
        let visibleHeight = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame.height ?? 800
        return max(visibleHeight - 80, 300)
    }

    /// Puts a window where it was last left, keeping the size its content asks for now, or
    /// in the middle of the screen if it has never been moved.
    private static func place(_ window: NSWindow, autosaveName: String?, contentSize: NSSize) {
        guard let autosaveName else {
            window.center()
            return
        }

        if window.setFrameUsingName(autosaveName) {
            // The saved frame's size is from whatever the content was then, and may be
            // degenerate. Only its top-left corner is kept.
            let top = window.frame.maxY
            window.setContentSize(contentSize)
            window.setFrameTopLeftPoint(NSPoint(x: window.frame.minX, y: top))
            if let visible = (window.screen ?? NSScreen.main)?.visibleFrame, !visible.contains(window.frame) {
                window.setFrame(window.constrainFrameRect(window.frame, to: window.screen), display: false)
            }
        } else {
            window.center()
        }
        window.setFrameAutosaveName(autosaveName)
    }

    /// Called as any of the app's windows closes. Lets go of the controller of one built
    /// here, so a closed window doesn't stay in memory until it's next opened, then gives
    /// focus back if nothing else is left on screen.
    static func windowWillClose(_ window: NSWindow) {
        openedAt[ObjectIdentifier(window)] = nil
        if let id = controllers.first(where: { $0.value.window === window })?.key {
            let controller = controllers[id]
            // After the close has run its course, and only if a new window hasn't taken
            // its place in the meantime.
            DispatchQueue.main.async {
                if let controller, controllers[id] === controller {
                    controllers[id] = nil
                }
            }
        }
        yieldFocusIfNoWindowsRemain(closing: window)
    }

    /// The player asked for this window, so it comes forward whatever they were doing.
    ///
    /// `NSApp.activate()`, the macOS 14 replacement, isn't used because it's only a request,
    /// and the frontmost app hasn't offered to give way to us, so it's often declined.
    /// `orderFrontRegardless` covers the case where activation doesn't lift the window over
    /// another app's.
    private static func raise(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    /// Gives focus back to the player's previous app once our last window has closed.
    ///
    /// An agent app stays active with nothing on screen otherwise, so keys go nowhere until
    /// the player clicks another window. The closing window still counts as visible during
    /// this notification, so the check waits a turn, and leaves it out in case it doesn't.
    ///
    /// Every titled window counts, not only the ones built here: hiding the app would also
    /// take away an update window, a Game Center sign-in or an alert. So does the game panel.
    /// It's up when a window closes because a past day was picked in it, and hiding the app
    /// would take the panel away with it.
    static func yieldFocusIfNoWindowsRemain(closing: NSWindow? = nil) {
        DispatchQueue.main.async {
            let isShowingWindow = NSApp.windows.contains { window in
                window !== closing
                    && window.isVisible
                    && !(window is GamePanel)
                    && (window.styleMask.contains(.titled) || window.isSheet || window.level == .modalPanel)
            }
            if !isShowingWindow && !isGameShowing() {
                NSApp.hide(nil)
            }
        }
    }
}

extension Bundle {
    /// The name the app goes by on screen, which differs between builds ("MenuMines Dev").
    var appName: String {
        object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "MenuMines"
    }
}
