import SwiftUI

struct FooterView: View {
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    let isGameComplete: Bool
    let puzzleType: PuzzleType
    let canReset: Bool
    let isFlagMode: Bool
    /// Finished text for the result, once there is one.
    var shareText: String?
    /// When the next daily arrives, once today's is finished.
    var nextPuzzleDate: Date?
    let onReset: () -> Void
    let onToggleFlagMode: () -> Void
    let onCopy: () -> Void
    var onReturnToToday: () -> Void = {}
    let onAbout: () -> Void

    @State private var showCopiedFeedback = false
    @State private var showControls = false

    private var puzzleTypeLabel: String {
        switch puzzleType {
        case .daily:
            String(localized: "puzzle_type_daily")
        case .random:
            String(localized: "puzzle_type_random")
        case .practice:
            String(localized: "puzzle_type_practice")
        }
    }

    private var puzzleTypeIconName: String {
        switch puzzleType {
        case .daily:
            "calendar"
        case .random:
            "shuffle"
        case .practice:
            "clock.arrow.circlepath"
        }
    }

    var body: some View {
        HStack {
            // Left side: where the player is, or what they can do with a finished game.
            if puzzleType == .practice {
                Button(String(localized: "return_to_today_button"), action: onReturnToToday)
                    .buttonStyle(.bordered)
                    .fixedSize()
                    .help(String(localized: "return_to_today_help"))
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
            } else if puzzleType != .practice {
                HStack(spacing: 4) {
                    Image(systemName: puzzleTypeIconName)
                        .font(.caption)
                    Text(puzzleTypeLabel)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundStyle(.secondary)
                .fixedSize()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(String(format: String(localized: "puzzle_type_accessibility_label"), puzzleTypeLabel))
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
                if puzzleType == .practice {
                    Button(String(localized: "return_to_today_button"), action: onReturnToToday)
                }

                Button(String(localized: "reset_button")) {
                    showCopiedFeedback = false
                    onReset()
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!canReset)
                .accessibilityHint(canReset ? String(localized: "reset_accessibility_hint") : String(localized: "reset_locked_hint"))

                Divider()

                Button(String(localized: "stats_menu_item")) {
                    openWindow(id: "stats")
                    WindowActivation.raiseWindowBeingOpened()
                }

                Button(String(localized: "settings_menu_item")) {
                    openSettings()
                    WindowActivation.raiseWindowBeingOpened()
                }
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
        onAbout: {}
    )
        .padding()
}
