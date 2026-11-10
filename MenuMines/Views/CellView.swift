import SwiftUI

struct CellView: View {
    let cell: Cell
    let row: Int
    let col: Int
    let gameStatus: GameStatus
    let isSelected: Bool
    let isChordReady: Bool
    var isStartHint: Bool = false
    let isFlagMode: Bool
    /// How long after a loss this cell's mine appears, so the mines spread out from the one
    /// that went off instead of all landing at once.
    var mineRevealDelay: Double = 0
    let onReveal: () -> Void
    let onFlag: () -> Void
    var onChord: () -> Void = {}
    var onHover: (Bool) -> Void = { _ in }
    var onHoldChanged: (Bool) -> Void = { _ in }
    var onAccessibilityFocus: () -> Void = {}

    @State private var isHovered = false
    @State private var isPressed = false
    @AccessibilityFocusState private var isAccessibilityFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ZStack {
            tile
            chordReadyRing
            startHintMarker
            content
        }
        .frame(width: CellMetrics.size, height: CellMetrics.size)
        .overlay(selectionRing)
        .overlay(
            ClickHandlerView(
                onLeftClick: onReveal,
                onRightClick: onFlag,
                onMiddleClick: onChord,
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
        // the other 80 cells gets animated too, which reads as the board wobbling. Reveals
        // themselves stay instant: only hover, a flag going down and a lost game's mines move.
        .animation(.easeOut(duration: 0.08), value: isHovered)
        .animation(motion(.easeOut(duration: 0.12)), value: isFlagged)
        .animation(isLostMine ? motion(.easeOut(duration: 0.12).delay(mineRevealDelay)) : nil, value: isLostMine)
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

    private func motion(_ animation: Animation) -> Animation? {
        reduceMotion ? nil : animation
    }

    // MARK: - State

    private var isPlayable: Bool {
        gameStatus == .notStarted || gameStatus == .playing
    }

    private var isRevealed: Bool {
        if case .revealed = cell.state { return true }
        return false
    }

    private var isFlagged: Bool {
        cell.state == .flagged
    }

    /// A flag on a cell with no mine, shown up by losing.
    private var isWrongFlag: Bool {
        isFlagged && !cell.hasMine && gameStatus == .lost
    }

    /// A mine uncovered by losing, other than the one that went off.
    private var isLostMine: Bool {
        gameStatus == .lost && isRevealed && cell.hasMine && !cell.isExploded
    }

    /// Drawn pushed in while the mouse is held on it, the way a covered cell would open.
    private var isSunken: Bool {
        isPressed && isPlayable && !isFlagMode && cell.state == .hidden
    }

    // MARK: - Accessibility

    private var accessibilityLabel: String {
        String(
            format: String(localized: "cell_accessibility_label"),
            row + 1,
            col + 1,
            cell.accessibilityStateDescription(isStartHint: isStartHint, isGameLost: gameStatus == .lost)
        )
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

    // MARK: - Tile

    @ViewBuilder
    private var tile: some View {
        if cell.isExploded {
            RecessedTile(isExploded: true)
        } else if isRevealed || isSunken || isWrongFlag {
            RecessedTile()
        } else {
            // Only a cell that can still be played lights up under the pointer.
            RaisedTile(isHovered: isHovered && isPlayable)
        }
    }

    @ViewBuilder
    private var chordReadyRing: some View {
        if isHovered && isChordReady && isRevealed {
            MarkerRing(cornerRadius: CellMetrics.revealedCornerRadius)
                .padding(2)
        }
    }

    // MARK: - Start Hint

    /// A small dot on the day's safe opening cell, so the board can start covered without
    /// the first click being a guess. It carries a ring in the label colour, because the
    /// accent alone disappears into the tile under Graphite.
    @ViewBuilder
    private var startHintMarker: some View {
        if isStartHint, cell.state == .hidden, !isSunken {
            Circle()
                .fill(Color.accentColor)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.55), lineWidth: 1))
                .frame(width: 9, height: 9)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if cell.isExploded {
            MineGlyph(color: .white)
        } else {
            switch cell.state {
            case .hidden:
                EmptyView()
            case .flagged where isWrongFlag:
                Image(systemName: "flag.slash.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            case .flagged:
                FlagGlyph()
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            case .revealed(let adjacentMines):
                if cell.hasMine {
                    MineGlyph()
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                } else if adjacentMines > 0 {
                    Text("\(adjacentMines)")
                        .font(.system(size: 16, weight: contrast == .increased ? .heavy : .bold, design: .rounded))
                        .foregroundStyle(NumberPalette.color(for: adjacentMines))
                }
            }
        }
    }

    // MARK: - Selection

    @ViewBuilder
    private var selectionRing: some View {
        if isSelected {
            MarkerRing(cornerRadius: CellMetrics.raisedCornerRadius + 0.5)
        }
    }
}

/// Cells are redrawn only when what they show changes, not every time the board's parent is.
/// The closures are left out: they're rebuilt with every board, and act only on the row and
/// column, the cell and the flag mode, which are compared.
extension CellView: Equatable {
    static func == (lhs: CellView, rhs: CellView) -> Bool {
        lhs.cell == rhs.cell
            && lhs.row == rhs.row
            && lhs.col == rhs.col
            && lhs.gameStatus == rhs.gameStatus
            && lhs.isSelected == rhs.isSelected
            && lhs.isChordReady == rhs.isChordReady
            && lhs.isStartHint == rhs.isStartHint
            && lhs.isFlagMode == rhs.isFlagMode
            && lhs.mineRevealDelay == rhs.mineRevealDelay
    }
}

/// The ring for the keyboard selection and a number ready to chord: the accent, lined with
/// the background colour so it still stands out from the tiles when the accent is Graphite.
private struct MarkerRing: View {
    let cornerRadius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            shape.strokeBorder(Color.accentColor, lineWidth: 2)
            shape.inset(by: 2).strokeBorder(Color(nsColor: .textBackgroundColor).opacity(0.75), lineWidth: 1)
        }
    }
}

// MARK: - Previews

private func previewCell(
    _ state: CellState,
    hasMine: Bool = false,
    isExploded: Bool = false,
    status: GameStatus = .playing,
    isSelected: Bool = false,
    isStartHint: Bool = false
) -> some View {
    CellView(
        cell: Cell(state: state, hasMine: hasMine, isExploded: isExploded),
        row: 0,
        col: 0,
        gameStatus: status,
        isSelected: isSelected,
        isChordReady: false,
        isStartHint: isStartHint,
        isFlagMode: false,
        onReveal: {},
        onFlag: {}
    )
}

#Preview("Cells") {
    VStack(spacing: 0) {
        HStack(spacing: 0) {
            previewCell(.hidden)
            previewCell(.hidden, status: .notStarted, isStartHint: true)
            previewCell(.hidden, isSelected: true)
            previewCell(.flagged, hasMine: true)
            previewCell(.flagged, status: .lost)
            previewCell(.revealed(adjacentMines: 0), hasMine: true, status: .lost)
            previewCell(.revealed(adjacentMines: 0), hasMine: true, isExploded: true, status: .lost)
            previewCell(.revealed(adjacentMines: 0))
        }
        HStack(spacing: 0) {
            ForEach(1...8, id: \.self) { count in
                previewCell(.revealed(adjacentMines: count))
            }
        }
    }
    .padding()
}
