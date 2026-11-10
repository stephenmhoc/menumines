import AppKit
import SwiftUI

// The pieces a cell is drawn from: its tile, its glyphs, its number colours, and the AppKit
// view that takes its clicks.

enum CellMetrics {
    /// The cell's hit area. Cells sit edge to edge, so there's no line between them that
    /// swallows a click; the gap the player sees is drawn inside each cell.
    static let size: CGFloat = 29
    /// How far the visible tile sits inside the hit area, on each side.
    static let inset: CGFloat = 1
    static let raisedCornerRadius: CGFloat = 4.5
    static let revealedCornerRadius: CGFloat = 2.5
    /// Nine cells across. Header and footer use it so they line up with the board's edges.
    static let boardWidth = size * CGFloat(Board.cols)
}

// MARK: - Tiles

/// A covered cell: a raised tile, lit from above.
struct RaisedTile: View {
    var isHovered = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var isDark: Bool { colorScheme == .dark }
    private var isIncreased: Bool { contrast == .increased }
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: CellMetrics.raisedCornerRadius, style: .continuous)
    }

    private var fill: LinearGradient {
        let top: Color
        let bottom: Color
        if isDark {
            top = Color(white: isHovered ? 0.47 : 0.42)
            bottom = Color(white: isHovered ? 0.40 : 0.35)
        } else {
            top = Color(white: isHovered ? 0.88 : 0.85)
            bottom = Color(white: isHovered ? 0.81 : 0.78)
        }
        return LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
    }

    private var edge: Color {
        if isIncreased {
            return isDark ? Color.white.opacity(0.6) : Color.black.opacity(0.55)
        }
        return isDark ? Color.black.opacity(0.45) : Color.black.opacity(0.2)
    }

    var body: some View {
        shape
            .fill(fill)
            // The highlight along the top edge is what reads as "raised".
            .overlay(alignment: .top) {
                shape
                    .inset(by: 0.5)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(isDark ? 0.28 : 0.75), .clear],
                            startPoint: .top,
                            endPoint: .center
                        ),
                        lineWidth: 1
                    )
            }
            .overlay(shape.strokeBorder(edge, lineWidth: isIncreased ? 1 : 0.5))
            .shadow(color: .black.opacity(isDark ? 0.35 : 0.14), radius: 0.5, y: 0.75)
            .padding(CellMetrics.inset)
    }
}

/// An opened cell, or one being pressed: flat and set into the board.
struct RecessedTile: View {
    var isExploded = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: CellMetrics.revealedCornerRadius, style: .continuous)
    }

    private var fill: Color {
        if isExploded {
            return Color(nsColor: .systemRed)
        }
        let isDark = colorScheme == .dark
        // Light mode opens cells up lighter than the board, the way paper shows through;
        // dark mode sets them into it. Either way they're the opposite of the raised tiles.
        if contrast == .increased {
            return isDark ? Color.black.opacity(0.55) : Color.white
        }
        return isDark ? Color.black.opacity(0.28) : Color.white.opacity(0.75)
    }

    var body: some View {
        shape
            .fill(fill)
            .overlay {
                if contrast == .increased && !isExploded {
                    shape.strokeBorder(Color.primary.opacity(0.35), lineWidth: 0.5)
                }
            }
            .padding(CellMetrics.inset / 2)
    }
}

/// The surface the cells sit on. Solid, so the board reads the same whatever is behind the panel.
struct BoardPlate: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(Color(nsColor: .windowBackgroundColor))
            // A shade darker in light mode, so the lines between opened cells show.
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.black.opacity(colorScheme == .dark ? 0 : 0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08), lineWidth: 0.5)
            )
    }
}

// MARK: - Glyphs

/// The flag, as it appears on the board, in the header and in the controls help.
struct FlagGlyph: View {
    var size: CGFloat = 13

    var body: some View {
        Image(systemName: "flag.fill")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(Color(nsColor: .systemRed))
    }
}

/// A mine: a round body with eight spikes and a glint. SF Symbols has nothing that reads as
/// a mine at this size, and the emoji looked like a cartoon bomb pasted onto the board.
struct MineGlyph: View {
    var color: Color = .primary
    var size: CGFloat = 15

    var body: some View {
        ZStack {
            MineSpikes()
                .stroke(color, style: StrokeStyle(lineWidth: size * 0.11, lineCap: .round))
            Circle()
                .fill(color)
                .padding(size * 0.2)
            Circle()
                .fill(Color.white.opacity(0.85))
                .frame(width: size * 0.16, height: size * 0.16)
                .offset(x: -size * 0.1, y: -size * 0.1)
        }
        .frame(width: size, height: size)
    }
}

private struct MineSpikes: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2 * 0.92
        var path = Path()
        for index in 0..<8 {
            let angle = Double(index) * .pi / 4
            // The diagonals are a little shorter, the way a sea mine's horns are usually drawn.
            let length = index.isMultiple(of: 2) ? radius : radius * 0.82
            path.move(to: center)
            path.addLine(to: CGPoint(x: center.x + cos(angle) * length, y: center.y + sin(angle) * length))
        }
        return path
    }
}

// MARK: - Number Colours

enum NumberPalette {
    /// The classic order (blue, green, red, navy, maroon, teal, black, grey) in system colours,
    /// so each adapts to light, dark and Increase Contrast. Purple stands in for navy, which
    /// is too close to blue in dark mode. Every number is also its digit, so none relies on colour.
    static func color(for adjacentMines: Int) -> Color {
        switch adjacentMines {
        case 1: Color(nsColor: .systemBlue)
        case 2: Color(nsColor: .systemGreen)
        case 3: Color(nsColor: .systemRed)
        case 4: Color(nsColor: .systemPurple)
        case 5: Color(nsColor: .systemBrown)
        case 6: Color(nsColor: .systemTeal)
        case 7: Color(nsColor: .labelColor)
        default: Color(nsColor: .secondaryLabelColor)
        }
    }
}

// MARK: - Click Handler

struct ClickHandlerView: NSViewRepresentable {
    let onLeftClick: () -> Void
    let onRightClick: () -> Void
    let onMiddleClick: () -> Void
    let onPressedChanged: (Bool) -> Void

    func makeNSView(context: Context) -> ClickableNSView {
        let view = ClickableNSView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ nsView: ClickableNSView, context: Context) {
        nsView.onLeftClick = onLeftClick
        nsView.onRightClick = onRightClick
        nsView.onMiddleClick = onMiddleClick
        nsView.onPressedChanged = onPressedChanged
    }
}

/// Handles clicks the way a Mac button does: a left click acts on release, so a player who
/// changes their mind can drag off the cell and let go. A secondary click flags on the way
/// down, because a flag is safe and these need to be quick. A middle click chords on release.
final class ClickableNSView: NSView {
    var onLeftClick: (() -> Void)?
    var onRightClick: (() -> Void)?
    var onMiddleClick: (() -> Void)?
    var onPressedChanged: ((Bool) -> Void)?

    /// Decided on the way down. Letting go of Control before the mouse must not turn a
    /// control-click into a reveal, which could lose the game.
    private var isPrimaryPress = false

    /// The panel doesn't activate the app, so without this the first click after another
    /// app's window, a menu or a popover only brings the panel forward and is lost.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

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

    override func otherMouseDown(with event: NSEvent) {
        guard event.buttonNumber == 2 else {
            super.otherMouseDown(with: event)
            return
        }
    }

    override func otherMouseUp(with event: NSEvent) {
        guard event.buttonNumber == 2, contains(event) else {
            super.otherMouseUp(with: event)
            return
        }
        onMiddleClick?()
    }

    private func flag() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        onRightClick?()
    }

    private func contains(_ event: NSEvent) -> Bool {
        bounds.contains(convert(event.locationInWindow, from: nil))
    }
}
