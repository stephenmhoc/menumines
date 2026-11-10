import AppKit
import SwiftUI

@main
struct MenuMinesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var gameState: GameState

    #if DEBUG
    private static var isScreenshotExportMode: Bool {
        ProcessInfo.processInfo.environment["MENUMINES_EXPORT_APP_STORE_SCREENSHOTS"] == "1"
    }
    #endif

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Constants.SettingsKeys.continuousPlay: true
        ])
    }

    init() {
        Telemetry.start()
        Self.registerDefaults()

        #if DEBUG
        let state = Self.isScreenshotExportMode
            ? GameState(board: Board(seed: AppStoreScreenshotVariant.seed), puzzleType: .random)
            : GameState.restored()
        #else
        let state = GameState.restored()
        #endif

        _gameState = State(initialValue: state)

        #if DEBUG
        if Self.isScreenshotExportMode {
            Task { @MainActor in
                do {
                    try AppStoreScreenshotExporter.exportAll()
                    NSApplication.shared.terminate(nil)
                } catch {
                    fputs("Failed to export App Store screenshots: \(error)\n", stderr)
                    exit(1)
                }
            }
            return
        }
        #endif

        // Hosted tests launch this app, and must not sign in or start syncing.
        guard !Self.isRunningTests else { return }
        AppDelegate.gameState = state
    }

    // Every window is built by AppWindows and StatusItemController. An app has to declare a
    // scene, so this is one that never opens. Its menu commands are pointed at the app's own
    // windows instead, so that ⌘, opens Settings and About shows ours while a window is in
    // front, and ⌘W closes it.
    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(String(localized: "about_menu_item")) {
                    AboutWindow.show()
                }
            }
            CommandGroup(replacing: .appSettings) {
                Button(String(localized: "settings_menu_item")) {
                    AppWindows.showSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(replacing: .saveItem) {
                Button(String(localized: "close_window_menu_item")) {
                    NSApp.keyWindow?.performClose(nil)
                }
                .keyboardShortcut("w", modifiers: .command)
            }
        }
    }
}

/// Owns everything that has to outlive the popover, and starts it once the app is up.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set before launch finishes. Nil when there's nothing to run, as under test.
    @MainActor static var gameState: GameState?

    private var dayWatcher: DayWatcher?
    private var statusItemController: StatusItemController?
    private var windowObserver: NSObjectProtocol?

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let gameState = Self.gameState else { return }

        StatsSync.onResultsChanged = { [weak gameState] in gameState?.adoptSyncedCompletion() }
        StatsSync.start()
        Leaderboard.authenticate()
        UpdateManager.start()

        let dayWatcher = DayWatcher { [weak gameState] in gameState?.dayMayHaveChanged() }
        dayWatcher.start()
        self.dayWatcher = dayWatcher

        let statusItemController = StatusItemController(gameState: gameState)
        self.statusItemController = statusItemController

        GlobalHotKey.onPress = { [weak statusItemController] in statusItemController?.toggle() }
        GlobalHotKey.start()

        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { notification in
            let window = notification.object as? NSWindow
            MainActor.assumeIsolated {
                if let window {
                    AppWindows.windowWillClose(window)
                }
            }
        }
    }

    /// Launching the app again, from Finder or Spotlight, opens the game. With no Dock icon,
    /// that's the only answer it could be looking for, and it's the way back to the game
    /// for a player whose menu bar has no room for the icon.
    @MainActor
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusItemController?.openForReopen()
        return false
    }

    @MainActor
    func applicationWillTerminate(_ notification: Notification) {
        Self.gameState?.pauseTimer()
        Self.gameState?.save()
    }
}
