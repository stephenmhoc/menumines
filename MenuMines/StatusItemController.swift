import AppKit
import SwiftUI

/// The menu bar icon and the game panel it opens.
///
/// Built on `NSStatusItem` because `MenuBarExtra` can't be told to open or close, doesn't say
/// when it's on screen, and leaves keyboard focus to chance. The panel never activates the
/// app: the player's own app stays frontmost while the keys come here.
@MainActor
final class StatusItemController: NSObject {
    private let gameState: GameState
    private let statusItem = NSStatusBar.system.statusItem(withLength: 28)
    let panel = GamePanel()

    private var clickMonitors: [Any] = []
    private var workspaceObservers: [NSObjectProtocol] = []

    /// When the panel last closed, on the clock that stamps events.
    private var closedAt: TimeInterval?

    /// Whether the panel was opened from one of the app's windows, which leaves the app
    /// active behind it. Closing the panel then has to hand focus back.
    private var wasOpenedFromWindow = false

    /// Space between the menu bar and the panel, and between the panel and the screen edge.
    private static let margin: CGFloat = 6

    /// The longest a click can wait to be handled and still count as the one that closed the panel.
    private static let sameClickWindow: TimeInterval = 1

    var isOpen: Bool { panel.isVisible }

    init(gameState: GameState) {
        self.gameState = gameState
        super.init()

        panel.onCancel = { [weak self] in self?.close() }
        AppWindows.onWillShowWindow = { [weak self] in self?.close() }
        AppWindows.onShowGame = { [weak self] in self?.openFromWindow() }
        AppWindows.isGameShowing = { [weak self] in self?.isOpen ?? false }
        configureButton()
    }

    private func configureButton() {
        statusItem.autosaveName = "MenuMines"
        guard let button = statusItem.button else { return }

        button.target = self
        button.action = #selector(buttonPressed)
        button.sendAction(on: [.leftMouseDown, .rightMouseDown])

        let icon = StatusIconHostingView(rootView: MenuBarIconView(gameState: gameState) { [weak button] label in
            button?.setAccessibilityLabel(label)
        })
        icon.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(icon)
        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: button.centerYAnchor)
        ])
    }

    @objc private func buttonPressed() {
        handlePress(NSApp.currentEvent)
    }

    /// A press on the icon toggles the panel, going by how things stood when the mouse went
    /// down rather than how they stand now.
    ///
    /// The system draws the icon in a window of its own, so the click lands in another
    /// process and is passed on from there. That makes it a click elsewhere as well as a
    /// press, and if the click elsewhere is heard first the panel is already closed by the
    /// time the press arrives. Reopening it then would leave it looking as if it never closed.
    func handlePress(_ event: NSEvent?) {
        if event?.type == .rightMouseDown || event?.modifierFlags.contains(.control) == true {
            showMenu()
            return
        }

        let wasOpenAtMouseDown: Bool
        if isOpen {
            wasOpenAtMouseDown = true
        } else if let event, event.type == .leftMouseDown, let closedAt {
            // Only a close this click could have caused counts, so a clock that disagrees
            // with the events' can't keep the panel shut.
            wasOpenAtMouseDown = (0...Self.sameClickWindow).contains(closedAt - event.timestamp)
        } else {
            wasOpenAtMouseDown = false
        }

        if wasOpenAtMouseDown {
            close()
            // This click has had its say. One made before it's handled should open the panel.
            closedAt = nil
        } else {
            open()
        }
    }

    /// Where the icon is on the screen.
    var iconFrame: NSRect? { statusItem.button?.window?.frame }

    /// Whether a click seen from outside the app landed on the icon.
    func isOnIcon(_ event: NSEvent) -> Bool {
        guard let iconFrame else { return false }

        // An event with no window gives its place on the screen.
        let location = event.window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow
        return iconFrame.contains(location)
    }

    func open() {
        guard !isOpen else { return }

        // A new host each time is what gives the content its appear and disappear, which
        // start and stop the game clock.
        let content = MenuContentView(gameState: gameState)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        let host = NSHostingController(rootView: content)
        host.sizingOptions = [.preferredContentSize]
        panel.contentViewController = host
        panel.setContentSize(host.view.fittingSize)
        panel.setFrameOrigin(panelOrigin(for: panel.frame.size))

        panel.makeKeyAndOrderFront(nil)
        statusItem.button?.highlight(true)
        startWatchingForDismissal()
    }

    /// Opens the panel in place of a window of ours that has just closed.
    ///
    /// Showing that window activated the app, and it stays active behind the panel. That's
    /// what lets the panel take the keyboard straight from the window, but an agent app
    /// left active with nothing on screen swallows the keys, so `close` gives focus back.
    func openFromWindow() {
        open()
        wasOpenedFromWindow = true
    }

    func close() {
        close(returningFocus: true)
    }

    private func close(returningFocus: Bool) {
        guard isOpen else { return }

        stopWatchingForDismissal()
        panel.orderOut(nil)
        panel.contentViewController = nil
        statusItem.button?.highlight(false)
        closedAt = ProcessInfo.processInfo.systemUptime

        if returningFocus {
            returnFocusIfTaken()
        }
    }

    /// Hands focus back to the player's own app, if the panel was holding it for ours.
    private func returnFocusIfTaken() {
        guard wasOpenedFromWindow else { return }
        wasOpenedFromWindow = false

        if NSApp.isActive {
            AppWindows.yieldFocusIfNoWindowsRemain()
        }
    }

    /// Under the icon, kept on the icon's screen.
    private func panelOrigin(for size: NSSize) -> NSPoint {
        guard let buttonWindow = statusItem.button?.window else { return .zero }

        let anchor = buttonWindow.frame
        let visibleFrame = (buttonWindow.screen ?? NSScreen.main)?.visibleFrame ?? anchor
        let centered = anchor.midX - size.width / 2
        let x = min(max(centered, visibleFrame.minX + Self.margin), visibleFrame.maxX - size.width - Self.margin)
        return NSPoint(x: x, y: anchor.minY - size.height - Self.margin)
    }

    /// Closes on a click anywhere else, as a menu would. The panel doesn't close when it
    /// stops being key, because its own gear menu and share sheet take key from it.
    private func startWatchingForDismissal() {
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]

        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: clicks, handler: { [weak self] event in
            // A click on the icon also arrives as a press, and the press decides.
            MainActor.assumeIsolated {
                guard let self, !self.isOnIcon(event) else { return }
                self.close()
            }
        }) {
            clickMonitors.append(monitor)
        }

        if let monitor = NSEvent.addLocalMonitorForEvents(matching: clicks, handler: { [weak self] event in
            // The icon's own click arrives as a press, and toggles the panel.
            if event.window?.canBecomeMain == true {
                MainActor.assumeIsolated { self?.close() }
            }
            return event
        }) {
            clickMonitors.append(monitor)
        }

        let workspace = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            workspace.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.close() }
            },
            // Cmd-Tab and the like take the keyboard without a click. Left open, the panel
            // would float there with no keys reaching it.
            workspace.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                let isOtherApp = app?.processIdentifier != ProcessInfo.processInfo.processIdentifier
                MainActor.assumeIsolated {
                    if isOtherApp {
                        self?.close()
                    }
                }
            }
        ]
    }

    private func stopWatchingForDismissal() {
        clickMonitors.forEach(NSEvent.removeMonitor)
        clickMonitors = []
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        workspaceObservers = []
    }

    // MARK: - Menu

    private func showMenu() {
        // Focus goes back once the menu is done with, not while it's tracking.
        close(returningFocus: false)
        defer { returnFocusIfTaken() }

        let menu = NSMenu()
        menu.addItem(item("daily_history_menu_item", #selector(showDailyHistory)))
        menu.addItem(item("stats_menu_item", #selector(showStats)))
        menu.addItem(item("settings_menu_item", #selector(showSettings)))
        menu.addItem(.separator())
        menu.addItem(item("about_menu_item", #selector(showAbout)))
        menu.addItem(item("quit_menu_item", #selector(quit)))

        // Attached only for this click, because an attached menu replaces the left click.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func item(_ key: String.LocalizationValue, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: String(localized: key), action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func showStats() {
        AppWindows.showStats(gameState: gameState)
    }

    @objc private func showDailyHistory() {
        AppWindows.showDailyHistory(gameState: gameState)
    }

    @objc private func showSettings() {
        AppWindows.showSettings()
    }

    @objc private func showAbout() {
        AboutWindow.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

/// A floating panel that takes the keyboard without activating the app.
final class GamePanel: NSPanel {
    var onCancel: (() -> Void)?

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
    }

    // A borderless window refuses key by default, and without it nothing reaches the board.
    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

/// Draws the icon inside the status item's button, leaving clicks to the button.
private final class StatusIconHostingView: NSHostingView<MenuBarIconView> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
