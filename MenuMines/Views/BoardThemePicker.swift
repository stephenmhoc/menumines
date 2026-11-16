import SwiftUI

/// Settings' theme choice: a card for each theme with a corner of a board drawn in it, so the
/// player sees what they're picking in their own appearance. The pick shows by its outline and
/// a checkmark, never by colour alone.
struct BoardThemePicker: View {
    @AppStorage(Constants.SettingsKeys.boardTheme) private var storedTheme = BoardTheme.defaultTheme.rawValue

    private static let spacing: CGFloat = 12

    var body: some View {
        let selected = BoardTheme(storedValue: storedTheme)
        // A plain grid, not a lazy one, so measuring the page for the window's height sees it.
        Grid(horizontalSpacing: Self.spacing, verticalSpacing: Self.spacing) {
            ForEach(Array(stride(from: 0, to: BoardTheme.allCases.count, by: 2)), id: \.self) { start in
                GridRow {
                    ForEach(BoardTheme.allCases[start..<min(start + 2, BoardTheme.allCases.count)]) { theme in
                        BoardThemeCard(theme: theme, isSelected: theme == selected) {
                            storedTheme = theme.rawValue
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "settings_section_board_theme"))
    }
}

private struct BoardThemeCard: View {
    let theme: BoardTheme
    let isSelected: Bool
    let onSelect: () -> Void

    private let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 8) {
                BoardThemePreview()
                    .environment(\.boardTheme, theme)
                    .accessibilityHidden(true)

                HStack(spacing: 4) {
                    Text(theme.title)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentColor)
                            .accessibilityHidden(true)
                    }
                }
                .font(.callout)
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(shape.fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear))
            .overlay(
                shape.strokeBorder(
                    isSelected ? Color.accentColor : Color.secondary.opacity(0.3),
                    lineWidth: isSelected ? 2 : 1
                )
            )
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(theme.title)
        .accessibilityHint(String(localized: "settings_board_theme_hint"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A corner of a game in progress: covered tiles, a flag and a few numbers.
private struct BoardThemePreview: View {
    private enum Tile: Hashable {
        case covered
        case flagged
        case open
        case number(Int)
    }

    private static let rows: [[Tile]] = [
        [.covered, .covered, .flagged, .covered, .covered],
        [.number(1), .number(2), .number(3), .number(2), .covered],
        [.open, .open, .number(1), .number(4), .covered]
    ]

    private static let cellSize: CGFloat = 24

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Self.rows.indices, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(Self.rows[row].indices, id: \.self) { col in
                        tile(Self.rows[row][col])
                            .frame(width: Self.cellSize, height: Self.cellSize)
                    }
                }
            }
        }
        .padding(GameBoardView.platePadding)
        .background(BoardPlate())
    }

    @ViewBuilder
    private func tile(_ tile: Tile) -> some View {
        BoardPaletteReader { palette in
            switch tile {
            case .covered:
                RaisedTile()
            case .flagged:
                ZStack {
                    RaisedTile()
                    FlagGlyph(size: 11, color: palette.flag)
                }
            case .open:
                RecessedTile()
            case .number(let count):
                ZStack {
                    RecessedTile()
                    Text(verbatim: String(count))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(palette.number(count))
                }
            }
        }
    }
}

#Preview {
    Form {
        BoardThemePicker()
    }
    .formStyle(.grouped)
    .frame(width: 420)
}
