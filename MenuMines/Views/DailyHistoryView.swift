import AppKit
import SwiftUI

// MARK: - Cursor

/// The day selected in Daily History, which decides the month on show.
///
/// It stays between launch day and today, the days there's a board for (today's is played
/// from the menu bar, but it can still be looked at). Moving it by days crosses into the
/// next or previous month, and moving it by months keeps the day of the month where it can.
struct DailyHistoryCursor: Equatable {
    private(set) var day: Date
    private(set) var first: Date
    private(set) var last: Date

    init(todaySeed: Int64, selectedSeed: Int64? = nil) {
        let first = dateFromSeed(DailyHistory.launchSeed) ?? .distantPast
        let last = max(dateFromSeed(todaySeed) ?? first, first)
        self.first = first
        self.last = last
        let wanted = selectedSeed.flatMap(dateFromSeed) ?? last
        day = min(max(wanted, first), last)
    }

    private static var calendar: Calendar { .utc }

    var seed: Int64 { seedFromDate(day) }
    var todaySeed: Int64 { seedFromDate(last) }

    /// The first of the selected day's month.
    var monthStart: Date {
        Self.monthStart(of: day)
    }

    var canMoveToPreviousMonth: Bool {
        monthStart > Self.monthStart(of: first)
    }

    var canMoveToNextMonth: Bool {
        monthStart < Self.monthStart(of: last)
    }

    var isOnToday: Bool { day == last }

    mutating func move(days: Int) {
        guard let moved = Self.calendar.date(byAdding: .day, value: days, to: day) else { return }
        day = min(max(moved, first), last)
    }

    mutating func move(months: Int) {
        guard let moved = Self.calendar.date(byAdding: .month, value: months, to: day) else { return }
        day = min(max(moved, first), last)
    }

    mutating func goToToday() {
        day = last
    }

    /// Selects a day, if it's one there's a board for.
    mutating func select(_ date: Date) {
        guard date >= first, date <= last else { return }
        day = date
    }

    /// Follows a change of day while the window is open, keeping the selection where it was
    /// unless it was on today.
    mutating func updateToday(_ todaySeed: Int64) {
        let wasOnToday = isOnToday
        self = DailyHistoryCursor(todaySeed: todaySeed, selectedSeed: wasOnToday ? nil : seed)
    }

    private static func monthStart(of date: Date) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
    }
}

// MARK: - Calendar

/// A month of puzzle days. It shows how each one went, and it's where a past day is picked
/// to play: a day with no result as a recorded past daily, any other as a replay.
///
/// The grid is one control: click or arrow to a day, and its result and what playing it
/// means show underneath with a Play, Continue or Replay button. Double-click, Return or
/// Space plays it. Page Up and Page Down change month, Home goes to today. VoiceOver reaches
/// each day on its own, and activating one plays it.
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

    @State private var cursor: DailyHistoryCursor
    @FocusState private var isGridFocused: Bool

    static let rows = 6
    static let spacing: CGFloat = 6

    init(
        todaySeed: Int64,
        onTheDay: [Int64: GameResult],
        later: [Int64: GameResult],
        inProgress: Set<Int64>,
        carriedOver: Int64?,
        onPlay: @escaping (Int64) -> Void
    ) {
        self.todaySeed = todaySeed
        self.onTheDay = onTheDay
        self.later = later
        self.inProgress = inProgress
        self.carriedOver = carriedOver
        self.onPlay = onPlay
        _cursor = State(initialValue: DailyHistoryCursor(todaySeed: todaySeed))
    }

    /// Each tile is a puzzle, and puzzles are UTC days. Laying the month out in the player's
    /// time zone would put a result on the wrong tile and replay the wrong board.
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        calendar.locale = .current
        calendar.firstWeekday = Calendar.current.firstWeekday
        return calendar
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            weekdayRow
            grid
            detail
            CalendarLegend()
            Text(String(localized: "stats_calendar_footnote"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onChange(of: todaySeed) { _, newValue in
            cursor.updateToday(newValue)
        }
        .onChange(of: cursor.monthStart) {
            // Paging is silent otherwise, since the month title isn't what has focus.
            AccessibilityNotification.Announcement(monthTitle).post()
        }
        .onAppear {
            // On the next turn, once the grid is in the window and can take focus.
            Task { @MainActor in isGridFocused = true }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Text(monthTitle)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            Spacer()

            Button(String(localized: "stats_calendar_today")) {
                cursor.goToToday()
            }
            .disabled(cursor.isOnToday)
            .help(String(localized: "stats_calendar_today_help"))
            .accessibilityHint(String(localized: "stats_calendar_today_hint"))

            ControlGroup {
                Button {
                    cursor.move(months: -1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(!cursor.canMoveToPreviousMonth)
                .help(String(localized: cursor.canMoveToPreviousMonth
                    ? "stats_calendar_previous_month"
                    : "stats_calendar_first_month_help"))
                .accessibilityLabel(String(localized: "stats_calendar_previous_month"))

                Button {
                    cursor.move(months: 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(!cursor.canMoveToNextMonth)
                .help(String(localized: "stats_calendar_next_month"))
                .accessibilityLabel(String(localized: "stats_calendar_next_month"))
            }
            .fixedSize()
        }
    }

    private var monthTitle: String {
        cursor.monthStart.formatted(Date.FormatStyle(timeZone: .gmt).month(.wide).year())
    }

    // MARK: Weekdays

    private var weekdayRow: some View {
        let short = Self.weekdaySymbols(\.veryShortStandaloneWeekdaySymbols)
        let full = Self.weekdaySymbols(\.standaloneWeekdaySymbols)
        return HStack(spacing: Self.spacing) {
            ForEach(short.indices, id: \.self) { index in
                Text(short[index])
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(index < full.count ? full[index] : short[index])
            }
        }
    }

    /// The week's day names, starting on the player's first weekday.
    private static func weekdaySymbols(_ keyPath: KeyPath<DateFormatter, [String]?>) -> [String] {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = .current
        let symbols = formatter[keyPath: keyPath] ?? []
        guard symbols.count == 7 else { return symbols }

        let firstIndex = calendar.firstWeekday - 1
        return Array(symbols[firstIndex...]) + Array(symbols[..<firstIndex])
    }

    // MARK: Grid

    /// Six weeks, always, so the calendar is the same height whichever month it shows.
    private var cells: [CalendarCell] {
        let calendar = Self.calendar
        let monthStart = cursor.monthStart
        let firstWeekday = calendar.component(.weekday, from: monthStart)
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7
        let dayCount = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 0

        return (0..<(Self.rows * 7)).map { index in
            let day = index - leading + 1
            guard day >= 1, day <= dayCount,
                  let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) else {
                return CalendarCell(id: "empty-\(index)", date: nil, day: nil)
            }
            return CalendarCell(id: "day-\(day)", date: date, day: day)
        }
    }

    private var grid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: Self.spacing), count: 7),
            spacing: Self.spacing
        ) {
            ForEach(cells) { cell in
                tile(for: cell)
            }
        }
        .focusable()
        .focused($isGridFocused)
        .focusEffectDisabled()
        .onKeyPress(phases: [.down, .repeat], action: handleKey)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "stats_calendar_month_accessibility \(monthTitle)"))
    }

    @ViewBuilder
    private func tile(for cell: CalendarCell) -> some View {
        let day = day(for: cell)
        let seed = cell.date.map(seedFromDate)
        let isSelected = seed != nil && seed == cursor.seed
        CalendarDayCell(
            cell: cell,
            day: day,
            todayResult: onTheDay[todaySeed],
            isSelected: isSelected,
            isFocused: isSelected && isGridFocused,
            onPlay: seed.flatMap { seed in day?.play == nil ? nil : { onPlay(seed) } }
        )
        .onTapGesture(count: 2) {
            if let date = cell.date {
                cursor.select(date)
                playSelected()
            }
        }
        .simultaneousGesture(TapGesture().onEnded {
            if let date = cell.date {
                cursor.select(date)
                isGridFocused = true
            }
        })
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        switch press.key {
        case .leftArrow:
            cursor.move(days: -1)
        case .rightArrow:
            cursor.move(days: 1)
        case .upArrow:
            cursor.move(days: -7)
        case .downArrow:
            cursor.move(days: 7)
        case .pageUp:
            cursor.move(months: -1)
        case .pageDown:
            cursor.move(months: 1)
        case .home:
            cursor.goToToday()
        case .return, .space:
            playSelected()
        default:
            return .ignored
        }
        return .handled
    }

    private func day(for cell: CalendarCell) -> DailyHistory.Day? {
        guard let date = cell.date else { return nil }
        return day(forSeed: seedFromDate(date))
    }

    private func day(forSeed seed: Int64) -> DailyHistory.Day {
        DailyHistory.day(
            forSeed: seed,
            todaySeed: todaySeed,
            onTheDay: onTheDay,
            later: later,
            inProgress: inProgress,
            carriedOver: carriedOver
        )
    }

    /// Plays the selected day, if it's one that can be played from here. Today is the ranked
    /// puzzle and is played from the menu bar, and there's no board before launch.
    private func playSelected() {
        guard day(forSeed: cursor.seed).play != nil else { return }
        onPlay(cursor.seed)
    }

    // MARK: Detail

    /// The selected day: its date, how it went, what playing it means, and the button.
    private var detail: some View {
        let selected = day(forSeed: cursor.seed)
        let description = DayDescription(day: selected, todayResult: onTheDay[todaySeed])
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(cursor.day.formatted(Date.FormatStyle(date: .complete, time: .omitted, timeZone: .gmt)))
                    .font(.subheadline.weight(.semibold))
                Text(description.shown)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(description.spoken)
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 0)

            if let action = selected.play {
                Button(action.buttonTitle) {
                    playSelected()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .frame(minHeight: 44)
    }
}
