import AppKit
import SwiftUI

struct CellView: View {
    let cell: Cell
    let row: Int
    let col: Int
    let gameStatus: GameStatus
    let isSelected: Bool
    let isChordReady: Bool
    let isFlagMode: Bool
    let onReveal: () -> Void
    let onFlag: () -> Void
    var onHover: (Bool) -> Void = { _ in }
    var onHoldChanged: (Bool) -> Void = { _ in }
    var onAccessibilityFocus: () -> Void = {}

    @State private var isHovered = false
    @State private var isPressed = false
    @AccessibilityFocusState private var isAccessibilityFocused
    @Environment(\.colorScheme) private var colorScheme

    private static let cellSize: CGFloat = 28

    var body: some View {
        ZStack {
            background
            hoverOverlay
            chordReadyOverlay
            content
        }
        .frame(width: Self.cellSize, height: Self.cellSize)
        .scaleEffect(isPressed && !isRevealed ? 0.96 : 1)
        .overlay(selectionBorder)
        .overlay(
            ClickHandlerView(
                onLeftClick: onReveal,
                onRightClick: onFlag,
                onPressedChanged: { pressed in
                    isPressed = pressed
                    if isPlayable {
                        onHoldChanged(pressed)
                    }
                }
            )
        )
        .onHover { hovering in
            isHovered = hovering
            onHover(hovering)
        }
        // Declarative animations only. Wrapping these state changes in `withAnimation`
        // opens a global transaction, so the reveal cascade the same click triggers across
        // the other 80 cells gets animated too, which reads as the board wobbling.
        .animation(.easeOut(duration: 0.08), value: isPressed)
        .animation(.easeOut(duration: 0.08), value: isHovered)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(accessibilityTraits)
        .accessibilityRespondsToUserInteraction(isPlayable)
        .accessibilityAction { onReveal() }
        .accessibilityAction(named: String(localized: "cell_action_flag")) { onFlag() }
        .accessibilityFocused($isAccessibilityFocused)
        .onChange(of: isAccessibilityFocused) { _, focused in
            if focused {
                onAccessibilityFocus()
            }
        }
    }

    private var isPlayable: Bool {
        gameStatus == .notStarted || gameStatus == .playing
    }

    // MARK: - Accessibility

    private var accessibilityLabel: String {
        let state: String

        if cell.isExploded {
            state = String(localized: "cell_state_exploded_mine")
            return String(format: String(localized: "cell_accessibility_label"), row + 1, col + 1, state)
        }

        switch cell.state {
        case .hidden:
            state = String(localized: "cell_state_covered")
        case .flagged:
            state = String(localized: "cell_state_flagged")
        case .revealed(let adjacentMines):
            if cell.hasMine {
                state = String(localized: "cell_state_mine")
            } else if adjacentMines == 0 {
                state = String(localized: "cell_state_empty")
            } else if adjacentMines == 1 {
                state = String(localized: "cell_state_one_mine")
            } else {
                state = String(format: String(localized: "cell_state_mines"), adjacentMines)
            }
        }

        return String(format: String(localized: "cell_accessibility_label"), row + 1, col + 1, state)
    }

    private var accessibilityHint: String {
        guard isPlayable else {
            return ""
        }

        switch cell.state {
        case .hidden:
            if isFlagMode {
                return String(localized: "cell_hint_flag_mode")
            }
            return String(localized: "cell_hint_reveal_or_flag")
        case .flagged:
            return String(localized: "cell_hint_remove_flag")
        case .revealed(let adjacentMines) where isChordReady && adjacentMines > 0:
            return String(localized: "cell_hint_chord_ready")
        case .revealed:
            return ""
        }
    }

    private var accessibilityTraits: AccessibilityTraits {
        switch cell.state {
        case .hidden, .flagged:
            return .isButton
        case .revealed:
            return .isStaticText
        }
    }

    // MARK: - Background

    @ViewBuilder
    private var background: some View {
        if cell.isExploded {
            Color.red
        } else if case .revealed = cell.state {
            revealedBackground
        } else {
            RaisedCellBackground(colorScheme: colorScheme)
        }
    }

    private var revealedBackground: Color {
        if colorScheme == .dark {
            Color(nsColor: .controlBackgroundColor)
        } else {
            Color(nsColor: .controlBackgroundColor).opacity(0.6)
        }
    }

    // MARK: - Hover

    private var isRevealed: Bool {
        if case .revealed = cell.state { return true }
        return false
    }

    @ViewBuilder
    private var hoverOverlay: some View {
        if isHovered && !isRevealed && !cell.isExploded {
            if colorScheme == .dark {
                Color.white.opacity(0.15)
            } else {
                Color.black.opacity(0.1)
            }
        }
    }

    @ViewBuilder
    private var chordReadyOverlay: some View {
        if isHovered && isChordReady && isRevealed {
            RoundedRectangle(cornerRadius: 2)
                .stroke(Color.accentColor.opacity(0.75), lineWidth: 2)
                .padding(2)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if cell.isExploded {
            mineIcon
        } else {
            switch cell.state {
            case .hidden:
                EmptyView()
            case .flagged:
                Text("🚩")
                    .font(.system(size: 14))
            case .revealed(let adjacentMines):
                if cell.hasMine {
                    mineIcon
                } else if adjacentMines > 0 {
                    Text("\(adjacentMines)")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundStyle(color(for: adjacentMines))
                }
            }
        }
    }

    private var mineIcon: some View {
        Text("💣")
            .font(.system(size: 14))
    }

    // MARK: - Selection Border

    @ViewBuilder
    private var selectionBorder: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 2)
                .stroke(Color.accentColor, lineWidth: 2)
        }
    }

    // MARK: - Number Colors
    // Classic Minesweeper palette with adaptive colors for light/dark mode.
    // Dark mode uses brighter variants for readability on dark backgrounds.

    private func color(for adjacentMines: Int) -> Color {
        let isDark = colorScheme == .dark

        switch adjacentMines {
        case 1: // Blue
            return isDark
                ? Color(red: 0.4, green: 0.6, blue: 1.0)
                : Color(red: 0.0, green: 0.0, blue: 1.0)
        case 2: // Green
            return isDark
                ? Color(red: 0.4, green: 0.85, blue: 0.4)
                : Color(red: 0.0, green: 0.5, blue: 0.0)
        case 3: // Red
            return isDark
                ? Color(red: 1.0, green: 0.4, blue: 0.4)
                : Color(red: 0.8, green: 0.0, blue: 0.0)
        case 4: // Navy
            return isDark
                ? Color(red: 0.5, green: 0.5, blue: 1.0)
                : Color(red: 0.0, green: 0.0, blue: 0.55)
        case 5: // Brown
            return isDark
                ? Color(red: 0.9, green: 0.6, blue: 0.3)
                : Color(red: 0.55, green: 0.27, blue: 0.07)
        case 6: // Teal
            return isDark
                ? Color(red: 0.4, green: 0.9, blue: 0.9)
                : Color(red: 0.0, green: 0.55, blue: 0.55)
        case 7: // Gray (dark in light mode, light in dark mode)
            return isDark
                ? Color(red: 0.75, green: 0.75, blue: 0.75)
                : Color(red: 0.2, green: 0.2, blue: 0.2)
        case 8: // Gray (medium in light mode, lighter in dark mode)
            return isDark
                ? Color(red: 0.85, green: 0.85, blue: 0.85)
                : Color(red: 0.5, green: 0.5, blue: 0.5)
        default:
            return .primary
        }
    }
}

// MARK: - Click Handler

private struct ClickHandlerView: NSViewRepresentable {
    let onLeftClick: () -> Void
    let onRightClick: () -> Void
    let onPressedChanged: (Bool) -> Void

    func makeNSView(context: Context) -> ClickableNSView {
        let view = ClickableNSView()
        view.onLeftClick = onLeftClick
        view.onRightClick = onRightClick
        view.onPressedChanged = onPressedChanged
        return view
    }

    func updateNSView(_ nsView: ClickableNSView, context: Context) {
        nsView.onLeftClick = onLeftClick
        nsView.onRightClick = onRightClick
        nsView.onPressedChanged = onPressedChanged
    }
}

/// Handles clicks the way a Mac button does: a left click acts on release, so a player who
/// changes their mind can drag off the cell and let go. A secondary click flags on the way
/// down, because a flag is safe and these need to be quick.
private class ClickableNSView: NSView {
    var onLeftClick: (() -> Void)?
    var onRightClick: (() -> Void)?
    var onPressedChanged: ((Bool) -> Void)?

    /// Decided on the way down. Letting go of Control before the mouse must not turn a
    /// control-click into a reveal, which could lose the game.
    private var isPrimaryPress = false

    override func mouseDown(with event: NSEvent) {
        // Control+Click is the macOS convention for secondary click
        isPrimaryPress = !event.modifierFlags.contains(.control)
        if isPrimaryPress {
            onPressedChanged?(true)
        } else {
            flag()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard isPrimaryPress else { return }
        onPressedChanged?(contains(event))
    }

    override func mouseUp(with event: NSEvent) {
        guard isPrimaryPress else { return }
        isPrimaryPress = false
        onPressedChanged?(false)
        if contains(event) {
            onLeftClick?()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        flag()
    }

    private func flag() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        onRightClick?()
    }

    private func contains(_ event: NSEvent) -> Bool {
        bounds.contains(convert(event.locationInWindow, from: nil))
    }
}

// MARK: - Raised Cell Background

/// The classic bevel that makes a covered cell look raised.
///
/// Drawn with `Shape`s rather than a `GeometryReader`: a shape receives its rect during
/// drawing, while a reader forces a second layout pass. With 81 cells rebuilt on every
/// reveal, those extra passes were a measurable share of the work done per click.
private struct RaisedCellBackground: View {
    let colorScheme: ColorScheme
    private let bevelWidth: CGFloat = 3

    var body: some View {
        ZStack {
            Color(nsColor: .controlColor)

            CellBevel(edge: .topLeading, width: bevelWidth)
                .fill(Color.white.opacity(colorScheme == .dark ? 0.3 : 0.5))

            CellBevel(edge: .bottomTrailing, width: bevelWidth)
                .fill(Color.black.opacity(colorScheme == .dark ? 0.5 : 0.3))
        }
    }
}

private struct CellBevel: Shape {
    enum Edge {
        case topLeading
        case bottomTrailing
    }

    let edge: Edge
    let width: CGFloat

    func path(in rect: CGRect) -> Path {
        Path { path in
            switch edge {
            case .topLeading:
                path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX - width, y: rect.minY + width))
                path.addLine(to: CGPoint(x: rect.minX + width, y: rect.minY + width))
                path.addLine(to: CGPoint(x: rect.minX + width, y: rect.maxY - width))
            case .bottomTrailing:
                path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.minX + width, y: rect.maxY - width))
                path.addLine(to: CGPoint(x: rect.maxX - width, y: rect.maxY - width))
                path.addLine(to: CGPoint(x: rect.maxX - width, y: rect.minY + width))
            }
            path.closeSubpath()
        }
    }
}

// MARK: - Previews

#Preview("Hidden Cell") {
    CellView(
        cell: Cell(state: .hidden, hasMine: false),
        row: 0,
        col: 0,
        gameStatus: .playing,
        isSelected: false,
        isChordReady: false,
        isFlagMode: false,
        onReveal: {},
        onFlag: {}
    )
    .padding()
}

#Preview("Hidden Cell (Selected)") {
    CellView(
        cell: Cell(state: .hidden, hasMine: false),
        row: 0,
        col: 0,
        gameStatus: .playing,
        isSelected: true,
        isChordReady: false,
        isFlagMode: false,
        onReveal: {},
        onFlag: {}
    )
    .padding()
}

#Preview("Revealed - Zero") {
    CellView(
        cell: Cell(state: .revealed(adjacentMines: 0), hasMine: false),
        row: 0,
        col: 0,
        gameStatus: .playing,
        isSelected: false,
        isChordReady: false,
        isFlagMode: false,
        onReveal: {},
        onFlag: {}
    )
    .padding()
}

#Preview("Revealed - Numbers") {
    HStack(spacing: 2) {
        ForEach(1...8, id: \.self) { count in
            CellView(
                cell: Cell(state: .revealed(adjacentMines: count), hasMine: false),
                row: 0,
                col: count - 1,
                gameStatus: .playing,
                isSelected: false,
                isChordReady: count == 1,
                isFlagMode: false,
                onReveal: {},
                onFlag: {}
            )
        }
    }
    .padding()
}

#Preview("Flagged Cell") {
    CellView(
        cell: Cell(state: .flagged, hasMine: true),
        row: 0,
        col: 0,
        gameStatus: .playing,
        isSelected: false,
        isChordReady: false,
        isFlagMode: false,
        onReveal: {},
        onFlag: {}
    )
    .padding()
}

#Preview("Mine (Game Over)") {
    CellView(
        cell: Cell(state: .revealed(adjacentMines: 0), hasMine: true),
        row: 0,
        col: 0,
        gameStatus: .lost,
        isSelected: false,
        isChordReady: false,
        isFlagMode: false,
        onReveal: {},
        onFlag: {}
    )
    .padding()
}

#Preview("Exploded Mine") {
    CellView(
        cell: Cell(state: .revealed(adjacentMines: 0), hasMine: true, isExploded: true),
        row: 0,
        col: 0,
        gameStatus: .lost,
        isSelected: false,
        isChordReady: false,
        isFlagMode: false,
        onReveal: {},
        onFlag: {}
    )
    .padding()
}

// MARK: - Dark Mode Previews

#Preview("Hidden Cell (Dark)") {
    CellView(
        cell: Cell(state: .hidden, hasMine: false),
        row: 0,
        col: 0,
        gameStatus: .playing,
        isSelected: false,
        isChordReady: false,
        isFlagMode: false,
        onReveal: {},
        onFlag: {}
    )
    .padding()
    .preferredColorScheme(.dark)
}

#Preview("Revealed - Numbers (Dark)") {
    HStack(spacing: 2) {
        ForEach(1...8, id: \.self) { count in
            CellView(
                cell: Cell(state: .revealed(adjacentMines: count), hasMine: false),
                row: 0,
                col: count - 1,
                gameStatus: .playing,
                isSelected: false,
                isChordReady: count == 1,
                isFlagMode: false,
                onReveal: {},
                onFlag: {}
            )
        }
    }
    .padding()
    .preferredColorScheme(.dark)
}
