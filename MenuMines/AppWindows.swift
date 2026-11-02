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

    private static var controllers: [String: NSWindowController] = [:]

    static func showStats(gameState: GameState) {
        show(id: "stats", title: String(localized: "stats_window_title")) {
            StatsWindow(gameState: gameState)
        }
    }

    static func showSettings() {
        show(id: "settings", title: String(localized: "settings_window_title")) {
            SettingsView()
        }
    }

    /// Brings a window forward, building it if it isn't open. A closed window is built again
    /// rather than reused, so it never shows what was on screen last time.
    static func show<Content: View>(id: String, title: String, @ViewBuilder content: () -> Content) {
        onWillShowWindow?()

        if let window = controllers[id]?.window, window.isVisible {
            raise(window)
            return
        }

        let window = NSWindow(contentViewController: NSHostingController(rootView: content()))
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        // Sized first, because centering uses the height the window has at the time.
        if let contentView = window.contentView {
            window.setContentSize(contentView.fittingSize)
        }
        window.center()

        let controller = NSWindowController(window: window)
        controllers[id] = controller
        controller.showWindow(nil)
        raise(window)
    }

    /// The player asked for this window, so it comes forward whatever they were doing.
    ///
    /// `NSApp.activate()` isn't used because it's only a request, and the frontmost app hasn't
    /// offered to give way to us, so it's often declined. `orderFrontRegardless` covers the
    /// case where activation doesn't lift the window over another app's.
    private static func raise(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    /// Gives focus back to the player's previous app once our last window has closed.
    ///
    /// An agent app stays active with nothing on screen otherwise, so keys go nowhere until
    /// the player clicks another window. The closing window still counts as visible during
    /// this notification, so the check waits a turn.
    static func yieldFocusIfNoWindowsRemain() {
        DispatchQueue.main.async {
            let isShowingWindow = controllers.values.contains { $0.window?.isVisible == true }
            if !isShowingWindow {
                NSApp.hide(nil)
            }
        }
    }
}
