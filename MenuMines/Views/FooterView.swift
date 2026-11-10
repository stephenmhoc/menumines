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
        HStack {
            // Left side: where the player is, or what they can do with a finished game.
            if isPastDay {
                Button(String(localized: "return_to_today_button"), action: onReturnToToday)
                    .buttonStyle(.bordered)
                    .fixedSize()
                    .help(puzzleType.returnToTodayHelp)
            }

            if isGameComplete {
                Button(showCopiedFeedback ? String(localized: "share_copied") : String(localized: "copy_result_button")) {
                    onCopy()
                    showCopiedFeedback = true
                    AccessibilityNotification.Announcement(String(localized: "share_copied")).post()
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        showCopiedFeedback = false
                    }
                }
                .buttonStyle(.bordered)
                .fixedSize()
                .accessibilityLabel(String(localized: "copy_result_button"))

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

            Spacer()
                .layoutPriority(1)

            Button {
                onToggleFlagMode()
            } label: {
                Image(systemName: isFlagMode ? "flag.fill" : "flag")
            }
            .buttonStyle(.borderless)
            .fixedSize()
            .foregroundStyle(isFlagMode ? Color.accentColor : Color.primary)
            .disabled(isGameComplete)
            .help(String(localized: "flag_mode_button_help"))
            .accessibilityLabel(isFlagMode ? String(localized: "flag_mode_on_accessibility") : String(localized: "flag_mode_off_accessibility"))

            Button {
                showControls.toggle()
            } label: {
                Image(systemName: "questionmark.circle")
            }
            .buttonStyle(.borderless)
            .fixedSize()
            .help(String(localized: "controls_button_accessibility"))
            .popover(isPresented: $showControls) {
                ControlsPopoverView()
            }
            .accessibilityLabel(String(localized: "controls_button_accessibility"))

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

                Button(String(localized: "check_for_updates_menu_item")) {
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
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(String(localized: "footer_menu_accessibility_label"))
            .accessibilityLabel(String(localized: "footer_menu_accessibility_label"))
        }
        .frame(width: 260)
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
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

/// Offers the result as an image through the system's share menu, or dragged out of the popover.
private struct ResultShareButton: View {
    let text: String

    @MainActor private var image: Image? {
        let renderer = ImageRenderer(content: ResultCardView(text: text))
        renderer.scale = 2
        return renderer.nsImage.map(Image.init(nsImage:))
    }

    var body: some View {
        if let image {
            let title = String(localized: "share_preview_title")
            ShareLink(item: image, preview: SharePreview(title, image: image)) {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.borderless)
            .fixedSize()
            .draggable(image)
            .help(String(localized: "share_button"))
            .accessibilityLabel(String(localized: "share_button"))
        }
    }
}

/// The result as a picture, for places where pasted emoji don't survive.
private struct ResultCardView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, design: .monospaced))
            .foregroundStyle(.black)
            .padding(16)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Controls Popover

private struct ControlsPopoverView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "controls_title"))
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                controlRow(key: "↑ ↓ ← →", action: String(localized: "controls_move"))
                controlRow(key: String(localized: "controls_key_space"), action: String(localized: "controls_reveal"))
                controlRow(key: "F", action: String(localized: "controls_flag"))
                controlRow(key: "🚩", action: String(localized: "controls_flag_mode"))
            }
            .font(.system(.body, design: .monospaced))
        }
        .padding()
    }

    private func controlRow(key: String, action: String) -> some View {
        HStack(spacing: 16) {
            Text(key)
                .frame(width: 76, alignment: .leading)
            Text(action)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(format: String(localized: "metric_accessibility_label"), key, action))
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
