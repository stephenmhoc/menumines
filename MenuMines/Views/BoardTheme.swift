import AppKit
import SwiftUI

/// The look of the board: its tiles, plate, numbers, flag and mine. Only the board changes;
/// the panel around it keeps the system's material, so it still sits with the menu bar.
///
/// Every theme has a light and a dark version and heavier edges under Increase Contrast.
/// None of them relies on colour alone: every number is its digit and every mark its glyph.
enum BoardTheme: String, CaseIterable, Identifiable {
    case classic
    case retro
    case forest
    case midnight

    /// The theme a player who has never picked one gets, and what an unknown stored value
    /// (say, from a newer version) falls back to.
    static let defaultTheme = BoardTheme.classic

    var id: String { rawValue }

    /// The theme stored under `Constants.SettingsKeys.boardTheme`.
    init(storedValue: String?) {
        self = storedValue.flatMap(BoardTheme.init(rawValue:)) ?? Self.defaultTheme
    }

    var title: String {
        switch self {
        case .classic: String(localized: "theme_classic")
        case .retro: String(localized: "theme_retro")
        case .forest: String(localized: "theme_forest")
        case .midnight: String(localized: "theme_midnight")
        }
    }

    func palette(isDark: Bool, isIncreasedContrast: Bool) -> BoardPalette {
        switch self {
        case .classic: .classic(isDark: isDark, isIncreasedContrast: isIncreasedContrast)
        case .retro: .retro(isDark: isDark, isIncreasedContrast: isIncreasedContrast)
        case .forest: .forest(isDark: isDark, isIncreasedContrast: isIncreasedContrast)
        case .midnight: .midnight(isDark: isDark, isIncreasedContrast: isIncreasedContrast)
        }
    }
}

extension EnvironmentValues {
    /// The theme the board is drawn in. Set from the player's setting by the panel.
    @Entry var boardTheme: BoardTheme = .defaultTheme
}

/// Reads the theme, appearance and contrast from the environment and gives the palette for
/// them, so a tile or glyph needs only one line to follow all three.
struct BoardPaletteReader<Content: View>: View {
    @Environment(\.boardTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @ViewBuilder let content: (BoardPalette) -> Content

    var body: some View {
        content(theme.palette(isDark: colorScheme == .dark, isIncreasedContrast: contrast == .increased))
    }
}

/// The colours and shapes one theme draws the board with, for one appearance.
struct BoardPalette {
    // Covered tiles
    var coveredTop: Color
    var coveredBottom: Color
    var coveredHoverTop: Color
    var coveredHoverBottom: Color
    /// The light along a covered tile's top edge, which is what reads as "raised".
    var coveredHighlight: Color
    var coveredEdge: Color
    var coveredEdgeWidth: CGFloat
    var coveredShadow: Color
    var coveredCornerRadius: CGFloat

    // Opened tiles
    var revealedFill: Color
    /// Drawn round opened tiles under Increase Contrast only.
    var revealedOutline: Color
    var revealedCornerRadius: CGFloat
    var explodedFill: Color

    // The plate the tiles sit on
    var plateFill: Color
    /// Laid over the fill, for a shade that follows the system's window colour.
    var plateShade: Color
    var plateEdge: Color
    var plateCornerRadius: CGFloat

    // Glyphs
    /// The colours for one to eight adjacent mines.
    var numbers: [Color]
    var flag: Color
    var wrongFlag: Color
    var mine: Color

    /// The colour for a count of adjacent mines. Anything past eight takes eight's.
    func number(_ adjacentMines: Int) -> Color {
        numbers[min(max(adjacentMines, 1), numbers.count) - 1]
    }
}

// MARK: - Themes

private extension Color {
    init(_ red: Double, _ green: Double, _ blue: Double) {
        self.init(red: red, green: green, blue: blue)
    }
}

extension BoardPalette {
    /// The system's own look: grey tiles and system colours, which adapt to light, dark and
    /// Increase Contrast by themselves. The original classic order (blue, green, red, navy,
    /// maroon, teal, black, grey), with purple standing in for navy, which is too close to
    /// blue in dark mode.
    static func classic(isDark: Bool, isIncreasedContrast: Bool) -> BoardPalette {
        let edge: Color = isIncreasedContrast
            ? (isDark ? .white.opacity(0.6) : .black.opacity(0.55))
            : (isDark ? .black.opacity(0.45) : .black.opacity(0.2))
        // Light mode opens cells up lighter than the board, the way paper shows through;
        // dark mode sets them into it. Either way they're the opposite of the raised tiles.
        let revealed: Color = isIncreasedContrast
            ? (isDark ? .black.opacity(0.55) : .white)
            : (isDark ? .black.opacity(0.28) : .white.opacity(0.75))
        return BoardPalette(
            coveredTop: Color(white: isDark ? 0.42 : 0.85),
            coveredBottom: Color(white: isDark ? 0.35 : 0.78),
            coveredHoverTop: Color(white: isDark ? 0.47 : 0.88),
            coveredHoverBottom: Color(white: isDark ? 0.40 : 0.81),
            coveredHighlight: .white.opacity(isDark ? 0.28 : 0.75),
            coveredEdge: edge,
            coveredEdgeWidth: isIncreasedContrast ? 1 : 0.5,
            coveredShadow: .black.opacity(isDark ? 0.35 : 0.14),
            coveredCornerRadius: CellMetrics.raisedCornerRadius,
            revealedFill: revealed,
            revealedOutline: Color.primary.opacity(0.35),
            revealedCornerRadius: CellMetrics.revealedCornerRadius,
            explodedFill: Color(nsColor: .systemRed),
            plateFill: Color(nsColor: .windowBackgroundColor),
            // A shade darker in light mode, so the lines between opened cells show.
            plateShade: .black.opacity(isDark ? 0 : 0.06),
            plateEdge: Color.primary.opacity(isDark ? 0.12 : 0.08),
            plateCornerRadius: 7,
            numbers: [
                Color(nsColor: .systemBlue),
                Color(nsColor: .systemGreen),
                Color(nsColor: .systemRed),
                Color(nsColor: .systemPurple),
                Color(nsColor: .systemBrown),
                Color(nsColor: .systemTeal),
                Color(nsColor: .labelColor),
                Color(nsColor: .secondaryLabelColor)
            ],
            flag: Color(nsColor: .systemRed),
            wrongFlag: Color(nsColor: .secondaryLabelColor),
            mine: Color.primary
        )
    }

    /// An old desktop: square, flat grey tiles with a hard bevel, and saturated numbers.
    static func retro(isDark: Bool, isIncreasedContrast: Bool) -> BoardPalette {
        let covered = isDark ? 0.36 : 0.76
        let hover = isDark ? 0.41 : 0.80
        let numbers: [Color] = isDark ? [
            Color(0.40, 0.60, 1.00),
            Color(0.30, 0.82, 0.30),
            Color(1.00, 0.36, 0.33),
            Color(0.62, 0.55, 1.00),
            Color(0.95, 0.55, 0.45),
            Color(0.20, 0.82, 0.82),
            Color(white: 0.92),
            Color(white: 0.62)
        ] : [
            Color(0.00, 0.00, 0.95),
            Color(0.00, 0.48, 0.00),
            Color(0.85, 0.00, 0.00),
            Color(0.00, 0.00, 0.50),
            Color(0.50, 0.00, 0.00),
            Color(0.00, 0.50, 0.50),
            Color(white: 0.0),
            Color(white: 0.45)
        ]
        return BoardPalette(
            coveredTop: Color(white: covered),
            coveredBottom: Color(white: covered),
            coveredHoverTop: Color(white: hover),
            coveredHoverBottom: Color(white: hover),
            coveredHighlight: .white.opacity(isDark ? 0.45 : 0.95),
            coveredEdge: isIncreasedContrast
                ? (isDark ? .white.opacity(0.7) : .black.opacity(0.75))
                : .black.opacity(isDark ? 0.6 : 0.45),
            coveredEdgeWidth: isIncreasedContrast ? 1.5 : 1,
            coveredShadow: .black.opacity(isDark ? 0.4 : 0.25),
            coveredCornerRadius: 1.5,
            revealedFill: Color(white: isDark ? 0.20 : 0.86),
            revealedOutline: isDark ? .white.opacity(0.4) : .black.opacity(0.45),
            revealedCornerRadius: 0.5,
            explodedFill: Color(0.90, 0.10, 0.10),
            plateFill: Color(white: isDark ? 0.12 : 0.55),
            plateShade: .clear,
            plateEdge: .black.opacity(isDark ? 0.6 : 0.35),
            plateCornerRadius: 3,
            numbers: numbers,
            flag: Color(0.88, 0.05, 0.05),
            wrongFlag: Color(white: isDark ? 0.62 : 0.40),
            mine: isDark ? Color(white: 0.95) : .black
        )
    }

    /// Mossy tiles over warm earth.
    static func forest(isDark: Bool, isIncreasedContrast: Bool) -> BoardPalette {
        let numbers: [Color] = isDark ? [
            Color(0.48, 0.72, 1.00),
            Color(0.58, 0.88, 0.46),
            Color(1.00, 0.52, 0.42),
            Color(0.82, 0.62, 1.00),
            Color(0.94, 0.70, 0.40),
            Color(0.40, 0.86, 0.84),
            Color(0.94, 0.91, 0.86),
            Color(0.66, 0.62, 0.56)
        ] : [
            Color(0.08, 0.32, 0.70),
            Color(0.15, 0.48, 0.12),
            Color(0.76, 0.16, 0.12),
            Color(0.44, 0.18, 0.56),
            Color(0.56, 0.30, 0.08),
            Color(0.02, 0.44, 0.44),
            Color(0.16, 0.12, 0.08),
            Color(0.44, 0.40, 0.34)
        ]
        let revealed: Color = isDark ? Color(0.17, 0.14, 0.11) : Color(0.95, 0.91, 0.82)
        return BoardPalette(
            coveredTop: isDark ? Color(0.29, 0.43, 0.25) : Color(0.56, 0.71, 0.45),
            coveredBottom: isDark ? Color(0.22, 0.34, 0.19) : Color(0.46, 0.62, 0.36),
            coveredHoverTop: isDark ? Color(0.34, 0.49, 0.30) : Color(0.61, 0.76, 0.50),
            coveredHoverBottom: isDark ? Color(0.27, 0.40, 0.23) : Color(0.51, 0.67, 0.41),
            coveredHighlight: Color(0.92, 1.00, 0.85).opacity(isDark ? 0.25 : 0.6),
            coveredEdge: isIncreasedContrast
                ? (isDark ? Color(0.85, 0.95, 0.80).opacity(0.7) : Color(0.08, 0.18, 0.06).opacity(0.8))
                : Color(0.08, 0.18, 0.06).opacity(isDark ? 0.6 : 0.35),
            coveredEdgeWidth: isIncreasedContrast ? 1 : 0.5,
            coveredShadow: .black.opacity(isDark ? 0.4 : 0.18),
            coveredCornerRadius: CellMetrics.raisedCornerRadius,
            revealedFill: revealed,
            revealedOutline: isDark ? Color(0.85, 0.78, 0.66).opacity(0.45) : Color(0.30, 0.22, 0.12).opacity(0.45),
            revealedCornerRadius: CellMetrics.revealedCornerRadius,
            explodedFill: Color(0.80, 0.22, 0.14),
            plateFill: isDark ? Color(0.10, 0.08, 0.06) : Color(0.74, 0.66, 0.52),
            plateShade: .clear,
            plateEdge: Color(0.20, 0.14, 0.08).opacity(isDark ? 0.5 : 0.3),
            plateCornerRadius: 7,
            numbers: numbers,
            flag: Color(nsColor: .systemRed),
            wrongFlag: isDark ? Color(0.70, 0.66, 0.60) : Color(0.42, 0.38, 0.32),
            mine: isDark ? Color(0.94, 0.91, 0.86) : Color(0.16, 0.12, 0.08)
        )
    }

    /// Dark tiles and neon numbers, in either appearance.
    static func midnight(isDark: Bool, isIncreasedContrast: Bool) -> BoardPalette {
        BoardPalette(
            coveredTop: isDark ? Color(0.17, 0.18, 0.26) : Color(0.22, 0.24, 0.33),
            coveredBottom: isDark ? Color(0.12, 0.13, 0.20) : Color(0.16, 0.17, 0.25),
            coveredHoverTop: isDark ? Color(0.22, 0.23, 0.32) : Color(0.27, 0.29, 0.39),
            coveredHoverBottom: isDark ? Color(0.16, 0.17, 0.25) : Color(0.20, 0.21, 0.30),
            coveredHighlight: Color(0.70, 0.80, 1.00).opacity(0.3),
            coveredEdge: isIncreasedContrast ? Color(0.70, 0.85, 1.00).opacity(0.75) : .black.opacity(0.6),
            coveredEdgeWidth: isIncreasedContrast ? 1 : 0.5,
            coveredShadow: .black.opacity(0.45),
            coveredCornerRadius: CellMetrics.raisedCornerRadius,
            revealedFill: isDark ? Color(0.03, 0.03, 0.06) : Color(0.06, 0.07, 0.11),
            revealedOutline: Color(0.70, 0.85, 1.00).opacity(0.45),
            revealedCornerRadius: CellMetrics.revealedCornerRadius,
            explodedFill: Color(1.00, 0.22, 0.45),
            plateFill: isDark ? Color(0.06, 0.06, 0.10) : Color(0.10, 0.11, 0.16),
            plateShade: .clear,
            plateEdge: Color(0.55, 0.65, 1.00).opacity(0.25),
            plateCornerRadius: 7,
            numbers: [
                Color(0.30, 0.85, 1.00),
                Color(0.55, 1.00, 0.45),
                Color(1.00, 0.38, 0.62),
                Color(0.76, 0.56, 1.00),
                Color(1.00, 0.66, 0.26),
                Color(0.30, 1.00, 0.82),
                Color(white: 0.95),
                Color(white: 0.62)
            ],
            flag: Color(1.00, 0.30, 0.45),
            wrongFlag: Color(white: 0.62),
            mine: Color(white: 0.95)
        )
    }
}
