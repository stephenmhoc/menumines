import AppKit
import SwiftUI

extension DailyHistory.Play {
    var buttonTitle: String {
        switch self {
        case .recorded:
            return String(localized: "stats_calendar_action_play")
        case .resume:
            return String(localized: "stats_calendar_action_continue")
        case .practice:
            return String(localized: "stats_calendar_action_replay")
        }
    }
}

/// How a day went and what playing it would mean, for the line under the grid.
struct DayDescription {
    let shown: String
    let spoken: String

    init(day: DailyHistory.Day, todayResult: GameResult?) {
        func result(
            _ result: GameResult,
            won: String.LocalizationValue,
            lost: String.LocalizationValue
        ) -> (String, String) {
            let key = result.won ? won : lost
            return (
                String(format: String(localized: key), result.elapsedTime.clockString),
                String(format: String(localized: key), result.elapsedTime.spokenDuration)
            )
        }

        let text: (String, String)
        switch day {
        case .beforeLaunch, .future:
            let line = String(localized: "stats_calendar_detail_unavailable")
            text = (line, line)
        case .today:
            if let todayResult {
                text = result(
                    todayResult,
                    won: "stats_calendar_detail_today_won",
                    lost: "stats_calendar_detail_today_lost"
                )
            } else {
                let line = String(localized: "stats_calendar_detail_today")
                text = (line, line)
            }
        case .unplayed:
            let line = String(localized: "stats_calendar_detail_not_played")
            text = (line, line)
        case .inProgress:
            let line = String(localized: "stats_calendar_detail_in_progress")
            text = (line, line)
        case .carriedOver:
            let line = String(localized: "stats_calendar_detail_carried_over")
            text = (line, line)
        case .playedOnTheDay(let played):
            text = result(played, won: "stats_calendar_detail_won", lost: "stats_calendar_detail_lost")
        case .playedLater(let played):
            text = result(played, won: "stats_calendar_detail_won_later", lost: "stats_calendar_detail_lost_later")
        }
        shown = text.0
        spoken = text.1
    }
}

struct CalendarCell: Identifiable {
    let id: String
    let date: Date?
    let day: Int?
}

// MARK: - Colours

/// The calendar's colours. A win is always system green and a loss system red, whatever
/// accent the player has picked: with a red accent, wins and losses would otherwise be the
/// same hue, and with graphite wins would go grey. The accent means "you can play this":
/// today's ring and a day waiting to be played.
enum CalendarPalette {
    static let won = Color(nsColor: .systemGreen)
    static let lost = Color(nsColor: .systemRed)
    static let inProgress = Color(nsColor: .systemOrange)
    static let playable = Color.accentColor

    static func result(_ won: Bool) -> Color {
        won ? self.won : lost
    }
}

/// Says what the tiles' marks mean. The words carry it, so it reads the same to VoiceOver.
/// Two columns that wrap, so longer translations fit.
struct CalendarLegend: View {
    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
            GridRow {
                entry(String(localized: "stats_calendar_legend_on_the_day")) {
                    CalendarTileBackground(style: .onTheDay, tint: CalendarPalette.won)
                }
                entry(String(localized: "stats_calendar_legend_later")) {
                    CalendarTileBackground(style: .later, tint: CalendarPalette.won)
                }
            }
            GridRow {
                entry(String(localized: "stats_calendar_legend_in_progress")) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(CalendarPalette.inProgress)
                }
                entry(String(localized: "stats_calendar_legend_not_played")) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(CalendarPalette.playable)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func entry(_ text: String, @ViewBuilder swatch: () -> some View) -> some View {
        HStack(spacing: 5) {
            swatch()
                .frame(width: 14, height: 12)
                .accessibilityHidden(true)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A tile's fill and outline. A result from the day itself is filled with a solid outline,
/// and one from later is hollow with a dashed outline, so they differ by more than colour.
/// With Increase Contrast, fills and outlines are stronger.
struct CalendarTileBackground: View {
    enum Style {
        case plain, onTheDay, later
    }

    let style: Style
    var tint: Color = CalendarPalette.won
    var isToday = false

    @Environment(\.colorSchemeContrast) private var contrast

    private var isHighContrast: Bool { contrast == .increased }

    var body: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(fillColor)
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(borderColor, style: strokeStyle)
            )
    }

    private var fillColor: Color {
        style == .onTheDay ? tint.opacity(isHighContrast ? 0.5 : 0.32) : Color(nsColor: .controlBackgroundColor)
    }

    private var borderColor: Color {
        if isToday {
            return CalendarPalette.playable
        }
        switch style {
        case .plain:
            return isHighContrast ? Color(nsColor: .secondaryLabelColor) : Color(nsColor: .separatorColor)
        case .onTheDay, .later:
            return tint
        }
    }

    private var strokeStyle: StrokeStyle {
        if isToday {
            return StrokeStyle(lineWidth: 2)
        }
        let width: CGFloat = isHighContrast ? 2 : 1.5
        if style == .later {
            return StrokeStyle(lineWidth: width, dash: [3, 2])
        }
        return StrokeStyle(lineWidth: isHighContrast ? 1.5 : 1)
    }
}

struct CalendarDayCell: View {
    let cell: CalendarCell
    /// Nil for the blank tiles around the month.
    let day: DailyHistory.Day?
    /// Today's tile shows how today went, though it can't be played from here.
    let todayResult: GameResult?
    let isSelected: Bool
    /// Whether the grid has the keyboard, which draws the selection as a focus ring.
    let isFocused: Bool
    /// What activating the tile does, for VoiceOver. Nil if it can't be played from here.
    let onPlay: (() -> Void)?

    static let height: CGFloat = 32

    @State private var isHovered = false
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    var body: some View {
        if cell.date == nil {
            Color.clear
                .frame(height: Self.height)
                .accessibilityHidden(true)
        } else {
            tile
                .onHover { isHovered = $0 }
                .help(helpText)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityHint(playHint)
                .accessibilityAddTraits(onPlay != nil ? .isButton : [])
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityAction {
                    onPlay?()
                }
        }
    }

    /// The result to draw, from the day itself or from later.
    private var result: GameResult? {
        switch day {
        case .playedOnTheDay(let result), .playedLater(let result):
            return result
        case .today:
            return todayResult
        default:
            return nil
        }
    }

    private var isInProgress: Bool {
        day?.isInProgress == true
    }

    private var isPlayedLater: Bool {
        if case .playedLater = day { return true }
        return false
    }

    /// Before launch and the future: there's no board to play.
    private var isUnavailable: Bool {
        day == .beforeLaunch || day == .future
    }

    private var backgroundStyle: CalendarTileBackground.Style {
        guard result != nil else { return .plain }
        return isPlayedLater ? .later : .onTheDay
    }

    /// The mark in the corner. Each state has a shape of its own, so none depends on colour.
    private var symbol: (name: String, color: Color)? {
        if let result {
            return result.won ? ("checkmark", CalendarPalette.won) : ("xmark", CalendarPalette.lost)
        }
        switch day {
        case .inProgress, .carriedOver:
            return ("ellipsis", CalendarPalette.inProgress)
        case .unplayed:
            return ("play.fill", CalendarPalette.playable)
        default:
            return nil
        }
    }

    private var symbolSize: CGFloat {
        let base: CGFloat = isInProgress ? 10 : 9
        return differentiateWithoutColor ? base + 1 : base
    }

    private var tile: some View {
        ZStack {
            // A day with no board has no tile, only its number, so it's set apart by shape.
            if !isUnavailable {
                CalendarTileBackground(
                    style: backgroundStyle,
                    tint: CalendarPalette.result(result?.won != false),
                    isToday: day == .today
                )
            }

            if onPlay != nil, isHovered {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
            }

            if let number = cell.day {
                Text("\(number)")
                    .font(.system(size: 12, weight: isQuiet ? .regular : .semibold))
                    .monospacedDigit()
                    .foregroundStyle(textColor)
            }

            if let symbol {
                Image(systemName: symbol.name)
                    .font(.system(size: symbolSize, weight: isInProgress ? .heavy : .bold))
                    .foregroundStyle(symbol.color)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(3)
            }
        }
        .frame(height: Self.height)
        .overlay {
            if isSelected {
                selectionRing
            }
        }
        .contentShape(Rectangle())
    }

    /// The selection, drawn just outside the tile: the system focus ring while the grid has
    /// the keyboard, a plain outline otherwise.
    private var selectionRing: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .strokeBorder(
                isFocused ? Color(nsColor: .keyboardFocusIndicatorColor) : Color(nsColor: .secondaryLabelColor),
                lineWidth: isFocused ? 3 : (contrast == .increased ? 2 : 1.5)
            )
            .padding(-3)
            .allowsHitTesting(false)
    }

    /// A day with nothing to report has a lighter number.
    private var isQuiet: Bool {
        result == nil && !isInProgress && day != .today
    }

    private var textColor: Color {
        if isUnavailable {
            return contrast == .increased ? .secondary : Color(nsColor: .tertiaryLabelColor)
        }
        if result != nil || isInProgress || day == .today {
            return .primary
        }
        // A day that's waiting to be played reads as something to click.
        return day == .unplayed ? CalendarPalette.playable : .secondary
    }

    private var helpText: String {
        day == .today ? String(localized: "stats_calendar_today_tile_help") : playHint
    }

    /// What playing the tile does, so the player knows before they do whether the game will
    /// be recorded.
    private var playHint: String {
        switch day?.play {
        case .recorded:
            return String(localized: "stats_calendar_hint_play")
        case .resume:
            let key: String.LocalizationValue = day == .carriedOver
                ? "stats_calendar_hint_continue_on_the_day"
                : "stats_calendar_hint_continue"
            return String(localized: key)
        case .practice:
            return String(localized: "stats_calendar_hint_replay")
        case nil:
            return day == .today ? String(localized: "stats_calendar_today_tile_help") : ""
        }
    }

    private var accessibilityLabel: String {
        guard let date = cell.date, let day else { return "" }
        let dateString = date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: .gmt))

        let key: String.LocalizationValue
        switch day {
        case .beforeLaunch, .future:
            key = "stats_calendar_day_unavailable"
        case .today:
            let state: String.LocalizationValue
            if let todayResult {
                state = todayResult.won ? "stats_calendar_day_won" : "stats_calendar_day_lost"
            } else {
                state = "stats_calendar_day_not_played"
            }
            return String(
                format: String(localized: "stats_calendar_day_today_prefix"),
                String(format: String(localized: state), dateString)
            )
        case .unplayed:
            key = "stats_calendar_day_not_played"
        case .inProgress, .carriedOver:
            key = "stats_calendar_day_in_progress"
        case .playedOnTheDay(let result):
            key = result.won ? "stats_calendar_day_won" : "stats_calendar_day_lost"
        case .playedLater(let result):
            key = result.won ? "stats_calendar_day_won_later" : "stats_calendar_day_lost_later"
        }
        return String(format: String(localized: key), dateString)
    }
}
