import SwiftUI
import Testing
@testable import MenuMines

@Suite("Board Theme Tests")
struct BoardThemeTests {
    private static let appearances = [(false, false), (true, false), (false, true), (true, true)]

    @Test("A missing or unknown stored theme is Classic")
    func testStoredValueFallsBackToClassic() {
        #expect(BoardTheme(storedValue: nil) == .classic)
        #expect(BoardTheme(storedValue: "neon-from-the-future") == .classic)
        for theme in BoardTheme.allCases {
            #expect(BoardTheme(storedValue: theme.rawValue) == theme)
        }
    }

    @Test("Stored names don't change, since they're in players' settings")
    func testRawValuesAreStable() {
        #expect(BoardTheme.allCases.map(\.rawValue) == ["classic", "retro", "forest", "midnight"])
        #expect(Constants.SettingsKeys.boardTheme == "com.menumines.boardTheme")
    }

    @Test("Every theme has eight different number colours in every appearance")
    func testNumberColoursAreDistinct() {
        for theme in BoardTheme.allCases {
            for (isDark, isIncreased) in Self.appearances {
                let palette = theme.palette(isDark: isDark, isIncreasedContrast: isIncreased)
                #expect(palette.numbers.count == 8, "\(theme)")
                #expect(Set(palette.numbers).count == 8, "\(theme) repeats a number colour")
                #expect(palette.revealedFill != palette.coveredTop, "\(theme): opened and covered tiles match")
            }
        }
    }

    @Test("Counts outside one to eight take the nearest colour")
    func testNumberLookupIsClamped() {
        let palette = BoardTheme.classic.palette(isDark: false, isIncreasedContrast: false)
        #expect(palette.number(0) == palette.numbers[0])
        #expect(palette.number(9) == palette.numbers[7])
        #expect(palette.number(3) == palette.numbers[2])
    }

    @Test("Every theme has an English name")
    func testThemeTitles() {
        let titles = BoardTheme.allCases.map(\.title)
        #expect(titles == ["Classic", "Retro", "Forest", "Midnight"])
    }
}
