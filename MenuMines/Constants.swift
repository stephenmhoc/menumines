import Foundation

/// Application-wide constants and configuration keys.
enum Constants {
    /// UserDefaults keys for application settings.
    enum SettingsKeys {
        /// Controls whether the menu bar icon shows dynamic status indicators.
        /// When false, the icon remains in the normal state regardless of game status.
        static let showMenuBarIndicators = "com.menumines.showMenuBarIndicators"

        /// Controls whether a confirmation dialog appears before resetting the game.
        /// When false (default), reset happens immediately.
        static let confirmBeforeReset = "com.menumines.confirmBeforeReset"

        /// Controls whether streaks are displayed in the Stats window.
        /// When false, streak data is still collected but hidden in the UI.
        static let showStreaks = "com.menumines.showStreaks"

        /// Controls whether continuous play mode is enabled.
        /// When true (default), after completing the daily puzzle, users can continue
        /// playing unlimited random puzzles. Only the daily puzzle counts toward streaks.
        static let continuousPlay = "com.menumines.continuousPlay"

        /// Whether crash and failure reports are sent. On unless the player turns it off.
        static let sendCrashReports = "com.menumines.sendCrashReports"
    }
}
