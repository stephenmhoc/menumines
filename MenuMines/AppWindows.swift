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

        show(id: statsWindowID, title: String(localized: "stats_window_title"), remembersPosition: true) {
            StatsWindow(gameState: gameState, navigation: statsNavigation) { seed in
                playPastDay(seed: seed, gameState: gameState)
            }
        }
    }

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
        String(format: String(localized: "settings_window_title"), Bundle.main.appName)
    }

    static func showSettings() {
        show(id: "settings", title: settingsTitle, remembersPosition: true) {
            SettingsView()
        }
    }

    /// Brings a window forward, building it if it isn't open. A closed window is built again
    /// rather than reused, so it never shows what was on screen last time.
    /// - Parameter remembersPosition: Whether the window goes back where the player last left
    ///   it. Otherwise, and the first time, it opens in the middle of the screen.
    static func show<Content: View>(
        id: String,
        title: String,
        remembersPosition: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        onWillShowWindow?()

        if let window = controllers[id]?.window, window.isVisible {
            raise(window)
            return
        }

        let window = NSWindow(contentViewController: NSHostingController(rootView: content()))
        window.title = title
        // Not miniaturizable: an agent app has no Dock icon to bring a minimised window
        // back from, and these are small utility windows that close instead.
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        // Opened from the menu bar, a window joins whatever the player is looking at, even a
        // full-screen app, rather than switching them to another Space.
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        // Activation can be refused, and the window is still raised over the other app's.
        window.allowsToolTipsWhenApplicationIsInactive = true
        // Sized first, because centering uses the height the window has at the time.
        let contentSize = window.contentView?.fittingSize
        if let contentSize {
            window.setContentSize(contentSize)
        }
        place(window, autosaveName: remembersPosition ? "MenuMines.\(id)" : nil, contentSize: contentSize)

        let controller = NSWindowController(window: window)
        controllers[id] = controller
        controller.showWindow(nil)
        raise(window)
    }

    /// Puts a window where it was last left, keeping the size its content asks for now, or
    /// in the middle of the screen if it has never been moved.
    private static func place(_ window: NSWindow, autosaveName: String?, contentSize: NSSize?) {
        guard let autosaveName else {
            window.center()
            return
        }

        if window.setFrameUsingName(autosaveName) {
            // The saved frame's size is from whatever the content was then.
            let top = window.frame.maxY
            if let contentSize {
                window.setContentSize(contentSize)
            }
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
