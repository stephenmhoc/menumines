import SwiftUI

struct HeaderView: View {
    let status: GameStatus
    /// Read only by the clock, so the tick each second redraws the clock and nothing else.
    let elapsedTime: () -> TimeInterval
    let flagCount: Int
    let canReset: Bool
    var isHoldingCell: Bool = false
    /// What the reset command does with this board.
    var resetAction: ResetAction = .restartToday
    /// Why reset is unavailable, when it is.
    var resetLockedHint: String = String(localized: "reset_locked_hint")
    let onReset: () -> Void

    private var statusEmoji: String {
        switch status {
        case .notStarted, .playing:
            return isHoldingCell ? "😮" : "🙂"
        case .won:
            return "😎"
        case .lost:
            return "😵"
        }
    }

    private var statusDescription: String {
        switch status {
        case .notStarted:
            return String(localized: "status_ready")
        case .playing:
            return String(localized: "status_playing")
        case .won:
            return String(localized: "status_won")
        case .lost:
            return String(localized: "status_lost")
        }
    }

    private var flagCountAccessibilityLabel: String {
        // Flagging is uncapped, so an over-flagged board would otherwise announce
        // a negative number of mines remaining.
        let remaining = max(0, Board.mineCount - flagCount)
        return String(localized: "flag_count_accessibility \(flagCount) \(remaining)")
    }

    var body: some View {
        HStack {
            HStack(spacing: 4) {
                FlagGlyph(size: 12)
                Text("\(flagCount)/\(Board.mineCount)")
                    .font(.system(size: 14, weight: .medium))
                    .monospacedDigit()
            }
            .frame(minWidth: 60, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(flagCountAccessibilityLabel)

            Spacer()

            // The face: how the game is going, and pressed for a new game or a restart.
            Button(action: onReset) {
                Text(statusEmoji)
                    .font(.system(size: 22))
            }
            .buttonStyle(FaceButtonStyle())
            // The gear menu shows ⌘R too, but a menu that isn't open answers no shortcuts.
            .keyboardShortcut("r", modifiers: .command)
            .disabled(!canReset)
            .help(canReset ? resetAction.title : resetLockedHint)
            // Named for what pressing it does. The face itself is how the game is going.
            .accessibilityLabel(resetAction.title)
            .accessibilityValue(statusDescription)
            .accessibilityHint(canReset ? resetAction.hint : resetLockedHint)

            Spacer()

            GameClockText(elapsedTime: elapsedTime)
                .frame(minWidth: 60, alignment: .trailing)
        }
        // Inset to the cells, so the counter and the clock line up with the board's edges.
        .padding(.horizontal, GameBoardView.platePadding)
        .frame(width: GameBoardView.width)
    }
}

/// The game clock. It's its own view so that the time, which changes every second, is read
/// here and nowhere else in the panel.
private struct GameClockText: View {
    let elapsedTime: () -> TimeInterval

    var body: some View {
        let elapsedTime = elapsedTime()
        Text(elapsedTime.clockString)
            .font(.system(size: 14, weight: .medium))
            .monospacedDigit()
            // Spoken the way every other time in the app is, not read out as digits.
            .accessibilityLabel(String(localized: "timer_accessibility_label"))
            .accessibilityValue(elapsedTime.spokenDuration)
    }
}

/// The face: a rounded backing under the pointer and while pressed, like a toolbar button.
/// It keeps its full colour while reset is locked, since the face also shows how the game
/// is going; only the backing goes.
private struct FaceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        FaceButton(configuration: configuration)
    }

    private struct FaceButton: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovered = false

        private var backingOpacity: Double {
            guard isEnabled else { return 0 }
            if configuration.isPressed { return 0.16 }
            return isHovered ? 0.08 : 0
        }

        var body: some View {
            configuration.label
                .frame(width: 32, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(backingOpacity))
                )
                .contentShape(.rect)
                .onHover { isHovered = $0 }
                .animation(.easeOut(duration: 0.08), value: isHovered)
        }
    }
}

// MARK: - Previews

#Preview("Not Started") {
    HeaderView(status: .notStarted, elapsedTime: { 0 }, flagCount: 0, canReset: true, onReset: {})
        .padding()
}

#Preview("Playing") {
    HeaderView(status: .playing, elapsedTime: { 125 }, flagCount: 3, canReset: true, onReset: {})
        .padding()
}

#Preview("Won") {
    HeaderView(status: .won, elapsedTime: { 89 }, flagCount: 10, canReset: true, onReset: {})
        .padding()
}

#Preview("Lost") {
    HeaderView(status: .lost, elapsedTime: { 45 }, flagCount: 5, canReset: true, onReset: {})
        .padding()
}
