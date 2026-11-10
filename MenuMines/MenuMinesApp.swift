import AppKit
import Combine
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
    // scene, so this is one that never opens, with its menu command removed so that ⌘, can't
    // open it from the app menu.
    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {}
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

        statusItemController = StatusItemController(gameState: gameState)

        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { AppWindows.yieldFocusIfNoWindowsRemain() }
        }
    }

    @MainActor
    func applicationWillTerminate(_ notification: Notification) {
        Self.gameState?.pauseTimer()
        Self.gameState?.save()
    }
}

/// Menu bar icon view showing state-specific icon with subtle indicators.
struct MenuBarIconView: View {
    let gameState: GameState
    /// Passes the description on to the status item's button, which is what VoiceOver reads.
    var onAccessibilityLabelChange: (String) -> Void = { _ in }

    @AppStorage(Constants.SettingsKeys.showMenuBarIndicators) private var showMenuBarIndicators = true
    @AppStorage(Constants.SettingsKeys.showMenuBarResult) private var showMenuBarResult = true
    @State private var isVoiceOverRunning = NSWorkspace.shared.isVoiceOverEnabled

    private var state: MenuBarIconState {
        guard showMenuBarIndicators else {
            return .normal
        }
        return menuBarIconState(
            gameStatus: gameState.status,
            isPaused: gameState.isPaused,
            isDailyComplete: isDailyPuzzleComplete(forSeed: gameState.currentDaySeed),
            puzzleType: gameState.puzzleType
        )
    }

    /// The elapsed time is only read while VoiceOver is running. Reading it unconditionally
    /// would rebuild the status item every second for a label nothing is listening to, and
    /// re-laying out the status item makes the attached popover jump.
    private var announcedElapsedTime: TimeInterval {
        isVoiceOverRunning ? gameState.elapsedTime : 0
    }

    private var baseIconName: String {
        state.baseSymbol(showingResult: showMenuBarResult)
    }

    private var overlayName: String? {
        state.overlaySymbol(showingResult: showMenuBarResult)
    }

    private var accessibilityLabel: String {
        switch state {
        case .normal:
            return String(localized: "menu_bar_title")
        case .incomplete:
            return String(localized: "menu_bar_accessibility_incomplete")
        case .playing:
            return String(format: String(localized: "menu_bar_accessibility_playing"), announcedElapsedTime.clockString)
        case .paused:
            return String(format: String(localized: "menu_bar_accessibility_paused"), announcedElapsedTime.clockString)
        case .complete:
            return String(format: String(localized: "menu_bar_accessibility_complete"), StatsStore.shared.currentStreak)
        case .lost:
            return String(localized: "menu_bar_accessibility_lost")
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: baseIconName)

                if let overlayName {
                    Image(systemName: overlayName)
                        .font(.system(size: 7, weight: .bold))
                        .symbolRenderingMode(.hierarchical)
                        .offset(x: 5, y: 4)
                }
            }
        }
        .accessibilityHidden(true)
        .frame(width: 22, alignment: .center)
        .onChange(of: accessibilityLabel, initial: true) {
            onAccessibilityLabelChange(accessibilityLabel)
        }
        .onReceive(NSWorkspace.shared.publisher(for: \.isVoiceOverEnabled)) { isEnabled in
            isVoiceOverRunning = isEnabled
        }
    }
}
