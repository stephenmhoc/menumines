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
}
