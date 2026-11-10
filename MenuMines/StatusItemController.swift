import AppKit
import SwiftUI

/// The menu bar icon and the game panel it opens.
///
/// Built on `NSStatusItem` because `MenuBarExtra` can't be told to open or close, doesn't say
/// when it's on screen, and leaves keyboard focus to chance. The panel never activates the
/// app: the player's own app stays frontmost while the keys come here.
@MainActor
final class StatusItemController: NSObject {
    let gameState: GameState
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var iconUpdater: StatusIconUpdater?
    let panel = GamePanel()

    // What closes the panel, while it's open. Kept by StatusItemController+Dismissal.
    var clickMonitors: [Any] = []
    var workspaceObservers: [NSObjectProtocol] = []
    var lockObserver: NSObjectProtocol?
    var screenObserver: NSObjectProtocol?
    private var mouseUpMonitors: [Any] = []

    /// When the panel last closed, on the clock that stamps events.
    private var closedAt: TimeInterval?

    /// Whether the panel was opened from one of the app's windows, which leaves the app
    /// active behind it. Closing the panel then has to hand focus back.
    private var wasOpenedFromWindow = false

    /// Bumped on every open and close, so a fade that's been overtaken doesn't finish.
    private var closeGeneration = 0

    /// Space between the menu bar and the panel, and between the panel and the screen edge.
    static let margin: CGFloat = 6

    /// The longest a click can wait to be handled and still count as the one that closed the panel.
    private static let sameClickWindow: TimeInterval = 1

    /// How long the panel takes to fade out. Menus vanish about this fast, and open at once.
    static let fadeOutDuration: TimeInterval = 0.15

    /// Whether the panel is open. It stops counting as open the moment it starts to close,
    /// before its fade has finished.
    private(set) var isOpen = false

    init(gameState: GameState) {
        self.gameState = gameState
        super.init()

        // Escape and ⌘W: a key closed it, so the next key goes to the player's app at once.
        panel.onCancel = { [weak self] in self?.close(returningFocus: true, immediately: true) }
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
        button.imagePosition = .imageOnly
        iconUpdater = StatusIconUpdater(gameState: gameState, button: button)
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
        if Self.isMenuRequest(event) {
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

    /// Opens or closes the panel, as the global shortcut does.
    func toggle() {
        if isOpen {
            close(returningFocus: true, immediately: true)
        } else if NSApp.isActive {
            // One of our windows is in front, so the app stays active behind the panel and
            // closing it has to give focus back, as when the panel opens from Stats.
            openFromWindow()
        } else {
            open()
        }
    }

    /// Opens the panel when the app is launched again from Finder or Spotlight. That
    /// activates the app, so closing the panel hands focus back.
    func openForReopen() {
        guard !isOpen else { return }
        if NSApp.isActive {
            openFromWindow()
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
        isOpen = true
        closeGeneration += 1

        if panel.isClosing {
            // Still fading out, so the same content comes straight back. Swapping in a new
            // host here would have the old one's disappear, which pauses the clock, land
            // after the new one's appear.
            panel.isClosing = false
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                panel.animator().alphaValue = 1
            }
            gameState.resumeTimer()
            show()
            return
        }

        // A new host each time is what gives the content its appear and disappear, which
        // start and stop the game clock.
        let content = MenuContentView(gameState: gameState)
            .clipShape(RoundedRectangle(cornerRadius: PanelBackdropController.cornerRadius, style: .continuous))
        let host = NSHostingController(rootView: content)
        host.sizingOptions = [.preferredContentSize]
        let backdrop = PanelBackdropController(content: host)
        backdrop.onContentSizeChange = { [weak self] size in self?.resize(to: size) }
        panel.contentViewController = backdrop
        panel.setContentSize(backdrop.contentSize)
        panel.alphaValue = 1
        show()
    }

    private func show() {
        panel.setFrameOrigin(panelOrigin(for: panel.frame.size))
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()
        setHighlighted(true)
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

    /// Closes the panel. The game clock stops at once, and the panel fades out after it, as
    /// a menu does, unless Reduce Motion is on.
    /// - Parameter immediately: Skips the fade, for a close that came from a key. The panel
    ///   stays key until it's off screen and takes no input while it fades, so the keys typed
    ///   straight after Escape would be lost instead of reaching the player's own app.
    func close(returningFocus: Bool, immediately: Bool = false) {
        guard isOpen else { return }
        isOpen = false

        stopWatchingForDismissal()
        // The content's disappear does this too, but not until the fade is over.
        gameState.pauseTimer()
        gameState.save()
        setHighlighted(false)
        closedAt = ProcessInfo.processInfo.systemUptime

        closeGeneration += 1
        let generation = closeGeneration
        panel.isClosing = true
        if immediately || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || !panel.isVisible {
            finishClosingNow()
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.fadeOutDuration
                panel.animator().alphaValue = 0
            } completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.closeGeneration == generation else { return }
                    self.finishClosingNow()
                }
            }
        }

        if returningFocus {
            returnFocusIfTaken()
        }
    }

    /// Takes the panel off screen, ending a fade that's under way.
    private func finishClosingNow() {
        guard panel.isClosing else { return }
        panel.orderOut(nil)
        panel.contentViewController = nil
        panel.alphaValue = 1
        panel.isClosing = false
    }

    /// Hands focus back to the player's own app, if the panel was holding it for ours.
    func returnFocusIfTaken() {
        guard wasOpenedFromWindow else { return }
        wasOpenedFromWindow = false

        if NSApp.isActive {
            AppWindows.yieldFocusIfNoWindowsRemain()
        }
    }

    /// The icon stays highlighted while the panel is up, as it would for a menu.
    ///
    /// The press arrives on mouse-down, and the button lets go of its highlight when the
    /// mouse comes up, so it's set again then.
    private func setHighlighted(_ isHighlighted: Bool) {
        mouseUpMonitors.forEach(NSEvent.removeMonitor)
        mouseUpMonitors = []
        statusItem.button?.highlight(isHighlighted)
        guard isHighlighted, NSApp.currentEvent?.type == .leftMouseDown else { return }

        let reassert: () -> Void = { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.isOpen else { return }
                self.statusItem.button?.highlight(true)
                self.mouseUpMonitors.forEach(NSEvent.removeMonitor)
                self.mouseUpMonitors = []
            }
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp, handler: { event in
            reassert()
            return event
        }) {
            mouseUpMonitors.append(monitor)
        }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: { _ in reassert() }) {
            mouseUpMonitors.append(monitor)
        }
    }
}
