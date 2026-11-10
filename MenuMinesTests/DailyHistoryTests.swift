import Foundation
import Testing
@testable import MenuMines

// MARK: - Which days can be played

@Suite("Past daily availability")
struct DailyHistoryTests {
    private let today: Int64 = 2026_11_09

    private func day(
        _ seed: Int64,
        onTheDay: [GameResult] = [],
        later laterResults: [GameResult] = [],
        inProgress: Set<Int64> = []
    ) -> DailyHistory.Day {
        DailyHistory.day(
            forSeed: seed,
            todaySeed: today,
            onTheDay: Dictionary(uniqueKeysWithValues: onTheDay.map { ($0.dailySeed, $0) }),
            later: Dictionary(uniqueKeysWithValues: laterResults.map { ($0.dailySeed, $0) }),
            inProgress: inProgress
        )
    }

    @Test("Launch day is the first day MenuMines was published, 31 January 2026")
    func testLaunchDay() {
        #expect(DailyHistory.launchSeed == 2026_01_31)
        #expect(DailyHistory.launchMonthStart == dateFromSeed(2026_01_01))
    }

    @Test("Days from launch through yesterday can be played, and nothing else")
    func testPlayableRange() {
        #expect(DailyHistory.isPastPuzzleDay(2026_01_31, todaySeed: today), "Launch day itself")
        #expect(DailyHistory.isPastPuzzleDay(2026_02_01, todaySeed: today))
        #expect(DailyHistory.isPastPuzzleDay(2026_11_08, todaySeed: today), "Yesterday")

        #expect(!DailyHistory.isPastPuzzleDay(2026_01_30, todaySeed: today), "The day before launch")
        #expect(!DailyHistory.isPastPuzzleDay(2020_01_01, todaySeed: today))
        #expect(!DailyHistory.isPastPuzzleDay(today, todaySeed: today), "Today is played as today")
        #expect(!DailyHistory.isPastPuzzleDay(2026_11_10, todaySeed: today), "Tomorrow")
    }

    @Test("A seed that isn't a calendar day is never playable")
    func testInvalidSeeds() {
        #expect(!DailyHistory.isPastPuzzleDay(2026_02_31, todaySeed: today))
        #expect(!DailyHistory.isPastPuzzleDay(2026_13_01, todaySeed: today))
        #expect(!DailyHistory.isPastPuzzleDay(2026_05_00, todaySeed: today))
        #expect(!DailyHistory.isPastPuzzleDay(-5, todaySeed: today), "A random puzzle's seed")
        #expect(!DailyHistory.isPastPuzzleDay(0, todaySeed: today))
    }

    @Test("Before launch, today and the future have nothing to play")
    func testUnavailableDays() {
        #expect(day(2026_01_30) == .beforeLaunch)
        #expect(day(2025_12_25) == .beforeLaunch)
        #expect(day(today) == .today)
        #expect(day(2026_11_10) == .future)
        #expect(day(2027_01_01) == .future)

        for unavailable in [DailyHistory.Day.beforeLaunch, .today, .future] {
            #expect(unavailable.play == nil)
        }
    }

    @Test("A result before launch doesn't make that day playable")
    func testResultBeforeLaunchStaysUnavailable() {
        #expect(day(2026_01_30, onTheDay: [onTheDayResult(2026_01_30)]) == .beforeLaunch)
    }

    @Test("A day with no result is played as a recorded past daily")
    func testUnplayedDay() {
        #expect(day(2026_11_08) == .unplayed)
        #expect(day(2026_01_31) == .unplayed)
        #expect(DailyHistory.Day.unplayed.play == .recorded)
    }

    @Test("A day that was started is carried on with")
    func testInProgressDay() {
        #expect(day(2026_11_08, inProgress: [2026_11_08]) == .inProgress)
        #expect(DailyHistory.Day.inProgress.play == .resume)
    }

    @Test("A day with a result, from its own day or later, is an unrecorded replay")
    func testPlayedDays() {
        let onTheDay = onTheDayResult(2026_11_08)
        let playedLater = pastDailyResult(2026_11_07, won: false)

        #expect(day(2026_11_08, onTheDay: [onTheDay]) == .playedOnTheDay(onTheDay))
        #expect(day(2026_11_07, later: [playedLater]) == .playedLater(playedLater))
        #expect(DailyHistory.Day.playedOnTheDay(onTheDay).play == .practice)
        #expect(DailyHistory.Day.playedLater(playedLater).play == .practice)
    }

    @Test("A result outranks saved progress, and the day's own result outranks a later one")
    func testPrecedence() {
        let onTheDay = onTheDayResult(2026_11_08, won: false)
        let playedLater = pastDailyResult(2026_11_08, won: true)

        let both = day(2026_11_08, onTheDay: [onTheDay], later: [playedLater], inProgress: [2026_11_08])
        #expect(both == .playedOnTheDay(onTheDay))
        #expect(day(2026_11_08, later: [playedLater], inProgress: [2026_11_08]) == .playedLater(playedLater))
    }

    @Test("The missed day offered is the most recent one with no result")
    func testMostRecentMissedDay() {
        #expect(DailyHistory.mostRecentMissedSeed(todaySeed: today, played: []) == 2026_11_08)
        #expect(DailyHistory.mostRecentMissedSeed(todaySeed: today, played: [2026_11_08, 2026_11_07]) == 2026_11_06)
        #expect(DailyHistory.mostRecentMissedSeed(todaySeed: today, played: [2026_11_07]) == 2026_11_08)
        #expect(DailyHistory.mostRecentMissedSeed(todaySeed: today, played: [], excluding: 2026_11_08) == 2026_11_07)
    }

    @Test("Looking for a missed day crosses month and year ends by the calendar")
    func testMissedDayAcrossMonths() {
        #expect(DailyHistory.mostRecentMissedSeed(todaySeed: 2026_03_01, played: []) == 2026_02_28)
        #expect(DailyHistory.mostRecentMissedSeed(todaySeed: 2026_03_01, played: [2026_02_28]) == 2026_02_27)
        #expect(DailyHistory.mostRecentMissedSeed(todaySeed: 2027_01_01, played: []) == 2026_12_31)
    }

    @Test("Nothing is offered from before launch")
    func testMissedDayStopsAtLaunch() {
        #expect(DailyHistory.mostRecentMissedSeed(todaySeed: 2026_01_31, played: []) == nil)
        #expect(DailyHistory.mostRecentMissedSeed(todaySeed: 2026_02_01, played: []) == 2026_01_31)
        #expect(DailyHistory.mostRecentMissedSeed(todaySeed: 2026_02_02, played: [2026_02_01, 2026_01_31]) == nil)
        #expect(DailyHistory.mostRecentMissedSeed(todaySeed: 2026_02_01, played: [], excluding: 2026_01_31) == nil)
    }
}
