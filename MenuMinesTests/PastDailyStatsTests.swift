import Foundation
import Testing
@testable import MenuMines

// MARK: - Stats

@Suite("Past daily stats", .serialized)
@MainActor
struct PastDailyStatsTests {
    private func makeStore(_ results: [GameResult] = [], past: [GameResult] = []) -> StatsStore {
        UserDefaults.standard.removeObject(forKey: "statsResetAt")
        return StatsStore.forTesting(with: results, pastDailyResults: past)
    }

    /// The store writes through to UserDefaults, where the app's own store would find it.
    private func cleanUp() {
        UserDefaults.standard.removeObject(forKey: "gameResults")
        UserDefaults.standard.removeObject(forKey: "pastDailyResults")
        UserDefaults.standard.removeObject(forKey: "statsResetAt")
    }

    @Test("A past daily is recorded once per day")
    func testRecordedOncePerDay() {
        defer { cleanUp() }
        let store = makeStore()

        #expect(store.record(pastDailyResult(2026_03_01, won: false)))
        #expect(!store.record(pastDailyResult(2026_03_01, won: true)))
        #expect(store.record(pastDailyResult(2026_03_02, won: true)))

        #expect(store.pastDailyGamesPlayed == 2)
        #expect(store.pastDailyWins == 1)
        #expect(store.pastDailyResultsBySeed[2026_03_01]?.won == false, "The first result stands")
        #expect(store.pastDailyResults.map(\.dailySeed) == [2026_03_02, 2026_03_01])
    }

    @Test("A past daily can't be recorded over a result from the day itself")
    func testNotRecordedOverOnTheDayResult() {
        defer { cleanUp() }
        let store = makeStore([onTheDayResult(2026_03_01, won: false)])

        #expect(!store.record(pastDailyResult(2026_03_01, won: true)))

        #expect(store.pastDailyGamesPlayed == 0)
        #expect(store.storedPastDailyResults.isEmpty)
        #expect(store.dailyResultsBySeed[2026_03_01]?.won == false)
    }

    @Test("Replays are never recorded")
    func testPracticeIsNeverRecorded() {
        defer { cleanUp() }
        let store = makeStore()
        let replay = GameResult(won: true, elapsedTime: 5, dailySeed: 2026_03_01, puzzleType: .practice)

        #expect(!store.record(replay))
        #expect(store.results.isEmpty)
        #expect(store.storedPastDailyResults.isEmpty)
    }

    @Test("Past dailies never reach results, so nothing computed from results can count them")
    func testKeptApartFromEverythingElse() {
        defer { cleanUp() }
        let store = makeStore([onTheDayResult(2026_03_01), onTheDayResult(2026_03_03)])
        store.record(pastDailyResult(2026_03_02))
        store.record(pastDailyResult(2026_03_04, won: false))

        #expect(store.results.allSatisfy { $0.puzzleType != .pastDaily })
        #expect(store.gamesPlayed == 2)
        #expect(store.wins == 2)
        #expect(store.winRate == 100)
        #expect(store.bestTime == 60, "A past daily's time isn't a best time")
        #expect(store.dailyGamesPlayed == 2)
        #expect(store.dailyWins == 2)
        #expect(store.dailyWinRate == 100)
        #expect(Set(store.dailyResultsBySeed.keys) == [2026_03_01, 2026_03_03])
        #expect(store.recentDailyResults.map(\.dailySeed) == [2026_03_03, 2026_03_01])
    }

    @Test("A past daily between two played days doesn't join them into a streak")
    func testStreaksIgnorePastDailies() throws {
        defer { cleanUp() }
        let store = makeStore(
            [onTheDayResult(2026_03_01), onTheDayResult(2026_03_03)],
            past: [pastDailyResult(2026_03_02), pastDailyResult(2026_03_04)]
        )
        let march3 = try #require(dateFromSeed(2026_03_03))
        let march4 = try #require(dateFromSeed(2026_03_04))
        let march5 = try #require(dateFromSeed(2026_03_05))

        #expect(store.longestStreak == 1)
        #expect(store.currentStreak(asOf: march3) == 1)
        #expect(store.currentStreak(asOf: march4) == 1, "The 3rd still counts through the 4th")
        #expect(store.currentStreak(asOf: march5) == 0, "A past daily for the 4th doesn't keep it alive")
        #expect(store.dailyCompletionRate(asOf: march4) == 50, "Two of four days were played on the day")
    }

    @Test("With both kinds of result for a day, the one from the day stands and the day counts once")
    func testOnTheDayResultTakesPrecedence() {
        defer { cleanUp() }
        let store = makeStore(
            [onTheDayResult(2026_03_01, won: false)],
            past: [pastDailyResult(2026_03_01, won: true), pastDailyResult(2026_03_02, won: true)]
        )

        #expect(store.pastDailyResults.map(\.dailySeed) == [2026_03_02])
        #expect(store.pastDailyResultsBySeed[2026_03_01] == nil)
        #expect(store.pastDailyGamesPlayed == 1)
        #expect(store.pastDailyWins == 1)
        #expect(store.dailyGamesPlayed == 1)
        #expect(store.dailyResultsBySeed[2026_03_01]?.won == false)
        #expect(store.playedDailySeeds == [2026_03_01, 2026_03_02])
        let counted = store.dailyGamesPlayed + store.pastDailyGamesPlayed
        #expect(counted == store.playedDailySeeds.count, "No day is counted twice")
    }

    @Test("An on-the-day result that arrives by sync takes over a day played later")
    func testPrecedenceAfterSyncMerge() {
        defer { cleanUp() }
        let store = makeStore()
        store.record(pastDailyResult(2026_03_01, won: true))
        #expect(store.pastDailyGamesPlayed == 1)

        #expect(store.merge(dailyResults: [onTheDayResult(2026_03_01, won: false)]))

        #expect(store.pastDailyGamesPlayed == 0)
        #expect(store.pastDailyWins == 0)
        #expect(store.pastDailyResults.isEmpty)
        #expect(store.dailyGamesPlayed == 1)
        #expect(store.dailyResultsBySeed[2026_03_01]?.won == false)
        #expect(store.playedDailySeeds == [2026_03_01])
        #expect(store.hasDailyResult(forSeed: 2026_03_01))
        #expect(store.longestStreak == 1, "It counts as the day's own result, which it is")
    }

    @Test("Merging past dailies keeps the first one finished, whichever order they arrive in")
    func testMergeKeepsFirstFinished() {
        defer { cleanUp() }
        let early = pastDailyResult(2026_03_01, won: false, at: pastDailyReferenceDate)
        let late = pastDailyResult(2026_03_01, won: true, at: pastDailyReferenceDate.addingTimeInterval(60))

        let first = makeStore()
        #expect(first.merge(pastDailyResults: [late]))
        #expect(first.merge(pastDailyResults: [early]))
        #expect(!first.merge(pastDailyResults: [late]), "Nothing changes the second time")

        let second = makeStore()
        #expect(second.merge(pastDailyResults: [early, late]))

        #expect(first.pastDailyResults == [early])
        #expect(second.pastDailyResults == [early])
    }

    @Test("Merging past dailies takes nothing that isn't one")
    func testMergeIgnoresOtherTypes() {
        defer { cleanUp() }
        let store = makeStore()

        #expect(!store.merge(pastDailyResults: [onTheDayResult(2026_03_01)]))
        #expect(store.storedPastDailyResults.isEmpty)

        #expect(!store.merge(dailyResults: [pastDailyResult(2026_03_01)]))
        #expect(store.results.isEmpty, "A past daily offered as an on-the-day result is refused")
    }

    @Test("Resetting statistics clears past dailies, and older ones don't come back")
    func testResetClearsPastDailies() {
        defer { cleanUp() }
        let store = makeStore([onTheDayResult(2026_03_01)], past: [pastDailyResult(2026_03_02)])

        store.reset()

        #expect(store.results.isEmpty)
        #expect(store.storedPastDailyResults.isEmpty)
        #expect(!store.merge(pastDailyResults: [pastDailyResult(2026_03_02)]), "From before the reset")
        #expect(store.merge(pastDailyResults: [pastDailyResult(2026_03_02, at: Date().addingTimeInterval(60))]))
    }

    @Test("A reset from another Mac removes the past dailies it covers")
    func testAppliedResetCoversPastDailies() {
        defer { cleanUp() }
        let before = pastDailyResult(2026_03_02, at: pastDailyReferenceDate)
        let after = pastDailyResult(2026_03_03, at: pastDailyReferenceDate.addingTimeInterval(120))
        let store = makeStore(past: [before, after])

        #expect(store.applyReset(at: pastDailyReferenceDate.addingTimeInterval(60)))

        #expect(store.pastDailyResults == [after])
    }

    @Test("Past dailies are written to their own key and read back")
    func testPersistence() throws {
        defer { cleanUp() }
        let store = makeStore([onTheDayResult(2026_03_01)])
        store.record(pastDailyResult(2026_03_02, won: false))

        let pastData = try #require(UserDefaults.standard.data(forKey: "pastDailyResults"))
        let stored = try JSONDecoder().decode([GameResult].self, from: pastData)
        #expect(stored.map(\.dailySeed) == [2026_03_02])
        #expect(stored.first?.puzzleType == .pastDaily)

        let resultsData = UserDefaults.standard.data(forKey: "gameResults") ?? Data()
        #expect(String(data: resultsData, encoding: .utf8)?.contains("pastDaily") != true)
    }

    @Test("Tracking is dated from the earliest result of either kind")
    func testTrackedSince() {
        defer { cleanUp() }
        let store = makeStore(
            [onTheDayResult(2026_03_05, at: pastDailyReferenceDate.addingTimeInterval(500))],
            past: [pastDailyResult(2026_03_01, at: pastDailyReferenceDate)]
        )
        #expect(store.trackedSince == pastDailyReferenceDate)
    }
}
