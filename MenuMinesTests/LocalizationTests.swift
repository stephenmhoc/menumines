import Foundation
import Testing
@testable import MenuMines

/// The String Catalog resolves the keys the app builds from interpolations, and its plural
/// variations pick the right form. A key that's missing from the catalog comes back as the
/// key itself, so each of these would fail on a miss rather than show the key to the player.
@Suite("Localization")
struct LocalizationTests {
    @Test("A revealed number says mine or mines to match")
    func adjacentMinesPlural() {
        #expect(Cell(state: .revealed(adjacentMines: 1), hasMine: false).accessibilityStateDescription()
            == "1 adjacent mine")
        #expect(Cell(state: .revealed(adjacentMines: 3), hasMine: false).accessibilityStateDescription()
            == "3 adjacent mines")
    }

    @Test("The flag counter's label agrees with both numbers")
    func flagCountPlurals() {
        #expect(String(localized: "flag_count_accessibility \(1) \(11)") == "1 flag placed, 11 mines remaining")
        #expect(String(localized: "flag_count_accessibility \(11) \(1)") == "11 flags placed, 1 mine remaining")
        #expect(String(localized: "flag_count_accessibility \(0) \(12)") == "0 flags placed, 12 mines remaining")
    }

    @Test("Cells and selection announcements give the row and column first")
    func cellLabel() {
        let state = String(localized: "cell_state_covered")
        #expect(String(localized: "cell_accessibility_label \(2) \(5) \(state)") == "Row 2, Column 5, covered")
        #expect(String(localized: "announcement_selection_changed \(9) \(1) \(state)") == "Row 9, Column 1, covered")
    }

    @Test("Arguments land in their places")
    func positionalArguments() {
        #expect(String(localized: "build_info_version \("1.2") \("34")") == "Version 1.2 (34)")
        #expect(String(localized: "stats_recent_won_accessibility \("Nov 9, 2026") \("1 minute")")
            == "Nov 9, 2026, won in 1 minute")
    }

    @Test("The menu bar's streak comes through as a number")
    func menuBarStreak() {
        #expect(String(localized: "menu_bar_accessibility_complete \(4)")
            == "MenuMines, today's puzzle finished, current streak 4")
    }
}
