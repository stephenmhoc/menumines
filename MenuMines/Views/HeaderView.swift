import SwiftUI

struct HeaderView: View {
    let status: GameStatus
    let elapsedTime: TimeInterval
    let flagCount: Int
    let canReset: Bool
    var isHoldingCell: Bool = false
    /// What a reset would do, for VoiceOver.
    var resetHint: String = String(localized: "reset_accessibility_hint")
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

    private var timerAccessibilityLabel: String {
        let totalSeconds = Int(elapsedTime)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60

        if minutes == 0 {
            if seconds == 1 {
                return String(localized: "timer_accessibility_one_second")
            }
            return String(format: String(localized: "timer_accessibility_seconds"), seconds)
        } else if minutes == 1 {
            if seconds == 0 {
                return String(localized: "timer_accessibility_one_minute")
            }
            return String(format: String(localized: "timer_accessibility_one_minute_seconds"), seconds)
        }
        if seconds == 0 {
            return String(format: String(localized: "timer_accessibility_minutes"), minutes)
        }
        return String(format: String(localized: "timer_accessibility_minutes_seconds"), minutes, seconds)
    }

    private var flagCountAccessibilityLabel: String {
        // Flagging is uncapped, so an over-flagged board would otherwise announce
        // a negative number of mines remaining.
        let remaining = max(0, Board.mineCount - flagCount)
        if remaining == 1 {
            return String(format: String(localized: "flag_count_accessibility_one_remaining"), flagCount)
        }
        return String(format: String(localized: "flag_count_accessibility_remaining"), flagCount, remaining)
    }

    var body: some View {
        HStack {
            // Flag count
            HStack(spacing: 4) {
                Text("🚩")
                Text("\(flagCount)/\(Board.mineCount)")
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
            }
            .frame(minWidth: 60, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(flagCountAccessibilityLabel)

            Spacer()

            // Status emoji - clickable to reset game
            Button(action: onReset) {
                Text(statusEmoji)
                    .font(.system(size: 24))
            }
            .buttonStyle(.plain)
            // The gear menu shows ⌘R too, but a menu that isn't open answers no shortcuts.
            .keyboardShortcut("r", modifiers: .command)
            .disabled(!canReset)
            .help(canReset ? String(localized: "reset_button") : resetLockedHint)
            .accessibilityLabel(String(format: String(localized: "reset_accessibility_combined"), statusDescription))
            .accessibilityHint(canReset ? resetHint : resetLockedHint)

            Spacer()

            // Timer
            Text(elapsedTime.clockString)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .frame(minWidth: 60, alignment: .trailing)
                .accessibilityLabel(timerAccessibilityLabel)
        }
        .padding(.horizontal, 8)
    }
}

// MARK: - Previews

#Preview("Not Started") {
    HeaderView(status: .notStarted, elapsedTime: 0, flagCount: 0, canReset: true, onReset: {})
        .padding()
}

#Preview("Playing") {
    HeaderView(status: .playing, elapsedTime: 125, flagCount: 3, canReset: true, onReset: {})
        .padding()
}

#Preview("Won") {
    HeaderView(status: .won, elapsedTime: 89, flagCount: 10, canReset: true, onReset: {})
        .padding()
}

#Preview("Lost") {
    HeaderView(status: .lost, elapsedTime: 45, flagCount: 5, canReset: true, onReset: {})
        .padding()
}
