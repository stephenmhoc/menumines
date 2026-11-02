import AppKit
import SwiftUI
import Testing
@testable import MenuMines

@Suite("Settings View Layout Tests")
struct SettingsViewLayoutTests {
    @Test("Settings view content stays within a reasonable window height")
    @MainActor
    func testSettingsViewStaysWithinMaxHeight() {
        let hostingView = NSHostingView(rootView: SettingsView())
        hostingView.frame = NSRect(x: 0, y: 0, width: SettingsView.Layout.width, height: 1000)
        hostingView.layoutSubtreeIfNeeded()
        let fittingSize = hostingView.fittingSize

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
