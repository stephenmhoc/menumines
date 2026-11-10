import Foundation
import Testing
@testable import MenuMines

@Suite("Daily History keyboard cursor")
struct DailyHistoryCursorTests {
    @Test("Starts on today")
    func startsOnToday() {
        let cursor = DailyHistoryCursor(todaySeed: 2026_03_15)
        #expect(cursor.seed == 2026_03_15)
        #expect(cursor.isOnToday)
    }

    @Test("Arrows cross into the next and previous month")
    func arrowsCrossMonths() {
        var cursor = DailyHistoryCursor(todaySeed: 2026_03_15, selectedSeed: 2026_03_01)
        cursor.move(days: -1)
        #expect(cursor.seed == 2026_02_28)
        cursor.move(days: 7)
        #expect(cursor.seed == 2026_03_07)
        cursor.move(days: -7)
        #expect(cursor.seed == 2026_02_28)
    }

    @Test("It stops at launch day and at today")
    func staysInRange() {
        var cursor = DailyHistoryCursor(todaySeed: 2026_03_15)
        cursor.move(days: 1)
        #expect(cursor.seed == 2026_03_15)
        cursor.move(days: 7)
        #expect(cursor.seed == 2026_03_15)
        #expect(!cursor.canMoveToNextMonth)

        cursor = DailyHistoryCursor(todaySeed: 2026_03_15, selectedSeed: DailyHistory.launchSeed)
        cursor.move(days: -1)
        #expect(cursor.seed == DailyHistory.launchSeed)
        #expect(!cursor.canMoveToPreviousMonth)

        // A day that can't be picked is ignored, and one out of range is brought into it.
        cursor = DailyHistoryCursor(todaySeed: 2026_03_15, selectedSeed: 2025_06_01)
        #expect(cursor.seed == DailyHistory.launchSeed)
        if let future = dateFromSeed(2026_03_20) {
            cursor.select(future)
        }
        #expect(cursor.seed == DailyHistory.launchSeed)
    }

    @Test("Page Up and Page Down change month, keeping the day where they can")
    func pagesMonths() {
        var cursor = DailyHistoryCursor(todaySeed: 2026_05_10, selectedSeed: 2026_03_31)
        cursor.move(months: -1)
        #expect(cursor.seed == 2026_02_28)
        cursor.move(months: 1)
        #expect(cursor.seed == 2026_03_28)
        cursor.move(months: 2)
        #expect(cursor.seed == 2026_05_10, "Today, not a day that hasn't come yet")
        cursor.move(months: -12)
        #expect(cursor.seed == DailyHistory.launchSeed)
    }

    @Test("Home goes to today, and the month follows the selection")
    func homeAndMonth() {
        var cursor = DailyHistoryCursor(todaySeed: 2026_05_10, selectedSeed: 2026_03_31)
        #expect(cursor.monthStart == dateFromSeed(2026_03_01))
        cursor.goToToday()
        #expect(cursor.seed == 2026_05_10)
        #expect(cursor.monthStart == dateFromSeed(2026_05_01))
    }

    @Test("A new day moves a selection that was on today, and leaves one elsewhere alone")
    func followsNewDay() {
        var cursor = DailyHistoryCursor(todaySeed: 2026_05_10)
        cursor.updateToday(2026_05_11)
        #expect(cursor.seed == 2026_05_11)

        cursor = DailyHistoryCursor(todaySeed: 2026_05_10, selectedSeed: 2026_05_02)
        cursor.updateToday(2026_05_11)
        #expect(cursor.seed == 2026_05_02)
    }

    @Test("The selected day is read with its date and how it went")
    func selectedDayIsSpoken() throws {
        let date = try #require(dateFromSeed(2026_03_10))
        let dateString = date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: .gmt))
        let won = GameResult(won: true, elapsedTime: 60, dailySeed: 2026_03_10)

        #expect(DailyHistory.Day.playedOnTheDay(won).spokenLabel(on: date, todayResult: nil)
            == String(localized: "stats_calendar_day_won \(dateString)"))
        #expect(DailyHistory.Day.unplayed.spokenLabel(on: date, todayResult: nil)
            == String(localized: "stats_calendar_day_not_played \(dateString)"))
        #expect(DailyHistory.Day.unplayed.spokenLabel(on: date, todayResult: nil).contains("2026"))
    }

    @Test("Moving quickly through the days says only the one the selection rests on")
    @MainActor
    func announcementsSettle() async throws {
        let announcer = AccessibilityAnnouncer()
        var said: [String] = []
        announcer.post = { said.append($0) }

        announcer.announceWhenSettled("March 1")
        announcer.announceWhenSettled("March 2")
        announcer.announceWhenSettled("March 3")
        try await Task.sleep(for: .milliseconds(400))

        #expect(said == ["March 3"])
    }
}
