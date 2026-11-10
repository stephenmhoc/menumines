import SwiftUI

/// Which tab the Statistics window is turned to. Lives outside the view so that the app can
/// turn a window that's already open to the calendar.
@Observable
final class StatsNavigation {
    var tab: StatsTab = .summary
}

/// The Statistics window: the summary, the Daily History calendar and recent results, with
/// the tabs in the window's toolbar.
struct StatsWindow: View {
    static let width: CGFloat = 380

    let gameState: GameState
    var navigation = StatsNavigation()
    /// Takes the player to a past day's board. The window can't do that itself: it has to
    /// come down and the game panel has to open.
    var onPlayDay: (Int64) -> Void = { _ in }
    /// Told the height the content wants, so the window can grow or shrink to it.
    var onContentHeightChange: (CGFloat) -> Void = { _ in }

    @State private var showResetConfirmation = false
    @AppStorage(Constants.SettingsKeys.showStreaks) private var showStreaks = true

    private var selectedTab: StatsTab { navigation.tab }

    private var store: StatsStore {
        StatsStore.shared
    }

    private var hasAnyResult: Bool {
        store.hasResults || store.pastDailyGamesPlayed > 0
    }

    /// Whether this copy is only being laid out to find the content's height.
    var isMeasuring = false

    /// The size the content wants at full height, for the window to open at. The window's
    /// own copy scrolls, so it has no height of its own to give.
    @MainActor
    static func idealContentSize(gameState: GameState, navigation: StatsNavigation) -> NSSize {
        NSHostingView(rootView: StatsWindow(gameState: gameState, navigation: navigation, isMeasuring: true))
            .fittingSize
    }

    var body: some View {
        if isMeasuring {
            content
        } else {
            window
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            selectedContent
            footer
        }
        .frame(width: Self.width)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var window: some View {
        // The window is as tall as the content, and the content scrolls only when the
        // screen is shorter than that.
        ScrollView(.vertical) {
            content
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    onContentHeightChange(height)
                }
        }
        .scrollBounceBehavior(.basedOnSize)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker(String(localized: "stats_view_picker"), selection: Bindable(navigation).tab) {
                    ForEach(StatsTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
        }
        .alert(String(localized: "stats_reset_confirmation_title"), isPresented: $showResetConfirmation) {
            Button(String(localized: "stats_reset_confirmation_cancel"), role: .cancel) {}
                .keyboardShortcut(.defaultAction)
            Button(String(localized: "stats_reset_confirmation_confirm"), role: .destructive) {
                store.reset()
            }
        } message: {
            Text(String(localized: Self.resetMessageKey))
        }
    }

    /// With iCloud, a reset reaches every Mac signed in to it, and the warning has to say so.
    private static var resetMessageKey: String.LocalizationValue {
        #if ICLOUD_SYNC_ENABLED
        return "stats_reset_confirmation_message_icloud"
        #else
        return "stats_reset_confirmation_message"
        #endif
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedTab {
        case .summary:
            // The calendar is how past days are found, so it's there before any game has
            // been finished. The other tabs have nothing to show until one has.
            if hasAnyResult {
                summaryForm
            } else {
                emptyState(
                    title: "stats_empty_message",
                    systemImage: "chart.bar.xaxis",
                    description: "stats_empty_subtitle"
                )
            }
        case .history:
            DailyCompletionCalendarView(
                todaySeed: gameState.currentDaySeed,
                onTheDay: store.dailyResultsBySeed,
                later: store.pastDailyResultsBySeed,
                inProgress: gameState.pastDailySeedsInProgress,
                carriedOver: gameState.carriedOverDailySeed,
                onPlay: onPlayDay
            )
            .padding(.horizontal, 20)
            .padding(.top, 16)
        case .recent:
            if store.recentDailyResults.isEmpty {
                emptyState(
                    title: "stats_recent_empty",
                    systemImage: "calendar",
                    description: "stats_recent_empty_subtitle"
                )
            } else {
                RecentDailyResultsView(results: store.recentDailyResults)
            }
        }
    }

    private func emptyState(
        title: String.LocalizationValue,
        systemImage: String,
        description: String.LocalizationValue
    ) -> some View {
        ContentUnavailableView {
            Label(String(localized: title), systemImage: systemImage)
        } description: {
            Text(String(localized: description))
        }
        .frame(height: 200)
    }

    // MARK: - Summary

    private var summaryForm: some View {
        Form {
            Section {
                metricRow("stats_games_played", value: store.dailyGamesPlayed)
                metricRow("stats_wins", value: store.dailyWins)
                metricRow("stats_win_rate", rate: store.dailyWinRate)
                metricRow("stats_completion_rate", rate: store.dailyCompletionRate)
                metricRow("stats_best_time", time: store.dailyBestTime)
                metricRow("stats_avg_time", time: store.dailyAverageTime)
                if showStreaks {
                    metricRow("stats_current_streak", value: store.currentStreak)
                    metricRow("stats_longest_streak", value: store.longestStreak)
                }
            } header: {
                sectionHeader("stats_section_daily")
            }

            Section {
                metricRow("stats_games_played", value: store.gamesPlayed)
                metricRow("stats_wins", value: store.wins)
                metricRow("stats_win_rate", rate: store.winRate)
                metricRow("stats_best_time", time: store.bestTime)
                metricRow("stats_avg_time", time: store.averageTime)
            } header: {
                sectionHeader("stats_section_all")
            } footer: {
                if store.pastDailyGamesPlayed == 0 {
                    trackedSinceFooter
                }
            }

            // Days played after the fact, as a figure of their own. They're deliberately
            // absent from everything above: daily stats and streaks are about playing on the day.
            if store.pastDailyGamesPlayed > 0 {
                Section {
                    metricRow("stats_past_dailies_played", value: store.pastDailyGamesPlayed)
                    metricRow("stats_past_dailies_won", value: store.pastDailyWins)
                } header: {
                    sectionHeader("stats_section_past_dailies")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "stats_past_dailies_footnote"))
                        trackedSinceFooter
                    }
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
        // A grouped form scrolls, so it has no height of its own to give the window.
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var trackedSinceFooter: some View {
        if let trackedSince = store.trackedSince {
            let date = trackedSince.formatted(date: .abbreviated, time: .omitted)
            Text(String(localized: "stats_tracked_since \(date)"))
            .foregroundStyle(.secondary)
        }
    }

    private func sectionHeader(_ key: String.LocalizationValue) -> some View {
        Text(String(localized: key))
            .accessibilityAddTraits(.isHeader)
    }

    private func metricRow(_ label: String.LocalizationValue, value: Int) -> some View {
        let text = value.formatted()
        return metricRow(label, shown: text, spoken: text)
    }

    private func metricRow(_ label: String.LocalizationValue, rate: Int?) -> some View {
        guard let rate else { return metricRow(label, shown: nil, spoken: nil) }
        let text = (Double(rate) / 100).formatted(.percent)
        return metricRow(label, shown: text, spoken: text)
    }

    private func metricRow(_ label: String.LocalizationValue, time: TimeInterval?) -> some View {
        metricRow(label, shown: time?.clockString, spoken: time?.spokenDuration)
    }

    /// One figure. Nothing to show yet reads as a dash, and is spoken as "no data".
    private func metricRow(_ label: String.LocalizationValue, shown: String?, spoken: String?) -> some View {
        let title = String(localized: label)
        return LabeledContent(title) {
            Text(shown ?? String(localized: "stats_no_data"))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(spoken ?? String(localized: "stats_no_data_accessibility"))
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button(String(localized: "stats_reset_button")) {
                showResetConfirmation = true
            }
            .disabled(!hasAnyResult)
            .accessibilityHint(String(localized: "stats_reset_accessibility_hint"))

            Spacer()

            if Leaderboard.isAvailable {
                Button(String(localized: "leaderboard_button")) {
                    Leaderboard.show()
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 16)
    }
}

enum StatsTab: String, CaseIterable, Identifiable {
    case summary
    case history
    case recent

    var id: Self { self }

    var title: String {
        switch self {
        case .summary:
            return String(localized: "stats_tab_summary")
        case .history:
            return String(localized: "stats_tab_history")
        case .recent:
            return String(localized: "stats_tab_recent")
        }
    }
}

// MARK: - Recent Daily Results

private struct RecentDailyResultsView: View {
    let results: [GameResult]

    var body: some View {
        Form {
            Section {
                ForEach(results, id: \.dailySeed) { result in
                    LabeledContent {
                        HStack(spacing: 8) {
                            Text(status(of: result))
                                .foregroundStyle(.secondary)
                            Text(result.elapsedTime.clockString)
                                .monospacedDigit()
                                .foregroundStyle(.primary)
                        }
                    } label: {
                        Label {
                            Text(StatsRecentResults.formattedDate(for: result))
                        } icon: {
                            Image(systemName: result.won ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(result.won ? Color.green : Color.red)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibilityLabel(for: result))
                }
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func status(of result: GameResult) -> String {
        result.won ? String(localized: "stats_result_won") : String(localized: "stats_result_lost")
    }

    private func accessibilityLabel(for result: GameResult) -> String {
        let date = StatsRecentResults.formattedDate(for: result)
        let time = result.elapsedTime.spokenDuration
        return result.won
            ? String(localized: "stats_recent_won_accessibility \(date) \(time)")
            : String(localized: "stats_recent_lost_accessibility \(date) \(time)")
    }
}

enum StatsRecentResults {
    /// Names the puzzle that was played, not the local day it happened to be finished on.
    static func formattedDate(for result: GameResult, locale: Locale = .current) -> String {
        guard let date = dateFromSeed(result.dailySeed) else { return "" }
        return date.formatted(
            Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale, timeZone: .gmt)
        )
    }
}

// MARK: - Previews

#Preview("Statistics - Empty") {
    StatsWindow(gameState: GameState(board: Board(dailySeed: 20260725)))
}
