import AppKit

/// What closes the game panel besides the player asking: a click elsewhere, another app, a
/// Space change, the display sleeping, the screen locking or a user switch.
extension StatusItemController {
    /// Closes on a click anywhere else, as a menu would. The panel doesn't close when it
    /// stops being key, because its own gear menu and share sheet take key from it.
    func startWatchingForDismissal() {
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
            MainActor.assumeIsolated {
                guard let self else { return }
                let iconWindow = self.statusItem.button?.window
                if Self.closesPanel(clickIn: event.window, panel: self.panel, iconWindow: iconWindow) {
                    self.close()
                }
            }
            return event
        }) {
            clickMonitors.append(monitor)
        }

        watchForLeavingTheGame()
    }

    /// Whether a click in one of the app's own windows takes the player away from the panel.
    ///
    /// Any other window of ours does: Statistics, Settings, an alert, and the standard About
    /// panel, which can't become main. Not the panel itself, nor the icon's window (the icon's
    /// own click arrives as a press, and toggles the panel), nor what the panel opens over
    /// itself, such as a popover, which is attached to it and has no title bar, or a menu.
    static func closesPanel(clickIn window: NSWindow?, panel: NSWindow, iconWindow: NSWindow?) -> Bool {
        guard let window, window !== panel, window !== iconWindow else { return false }
        var parent = window.parent
        while let ancestor = parent {
            if ancestor === panel { return false }
            parent = ancestor.parent
        }
        return window.canBecomeMain || window.styleMask.contains(.titled)
    }

    /// Closes when the player turns to something else, or leaves the Mac.
    private func watchForLeavingTheGame() {
        let workspace = NSWorkspace.shared.notificationCenter
        let closingNotifications: [Notification.Name] = [
            NSWorkspace.activeSpaceDidChangeNotification,
            // The display going to sleep and another user taking the Mac both leave the
            // game unattended, so the clock mustn't keep running behind them.
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.sessionDidResignActiveNotification
        ]
        workspaceObservers = closingNotifications.map { name in
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.close() }
            }
        }
        // Cmd-Tab and the like take the keyboard without a click. Left open, the panel
        // would float there with no keys reaching it.
        workspaceObservers.append(workspace.addObserver(
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
        })

        // Locking the screen doesn't always sleep the display.
        lockObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
        // A display coming or going, or the menu bar moving, leaves the panel hanging where
        // the icon used to be.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.followIcon() }
        }
    }

    /// Puts the open panel back under the icon after the screens change.
    private func followIcon() {
        guard isOpen else { return }
        panel.setFrameOrigin(panelOrigin(for: panel.frame.size))
        if !NSScreen.screens.contains(where: { $0.frame.contains(panel.frame) }) {
            close()
        }
    }

    func stopWatchingForDismissal() {
        clickMonitors.forEach(NSEvent.removeMonitor)
        clickMonitors = []
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        workspaceObservers = []
        if let lockObserver {
            DistributedNotificationCenter.default().removeObserver(lockObserver)
        }
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        lockObserver = nil
        screenObserver = nil
    }
}
