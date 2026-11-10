import SwiftUI

// MARK: - Daily Completion Calendar

/// A month of puzzle days. It shows how each one went, and it's where a past day is picked
/// to play: a day with no result as a recorded past daily, any other as a replay.
struct DailyCompletionCalendarView: View {
    let todaySeed: Int64
    /// Results from the day itself.
    let onTheDay: [Int64: GameResult]
    /// Results from past dailies, for days with no on-the-day result.
    let later: [Int64: GameResult]
    /// Days with a past daily started and not finished.
    let inProgress: Set<Int64>
    /// The day of a daily started on that day and still under way, if there is one.
    let carriedOver: Int64?
    let onPlay: (Int64) -> Void

    @State private var displayedMonth = Self.currentMonthStart()

    /// Each tile is a puzzle, and puzzles are UTC days. Laying the month out in the player's
    /// time zone would put a result on the wrong tile and replay the wrong board.
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        calendar.locale = .current
        calendar.firstWeekday = Calendar.current.firstWeekday
        return calendar
    }

    private static func currentMonthStart() -> Date {
        let calendar = Self.calendar
        let now = Date()
        let components = calendar.dateComponents([.year, .month], from: now)
        return calendar.date(from: components) ?? now
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(String(localized: "stats_calendar_title"))
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                Button(String(localized: "stats_calendar_today")) {
                    displayedMonth = Self.currentMonthStart()
                }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .disabled(isShowingCurrentOrFutureMonth)
                    .accessibilityLabel(String(localized: "stats_calendar_today_accessibility"))

                Button {
                    moveMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)
                .disabled(isShowingLaunchMonthOrEarlier)
                .help(String(localized: isShowingLaunchMonthOrEarlier
                    ? "stats_calendar_first_month_help"
                    : "stats_calendar_previous_month"))
                .accessibilityLabel(String(localized: "stats_calendar_previous_month"))

                Button {
                    moveMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.borderless)
                .disabled(isShowingCurrentOrFutureMonth)
                .accessibilityLabel(String(localized: "stats_calendar_next_month"))
            }

            Text(monthTitle)
                .font(.subheadline)
                .fontWeight(.medium)
                .accessibilityLabel(String(format: String(localized: "stats_calendar_month_accessibility"), monthTitle))

            HStack(spacing: 6) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(calendarCells) { cell in
                    CalendarDayCell(
                        cell: cell,
                        day: day(for: cell),
                        todayResult: onTheDay[todaySeed],
                        onPlay: playAction(for: cell)
                    )
                }
            }

            CalendarLegend()

            Text(String(localized: "stats_calendar_replay_hint"))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var monthTitle: String {
        displayedMonth.formatted(
            Date.FormatStyle(timeZone: .gmt).month(.wide).year()
        )
    }

    private var weekdaySymbols: [String] {
        let formatter = DateFormatter()
        formatter.calendar = Self.calendar
        formatter.locale = .current
        let symbols = formatter.veryShortWeekdaySymbols ?? []
        guard symbols.count == 7 else { return symbols }

        let firstIndex = Self.calendar.firstWeekday - 1
        return Array(symbols[firstIndex...]) + Array(symbols[..<firstIndex])
    }

    private var isShowingCurrentOrFutureMonth: Bool {
        Self.calendar.compare(displayedMonth, to: Self.currentMonthStart(), toGranularity: .month) != .orderedAscending
    }

    /// There are no puzzles before launch, so there's nothing to page back to.
    private var isShowingLaunchMonthOrEarlier: Bool {
        let order = Self.calendar.compare(displayedMonth, to: DailyHistory.launchMonthStart, toGranularity: .month)
        return order != .orderedDescending
    }

    private var calendarCells: [CalendarCell] {
        let calendar = Self.calendar
        guard let dayRange = calendar.range(of: .day, in: .month, for: displayedMonth) else {
            return []
        }

        let firstWeekday = calendar.component(.weekday, from: displayedMonth)
        let leadingEmptyCells = (firstWeekday - calendar.firstWeekday + 7) % 7
        var cells = (0..<leadingEmptyCells).map { CalendarCell(id: "empty-\($0)", date: nil, day: nil) }

        for day in dayRange {
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: displayedMonth) else { continue }
            cells.append(CalendarCell(id: "day-\(day)", date: date, day: day))
        }

        return cells
    }

    private func day(for cell: CalendarCell) -> DailyHistory.Day? {
        guard let date = cell.date else { return nil }
        return DailyHistory.day(
            forSeed: seedFromDate(date),
            todaySeed: todaySeed,
            onTheDay: onTheDay,
            later: later,
            inProgress: inProgress,
            carriedOver: carriedOver
        )
    }

    /// Returns an action only for days that can be played from here. Today is the ranked
    /// puzzle and is played as itself, future days have no board yet, and there was no
    /// puzzle before launch.
    private func playAction(for cell: CalendarCell) -> (() -> Void)? {
        guard let date = cell.date, day(for: cell)?.play != nil else { return nil }

        let seed = seedFromDate(date)
        return { onPlay(seed) }
    }

    private func moveMonth(by value: Int) {
        guard let month = Self.calendar.date(byAdding: .month, value: value, to: displayedMonth) else { return }
        displayedMonth = max(month, DailyHistory.launchMonthStart)
    }
}

private struct CalendarCell: Identifiable {
    let id: String
    let date: Date?
    let day: Int?
}

/// Says what the tiles' marks mean. The words carry it, so it reads the same to VoiceOver.
private struct CalendarLegend: View {
    var body: some View {
        HStack(spacing: 8) {
            entry(String(localized: "stats_calendar_legend_on_the_day")) {
                CalendarTileBackground(style: .onTheDay, tint: .accentColor)
            }
            entry(String(localized: "stats_calendar_legend_later")) {
                CalendarTileBackground(style: .later, tint: .accentColor)
            }
            entry(String(localized: "stats_calendar_legend_in_progress")) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(Color.orange)
            }
            entry(String(localized: "stats_calendar_legend_not_played")) {
                Image(systemName: "play.fill")
                    .font(.system(size: 6, weight: .bold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func entry(_ text: String, @ViewBuilder swatch: () -> some View) -> some View {
        HStack(spacing: 4) {
            swatch()
                .frame(width: 12, height: 10)
                .accessibilityHidden(true)
            Text(text)
                .lineLimit(1)
        }
    }
}

/// A tile's fill and outline. A result from the day itself is filled with a solid outline,
/// and one from later is hollow with a dashed outline, so they differ by more than color.
private struct CalendarTileBackground: View {
    enum Style {
        case plain, onTheDay, later
    }

    let style: Style
    var tint: Color = .accentColor
    var isToday = false

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(fillColor)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(borderColor, style: strokeStyle)
            )
    }

    private var fillColor: Color {
        style == .onTheDay ? tint.opacity(0.26) : Color(nsColor: .controlBackgroundColor)
    }

    private var borderColor: Color {
        if isToday {
            return Color.accentColor
        }
        switch style {
        case .plain:
            return Color(nsColor: .separatorColor).opacity(0.7)
        case .onTheDay:
            return tint.opacity(0.6)
        case .later:
            return tint.opacity(0.85)
        }
    }

    private var strokeStyle: StrokeStyle {
        if isToday {
            return StrokeStyle(lineWidth: 2)
        }
        return style == .later ? StrokeStyle(lineWidth: 1.5, dash: [3, 2]) : StrokeStyle(lineWidth: 1)
    }
}

private struct CalendarDayCell: View {
    let cell: CalendarCell
    /// Nil for the blank tiles before the 1st.
    let day: DailyHistory.Day?
    /// Today's tile shows how today went, though it can't be played from here.
    let todayResult: GameResult?
    let onPlay: (() -> Void)?

    @State private var isHovered = false

    var body: some View {
        if let onPlay {
            Button(action: onPlay) { tile }
                .buttonStyle(.plain)
                .onHover { isHovered = $0 }
                .help(playHint)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityHint(playHint)
                .accessibilityAddTraits(.isButton)
        } else {
            tile
                .accessibilityLabel(accessibilityLabel)
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

    /// The mark in the corner. Each state has a shape of its own, so none depends on color.
    private var symbol: (name: String, color: Color)? {
        if let result {
            return result.won ? ("checkmark", .accentColor) : ("xmark", .red)
        }
        switch day {
        case .inProgress, .carriedOver:
            return ("ellipsis", .orange)
        case .unplayed:
            return ("play.fill", .accentColor)
        default:
            return nil
        }
    }

    private var tile: some View {
        ZStack {
            CalendarTileBackground(
                style: backgroundStyle,
                tint: result?.won == false ? .red : .accentColor,
                isToday: day == .today
            )

            if onPlay != nil, isHovered {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(0.08))
            }

            if let number = cell.day {
                Text("\(number)")
                    .font(.caption2)
                    .fontWeight(result == nil && !isInProgress ? .regular : .semibold)
                    .monospacedDigit()
                    .foregroundStyle(textColor)
            }

            if let symbol {
                Image(systemName: symbol.name)
                    .font(.system(size: isInProgress ? 8 : 6, weight: isInProgress ? .heavy : .bold))
                    .foregroundStyle(symbol.color)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(2.5)
            }
        }
        .frame(height: 26)
        .opacity(isUnavailable ? 0.45 : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityHidden(cell.date == nil)
    }

    private var textColor: Color {
        if result != nil || isInProgress {
            return .primary
        }
        // A day that's waiting to be played reads as something to click.
        return day == .unplayed ? .accentColor : .secondary
    }

    /// What clicking the tile does, so the player knows before they click whether the game
    /// will be recorded.
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
            return ""
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
