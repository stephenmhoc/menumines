import AppKit
import Testing
@testable import MenuMines

/// Settings' pages: a toolbar tab each, the window titled and sized for the page that's up.
/// Part of the game panel suite, since it puts windows on screen.
extension GamePanelTests {
    @Test("Settings has a tab for each page and fits the window to the page that's up")
    func settingsPages() async throws {
        let cleanup = setupCleanPersistenceState(continuousPlay: true)
        let lastPage = SettingsTabController.lastPage
        defer {
            SettingsTabController.lastPage = lastPage
            cleanup()
        }
        SettingsTabController.lastPage = .general

        let window = try await openSettings()
        defer { window.close() }
        let tabs = try #require(window.contentViewController as? SettingsTabController)
        #expect(tabs.tabViewItems.compactMap { $0.identifier as? String } == SettingsPage.available.map(\.rawValue))
        #expect(tabs.selectedPage == .general)
        #expect(window.title == SettingsPage.general.title)
        #expect(window.toolbar != nil)

        for page in [SettingsPage.appearance, .game, .general] {
            tabs.selectedTabViewItemIndex = try #require(SettingsPage.available.firstIndex(of: page))
            try await settle()
            #expect(window.title == page.title)
            #expect(SettingsTabController.lastPage == page)
            let wanted = max(
                min(SettingsView.idealContentSize(for: page).height, AppWindows.screenLimitedContentHeight),
                SettingsView.Layout.minimumSize.height
            )
            let height = window.contentLayoutRect.height
            #expect(abs(height - wanted) <= 1, "\(page) is \(height)pt, wants \(wanted)pt")
        }
        try await handFocusBack()
    }

    @Test("Settings opens on the page it was last left on")
    func settingsReopensOnLastPage() async throws {
        let cleanup = setupCleanPersistenceState(continuousPlay: true)
        let lastPage = SettingsTabController.lastPage
        defer {
            SettingsTabController.lastPage = lastPage
            cleanup()
        }
        SettingsTabController.lastPage = .appearance

        let window = try await openSettings()
        defer { window.close() }
        let tabs = try #require(window.contentViewController as? SettingsTabController)
        #expect(tabs.selectedPage == .appearance)
        #expect(window.title == SettingsPage.appearance.title)
        try await handFocusBack()
    }
}
