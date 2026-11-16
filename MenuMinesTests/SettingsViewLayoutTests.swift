import AppKit
import SwiftUI
import Testing
@testable import MenuMines

@Suite("Settings View Layout Tests")
struct SettingsViewLayoutTests {
    @Test("Every Settings page stays within a reasonable window height")
    @MainActor
    func testSettingsPagesStayWithinMaxHeight() {
        for page in SettingsPage.available {
            // The window is sized from this measurement, since the form in it scrolls.
            let fittingSize = SettingsView.idealContentSize(for: page)

            // A form that reports no height collapses the window to its title bar.
            #expect(fittingSize.height >= 100, "\(page) reports only \(fittingSize.height)pt")

            // The direct build adds an Updates section this target cannot compile, so leave
            // headroom rather than tuning this to the exact App Store measurement.
            #expect(
                fittingSize.height <= SettingsView.Layout.maxHeight,
                "\(page) needs \(fittingSize.height)pt, ceiling is \(SettingsView.Layout.maxHeight)pt"
            )
        }
    }

    @Test("General, Game and Appearance are in every build, in that order")
    func testPagesInEveryBuild() {
        let available = SettingsPage.available
        #expect(Array(available.prefix(3)) == [.general, .game, .appearance])
    }

    @Test("Every page has a title and a symbol that exists")
    func testPageTitlesAndSymbols() {
        for page in SettingsPage.allCases {
            #expect(!page.title.hasPrefix("settings_page_"), "\(page) has no English title")
            #expect(NSImage(systemSymbolName: page.symbolName, accessibilityDescription: nil) != nil)
        }
    }
}
