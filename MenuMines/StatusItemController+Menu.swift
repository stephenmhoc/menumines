import AppKit

/// The menu a right-click or Control-click on the icon opens.
extension StatusItemController {
    /// Whether a press on the icon asks for the menu rather than the game. Only a real
    /// right-click or Control-click does: VoiceOver's press (Control-Option-Space) and other
    /// keyboard presses hold Control too, and they're asking for the game.
    static func isMenuRequest(_ event: NSEvent?) -> Bool {
        guard let event else { return false }
        switch event.type {
        case .rightMouseDown:
            return true
        case .leftMouseDown:
            return event.modifierFlags.contains(.control)
        default:
            return false
        }
    }

    /// The right-click menu. It carries the gear menu's app-wide items, in the same order
    /// and wording (`FooterView`), so keep the two together. Reset and Back to Today stay in
    /// the gear menu, since they act on the board in front of the player.
    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(item("daily_history_menu_item", #selector(showDailyHistory)))
        menu.addItem(item("stats_menu_item", #selector(showStats)))
        menu.addItem(item("settings_menu_item", #selector(showSettings), key: ","))

        #if SPARKLE_ENABLED
        menu.addItem(.separator())
        let updates = item(
            UpdateManager.isUpdatePending ? "update_available_menu_item" : "check_for_updates_menu_item",
            #selector(checkForUpdates)
        )
        updates.isEnabled = UpdateManager.canCheckForUpdates
        menu.addItem(updates)
        #endif

        menu.addItem(.separator())
        menu.addItem(item("about_menu_item", #selector(showAbout)))
        menu.addItem(item("quit_menu_item", #selector(quit), key: "q"))
        return menu
    }

    func showMenu() {
        // Focus goes back once the menu is done with, not while it's tracking.
        close(returningFocus: false)
        defer { returnFocusIfTaken() }

        // Attached only for this click, because an attached menu replaces the left click.
        statusItem.menu = makeMenu()
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func item(_ key: String.LocalizationValue, _ action: Selector, key equivalent: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: String(localized: key), action: action, keyEquivalent: equivalent)
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

    #if SPARKLE_ENABLED
    @objc private func checkForUpdates() {
        UpdateManager.checkForUpdates()
    }
    #endif

    @objc private func showAbout() {
        AboutWindow.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
