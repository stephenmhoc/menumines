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

    /// Space between the menu bar and the panel, and between the panel and the screen edge.
    private static let margin: CGFloat = 6

    var isOpen: Bool { panel.isVisible }

    init(gameState: GameState) {
        self.gameState = gameState
        super.init()

        panel.onCancel = { [weak self] in self?.close() }
        AppWindows.onWillShowWindow = { [weak self] in self?.close() }
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
        let event = NSApp.currentEvent
        if event?.type == .rightMouseDown || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else if isOpen {
            close()
        } else {
            open()
        }
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

    func close() {
        guard isOpen else { return }

        stopWatchingForDismissal()
        panel.orderOut(nil)
        panel.contentViewController = nil
        statusItem.button?.highlight(false)
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

        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: clicks, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
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
        close()

        let menu = NSMenu()
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
