import Foundation
import Testing
@testable import MenuMines

@Suite("Daily Completion Tests", .serialized)
struct DailyCompletionTests {

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    private func makeUTCDate(year: Int, month: Int, day: Int) -> Date {
        utcCalendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: 12
        )) ?? Date.distantPast
    }

    @Test("Daily puzzle is incomplete by default")
    func testDailyPuzzleIncompleteByDefault() {
        // Clear any existing completion
        UserDefaults.standard.removeObject(forKey: "dailyCompletionSeed")

        let date = makeUTCDate(year: 2026, month: 1, day: 15)

        #expect(!isDailyPuzzleComplete(forSeed: seedFromDate(date)))
    }

    @Test("Mark daily puzzle complete sets correct seed")
    func testMarkDailyPuzzleComplete() {
        // Clear any existing completion
        UserDefaults.standard.removeObject(forKey: "dailyCompletionSeed")

        let date = makeUTCDate(year: 2026, month: 1, day: 15)

        markDailyPuzzleComplete(forSeed: seedFromDate(date))

        #expect(isDailyPuzzleComplete(forSeed: seedFromDate(date)))
    }

    @Test("Daily puzzle completion is date-specific")
    func testDailyPuzzleCompletionIsDateSpecific() {
        // Clear any existing completion
        UserDefaults.standard.removeObject(forKey: "dailyCompletionSeed")

        // Mark yesterday as complete
        let today = makeUTCDate(year: 2026, month: 1, day: 15)
        let yesterday = utcCalendar.date(byAdding: .day, value: -1, to: today) ?? Date.distantPast
        markDailyPuzzleComplete(forSeed: seedFromDate(yesterday))

        // Today should still be incomplete
        #expect(!isDailyPuzzleComplete(forSeed: seedFromDate(today)))

        // Yesterday should be complete
        #expect(isDailyPuzzleComplete(forSeed: seedFromDate(yesterday)))
    }

    @Test("Different days have different completion states")
    func testDifferentDaysHaveDifferentCompletionStates() {
        // Clear any existing completion
        UserDefaults.standard.removeObject(forKey: "dailyCompletionSeed")

        let today = makeUTCDate(year: 2026, month: 1, day: 15)
        let tomorrow = utcCalendar.date(byAdding: .day, value: 1, to: today) ?? Date.distantPast

        markDailyPuzzleComplete(forSeed: seedFromDate(today))

        #expect(isDailyPuzzleComplete(forSeed: seedFromDate(today)))
        #expect(!isDailyPuzzleComplete(forSeed: seedFromDate(tomorrow)))
    }
}
