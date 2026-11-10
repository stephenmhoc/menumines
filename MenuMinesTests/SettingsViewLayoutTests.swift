import AppKit
import SwiftUI
import Testing
@testable import MenuMines

@Suite("Settings View Layout Tests")
struct SettingsViewLayoutTests {
    @Test("Settings view content stays within a reasonable window height")
    @MainActor
    func testSettingsViewStaysWithinMaxHeight() {
        // The window is sized from this measurement, since the form in it scrolls.
        let fittingSize = SettingsView.idealContentSize

        // A form that reports no height collapses the window to its title bar.
        #expect(fittingSize.height >= 200, "Settings reports only \(fittingSize.height)pt")

        // The direct build adds an Updates section this target cannot compile, so leave
        // headroom rather than tuning this to the exact App Store measurement.
        #expect(
            fittingSize.height <= SettingsView.Layout.maxHeight,
            "Settings needs \(fittingSize.height)pt, ceiling is \(SettingsView.Layout.maxHeight)pt"
        )
    }
}
