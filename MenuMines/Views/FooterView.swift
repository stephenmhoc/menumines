import SwiftUI

struct FooterView: View {
    let isGameComplete: Bool
    let puzzleType: PuzzleType
    let canReset: Bool
    let isFlagMode: Bool
    /// Finished text for the result, once there is one.
    var shareText: String?
    /// When the next daily arrives, once today's is finished.
    var nextPuzzleDate: Date?
    /// The day on the board, when it's an earlier one.
    var pastDay: Date?
    /// Why reset is unavailable, when the puzzle type alone doesn't say.
    var resetLockedHint: String?
    let onReset: () -> Void
    let onToggleFlagMode: () -> Void
    let onCopy: () -> Void
    var onReturnToToday: () -> Void = {}
    var onDailyHistory: () -> Void = {}
    let onStats: () -> Void
    let onSettings: () -> Void
    let onAbout: () -> Void

    @State private var showCopiedFeedback = false
    @State private var showControls = false

    private var isPastDay: Bool { puzzleType.isPastDay }

    var body: some View {
        HStack(spacing: 6) {
            // Left side: where the player is, or what they can do with a finished game.
            if isPastDay {
                returnToTodayButton
            }

            if isGameComplete {
                copyButton

                if let shareText {
                    ResultShareButton(text: shareText)
                }
            } else if isPastDay {
                // Which day this is, and whether it counts. The button beside it already
                // says it isn't today.
                if let pastDay {
                    let description = puzzleType.pastDayDescription(for: pastDay)
                    HStack(spacing: 4) {
                        Image(systemName: puzzleType.iconName)
                            .font(.caption)
                        Text(pastDay.formatted(Date.FormatStyle(timeZone: .gmt).month(.abbreviated).day()))
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .help(description)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(description)
                }
            } else {
                HStack(spacing: 4) {
                    Image(systemName: puzzleType.iconName)
                        .font(.caption)
                    Text(puzzleType.label)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundStyle(.secondary)
                .fixedSize()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    String(format: String(localized: "puzzle_type_accessibility_label"), puzzleType.label)
                )
            }

            if let nextPuzzleDate {
                NextPuzzleCountdown(date: nextPuzzleDate)
            }

            Spacer(minLength: 0)

            HStack(spacing: 2) {
                Toggle(isOn: Binding(get: { isFlagMode }, set: { _ in onToggleFlagMode() })) {
                    Image(systemName: isFlagMode ? "flag.fill" : "flag")
                }
                .toggleStyle(FooterIconToggleStyle())
                .disabled(isGameComplete)
                .help(String(localized: "flag_mode_button_help"))
                .accessibilityLabel(String(localized: "controls_flag_mode"))

                Button {
                    showControls.toggle()
                } label: {
                    Image(systemName: "questionmark.circle")
                }
                .buttonStyle(FooterIconButtonStyle())
                .help(String(localized: "controls_button_accessibility"))
                .popover(isPresented: $showControls) {
                    ControlsPopoverView()
                }
                .accessibilityLabel(String(localized: "controls_button_accessibility"))

                gearMenu
            }
        }
        .frame(width: GameBoardView.width)
    }

    /// Spelled out while there's room, and an icon beside a finished game's Copy and Share,
    /// where the words would push the footer past the board.
    @ViewBuilder
    private var returnToTodayButton: some View {
        let title = String(localized: "return_to_today_button")
        Group {
            if isGameComplete {
                Button(action: onReturnToToday) {
                    Image(systemName: "arrow.uturn.backward")
                        .accessibilityLabel(title)
                }
            } else {
                Button(title, action: onReturnToToday)
            }
        }
        .buttonStyle(.bordered)
        .fixedSize()
        .help(isGameComplete ? "\(title). \(puzzleType.returnToTodayHelp)" : puzzleType.returnToTodayHelp)
    }

    private var copyButton: some View {
        Button {
            onCopy()
            showCopiedFeedback = true
            AccessibilityNotification.Announcement(String(localized: "share_copied")).post()
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                showCopiedFeedback = false
            }
        } label: {
            // Both words are laid out and one is shown, so the button keeps the width of the
            // longer one and doesn't shove its neighbours when it changes.
            ZStack {
                Text(String(localized: "copy_result_button"))
                    .opacity(showCopiedFeedback ? 0 : 1)
                Text(String(localized: "share_copied"))
                    .opacity(showCopiedFeedback ? 1 : 0)
            }
        }
        .buttonStyle(.bordered)
        .fixedSize()
        .accessibilityLabel(String(localized: "copy_result_button"))
    }

    private var gearMenu: some View {
        Menu {
            if isPastDay {
                Button(String(localized: "return_to_today_button"), action: onReturnToToday)
            }

            Button(String(localized: "reset_button")) {
                showCopiedFeedback = false
                onReset()
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(!canReset)
            .accessibilityHint(canReset ? puzzleType.resetHint : (resetLockedHint ?? puzzleType.resetLockedHint))

            Divider()

            Button(String(localized: "daily_history_menu_item"), action: onDailyHistory)

            Button(String(localized: "stats_menu_item"), action: onStats)

            Button(String(localized: "settings_menu_item"), action: onSettings)
            .keyboardShortcut(",", modifiers: .command)

            #if SPARKLE_ENABLED
            Divider()

            Button(String(localized: UpdateManager.isUpdatePending
                ? "update_available_menu_item"
                : "check_for_updates_menu_item")) {
                UpdateManager.checkForUpdates()
            }
            .disabled(!UpdateManager.canCheckForUpdates)
            #endif

            Divider()

            Button(String(localized: "about_menu_item")) {
                onAbout()
            }

            Button(String(localized: "quit_menu_item")) {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        } label: {
            Image(systemName: "gearshape")
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: FooterIconMetrics.size, height: FooterIconMetrics.size)
        .modifier(HoverBacking())
        .help(String(localized: "footer_menu_accessibility_label"))
        .accessibilityLabel(String(localized: "footer_menu_accessibility_label"))
    }
}

extension GameState {
    /// Why reset is unavailable. A daily carried over from its day isn't today's puzzle.
    var resetLockedHint: String {
        isCarriedOverDaily ? String(localized: "reset_locked_hint_carried_over") : puzzleType.resetLockedHint
    }
}

extension PuzzleType {
    /// The short name shown beside the board.
    var label: String {
        switch self {
        case .daily:
            String(localized: "puzzle_type_daily")
        case .random:
            String(localized: "puzzle_type_random")
        case .practice:
            String(localized: "puzzle_type_practice")
        case .pastDaily:
            String(localized: "puzzle_type_past_daily")
        }
    }

    var iconName: String {
        switch self {
        case .daily:
            "calendar"
        case .random:
            "shuffle"
        case .practice:
            "clock.arrow.circlepath"
        case .pastDaily:
            "calendar.badge.clock"
        }
    }

    /// Whether the board is an earlier day's, as a past daily or a replay.
    var isPastDay: Bool {
        self == .practice || self == .pastDaily
    }

    /// What a reset would do, for VoiceOver.
    var resetHint: String {
        String(localized: isPastDay ? "reset_accessibility_hint_past_day" : "reset_accessibility_hint")
    }

    /// Why reset is unavailable, when it is.
    var resetLockedHint: String {
        String(localized: self == .pastDaily ? "reset_locked_hint_past_daily" : "reset_locked_hint")
    }

    var resetConfirmationMessage: String {
        String(localized: isPastDay ? "reset_confirmation_message_past_day" : "reset_confirmation_message")
    }

    var returnToTodayHelp: String {
        String(localized: self == .pastDaily ? "return_to_today_help_past_daily" : "return_to_today_help")
    }

    /// Says which earlier day is on the board and whether its result counts, in full.
    func pastDayDescription(for date: Date) -> String {
        let day = date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: .gmt))
        let key: String.LocalizationValue = self == .pastDaily ? "past_daily_description" : "replay_description"
        return String(format: String(localized: key), day)
    }
}

/// How long until the next daily. Worth stating because puzzles change at midnight UTC, which
/// for most players isn't midnight, and a streak depends on knowing when that is.
private struct NextPuzzleCountdown: View {
    let date: Date

    private var formatter: DateComponentsFormatter {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let remaining = max(60, date.timeIntervalSince(context.date))
            Text(String(format: String(localized: "next_puzzle_countdown"), formatter.string(from: remaining) ?? ""))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                // The footer leaves room for the longest countdown, "23h 59m", so it never
                // needs shrinking or cutting short.
                .fixedSize()
        }
    }
}

/// Offers the result's text through the system's share menu, or dragged out of the panel.
/// Text, not a picture of it, so it can be pasted, edited and read by a screen reader
/// wherever it lands.
private struct ResultShareButton: View {
    let text: String

    var body: some View {
        ShareLink(item: text, preview: SharePreview(String(localized: "share_preview_title"))) {
            Image(systemName: "square.and.arrow.up")
        }
        .buttonStyle(FooterIconButtonStyle())
        .draggable(text)
        .help(String(localized: "share_button"))
        .accessibilityLabel(String(localized: "share_button"))
    }
}

// MARK: - Previews

#Preview("Footer - Game In Progress") {
    FooterView(
        isGameComplete: false,
        puzzleType: .daily,
        canReset: true,
        isFlagMode: false,
        onReset: {},
        onToggleFlagMode: {},
        onCopy: {},
        onStats: {},
        onSettings: {},
        onAbout: {}
    )
        .padding()
}

#Preview("Footer - Game Complete") {
    FooterView(
        isGameComplete: true,
        puzzleType: .random,
        canReset: true,
        isFlagMode: true,
        onReset: {},
        onToggleFlagMode: {},
        onCopy: {},
        onStats: {},
        onSettings: {},
        onAbout: {}
    )
        .padding()
}
