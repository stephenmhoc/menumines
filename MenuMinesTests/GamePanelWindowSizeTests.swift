import AppKit
import Testing
@testable import MenuMines

/// Settings, Statistics and About open at a proper size, whatever their content reports and
/// whatever frame was saved for them. Part of the game panel suite, since these put windows
/// on screen.
extension GamePanelTests {
    /// Gives focus back as the app does once its last window closes, which hides it. Tests
    /// run without the app delegate that does that, and later panel tests expect the app
    /// not to be active.
    func handFocusBack() async throws {
        guard NSApp.isActive else { return }
        NSApp.hide(nil)
        try await settle()
        NSApp.unhideWithoutActivation()
        try await settle()
    }

    private static let savedFrameKeys = ["NSWindow Frame MenuMines.settings", "NSWindow Frame MenuMines.stats"]

    /// Runs `body` with the given frames saved for Settings and Statistics, then puts back
    /// whatever was saved before.
    private func withSavedFrames(_ frames: [String: String], _ body: () async throws -> Void) async rethrows {
        let saved = Self.savedFrameKeys.map { UserDefaults.standard.object(forKey: $0) }
        for (key, frame) in frames {
            UserDefaults.standard.set(frame, forKey: key)
        }
        defer {
            for (key, value) in zip(Self.savedFrameKeys, saved) {
                if let value {
                    UserDefaults.standard.set(value, forKey: key)
                } else {
                    UserDefaults.standard.removeObject(forKey: key)
                }
            }
        }
        try await body()
    }

    private func openedContentSize(_ open: () -> Void, titled title: String) async throws -> NSSize {
        open()
        try await settle()
        try await settle()
        let window = try #require(NSApp.windows.first { $0.isVisible && $0.title == title })
        defer { window.close() }
        return window.contentLayoutRect.size
    }

    private func checkWindowSizes() async throws {
        let settings = try await openedContentSize(AppWindows.showSettings, titled: AppWindows.settingsTitle)
        #expect(settings.width >= SettingsView.Layout.minimumSize.width)
        #expect(settings.height >= SettingsView.Layout.minimumSize.height, "Settings is \(settings.height)pt tall")
        // Every section shows, unless the screen is too short for them.
        let ideal = min(SettingsView.idealContentSize.height, AppWindows.screenLimitedContentHeight)
        #expect(settings.height >= ideal - 1, "Settings is \(settings.height)pt, wants \(ideal)pt")
        try await settle()

        let stats = try await openedContentSize(
            { AppWindows.showStats(gameState: todaysDaily()) },
            titled: String(localized: "stats_window_title")
        )
        #expect(stats.width >= AppWindows.statsMinimumContentSize.width)
        #expect(stats.height >= AppWindows.statsMinimumContentSize.height, "Statistics is \(stats.height)pt tall")
        try await settle()
        try await handFocusBack()
    }

    @Test("Settings and Statistics open at a proper size")
    func windowsOpenAtProperSize() async throws {
        let cleanup = setupCleanPersistenceState(continuousPlay: true)
        defer { cleanup() }
        try await withSavedFrames([:]) {
            for key in Self.savedFrameKeys {
                UserDefaults.standard.removeObject(forKey: key)
            }
            try await checkWindowSizes()
        }
    }

    @Test("A tiny frame saved for a window doesn't make it small")
    func savedTinyFrameIsIgnored() async throws {
        let cleanup = setupCleanPersistenceState(continuousPlay: true)
        defer { cleanup() }
        try await withSavedFrames([
            "NSWindow Frame MenuMines.settings": "112 233 420 21 0 0 1920 1050 ",
            "NSWindow Frame MenuMines.stats": "815 408 380 3 0 0 1920 1050 "
        ]) {
            try await checkWindowSizes()
        }
    }

    @Test("A window's size is what its content wants, floored at its minimum and capped by the screen")
    func contentSizeIsFloored() {
        let minimum = NSSize(width: 300, height: 200)
        #expect(AppWindows.contentSize(wanted: NSSize(width: 10, height: 3), minimum: minimum) == minimum)
        let roomy = NSSize(width: 400, height: 350)
        #expect(AppWindows.contentSize(wanted: roomy, minimum: minimum) == roomy)
        let tall = AppWindows.contentSize(wanted: NSSize(width: 400, height: 100_000), minimum: minimum)
        #expect(tall.height == AppWindows.screenLimitedContentHeight.rounded(.up))
    }
}
