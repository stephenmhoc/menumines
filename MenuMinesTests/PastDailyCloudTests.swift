import Foundation
import Testing
@testable import MenuMines

// MARK: - iCloud

@Suite("Past daily iCloud sync", .serialized)
@MainActor
struct PastDailyCloudTests {
    private func makeStore(_ results: [GameResult] = [], past: [GameResult] = []) -> StatsStore {
        UserDefaults.standard.removeObject(forKey: "statsResetAt")
        return StatsStore.forTesting(with: results, pastDailyResults: past)
    }

    private func cleanUp() {
        UserDefaults.standard.removeObject(forKey: "gameResults")
        UserDefaults.standard.removeObject(forKey: "pastDailyResults")
        UserDefaults.standard.removeObject(forKey: "statsResetAt")
    }

    private func sync(_ store: StatsStore, with cloud: InMemoryCloud) {
        DailyResultsCloud(cloud: cloud, stats: store).sync()
    }

    private func results(in cloud: InMemoryCloud, prefix: String) throws -> [GameResult] {
        try cloud.allKeys.filter { $0.hasPrefix(prefix) }
            .compactMap { cloud.data(forKey: $0) }
            .flatMap { try JSONDecoder().decode([GameResult].self, from: $0) }
    }

    @Test("Two Macs converge on the union of the past dailies they've played")
    func testMacsConverge() {
        defer { cleanUp() }
        let cloud = InMemoryCloud()
        let first = makeStore(past: [pastDailyResult(2026_03_01)])
        let second = makeStore(past: [pastDailyResult(2026_04_02, won: false)])

        sync(first, with: cloud)
        sync(second, with: cloud)
        sync(first, with: cloud)

        for store in [first, second] {
            #expect(Set(store.pastDailyResults.map(\.dailySeed)) == [2026_03_01, 2026_04_02])
            #expect(store.pastDailyWins == 1)
            #expect(store.dailyResults.isEmpty)
            #expect(store.longestStreak == 0)
        }
    }

    @Test("Past dailies go under their own keys, one a month, and never into the on-the-day ones")
    func testCloudKeysAreSeparate() throws {
        defer { cleanUp() }
        let cloud = InMemoryCloud()
        let store = makeStore(
            [onTheDayResult(2026_03_01)],
            past: [pastDailyResult(2026_03_02), pastDailyResult(2026_03_09), pastDailyResult(2026_04_02)]
        )

        sync(store, with: cloud)

        #expect(Set(cloud.allKeys) == ["results.202603", "past.202603", "past.202604"])
        #expect(DailyResultsCloud.pastMonthKey(forSeed: 2026_03_02) == "past.202603")

        // The keys a version without past dailies reads hold nothing it can't decode.
        let onTheDay = try results(in: cloud, prefix: DailyResultsCloud.monthKeyPrefix)
        #expect(onTheDay.map(\.dailySeed) == [2026_03_01])
        #expect(onTheDay.allSatisfy { $0.puzzleType == .daily })

        let past = try results(in: cloud, prefix: DailyResultsCloud.pastMonthKeyPrefix)
        #expect(Set(past.map(\.dailySeed)) == [2026_03_02, 2026_03_09, 2026_04_02])
        #expect(past.allSatisfy { $0.puzzleType == .pastDaily })
    }

    @Test("When Macs disagree about a past daily, the first one finished stands on both")
    func testFirstFinishedWinsAcrossMacs() {
        defer { cleanUp() }
        let cloud = InMemoryCloud()
        let early = pastDailyResult(2026_03_01, won: false, at: pastDailyReferenceDate)
        let late = pastDailyResult(2026_03_01, won: true, at: pastDailyReferenceDate.addingTimeInterval(60))
        let first = makeStore(past: [late])
        let second = makeStore(past: [early])

        sync(first, with: cloud)
        sync(second, with: cloud)
        sync(first, with: cloud)

        #expect(first.pastDailyResults == [early])
        #expect(second.pastDailyResults == [early])
    }

    @Test("A day played later on one Mac and on the day on another counts once, as the on-the-day result")
    func testOnTheDayWinsAcrossMacs() {
        defer { cleanUp() }
        let cloud = InMemoryCloud()
        let playedLater = makeStore(past: [pastDailyResult(2026_03_01, won: true)])
        let playedOnTheDay = makeStore([onTheDayResult(2026_03_01, won: false)])

        sync(playedLater, with: cloud)
        sync(playedOnTheDay, with: cloud)
        sync(playedLater, with: cloud)

        for store in [playedLater, playedOnTheDay] {
            #expect(store.dailyResultsBySeed[2026_03_01]?.won == false)
            #expect(store.pastDailyGamesPlayed == 0)
            #expect(store.pastDailyResults.isEmpty)
            #expect(store.dailyGamesPlayed == 1)
            #expect(store.playedDailySeeds == [2026_03_01])
        }
    }

    @Test("Once Macs agree, syncing again writes nothing")
    func testSyncSettles() {
        defer { cleanUp() }
        let cloud = InMemoryCloud()
        let first = makeStore([onTheDayResult(2026_03_01, won: false)], past: [pastDailyResult(2026_03_02)])
        let second = makeStore(
            [onTheDayResult(2026_03_03)],
            past: [pastDailyResult(2026_03_01), pastDailyResult(2026_04_05)]
        )

        for _ in 0..<2 {
            sync(first, with: cloud)
            sync(second, with: cloud)
        }
        let settled = cloud.writeCount

        for _ in 0..<3 {
            sync(first, with: cloud)
            sync(second, with: cloud)
        }

        #expect(cloud.writeCount == settled, "Macs mustn't keep rewriting each other's months")
        #expect(first.pastDailyResults == second.pastDailyResults)
        #expect(first.dailyResults.map(\.dailySeed).sorted() == second.dailyResults.map(\.dailySeed).sorted())
    }

    @Test("A cloud written by a version without past dailies syncs as before")
    func testCloudFromOlderVersion() throws {
        defer { cleanUp() }
        let cloud = InMemoryCloud()
        cloud.set(try JSONEncoder().encode([onTheDayResult(2026_03_01)]), forKey: "results.202603")
        cloud.set(try JSONEncoder().encode([onTheDayResult(2026_01_31)]), forKey: DailyResultsCloud.legacyKey)
        let store = makeStore(past: [pastDailyResult(2026_03_02)])

        sync(store, with: cloud)

        #expect(Set(store.dailyResults.map(\.dailySeed)) == [2026_03_01, 2026_01_31])
        #expect(store.pastDailyResults.map(\.dailySeed) == [2026_03_02])
        #expect(cloud.data(forKey: "past.202603") != nil)
    }

    @Test("Unreadable past-daily data in the cloud is ignored, and on-the-day results still sync")
    func testCorruptPastData() throws {
        defer { cleanUp() }
        let cloud = InMemoryCloud()
        cloud.set(Data("nonsense".utf8), forKey: "past.202603")
        cloud.set(try JSONEncoder().encode([onTheDayResult(2026_03_01)]), forKey: "results.202603")
        let store = makeStore()

        sync(store, with: cloud)

        #expect(store.dailyResults.map(\.dailySeed) == [2026_03_01])
        #expect(store.pastDailyResults.isEmpty)
    }

    @Test("Resetting statistics erases past dailies from the cloud and from other Macs")
    func testResetReachesPastDailies() {
        defer { cleanUp() }
        let cloud = InMemoryCloud()
        let first = makeStore(past: [pastDailyResult(2026_03_01, at: Date().addingTimeInterval(-600))])
        let second = makeStore()
        sync(first, with: cloud)
        sync(second, with: cloud)
        #expect(second.pastDailyGamesPlayed == 1)

        first.reset()
        DailyResultsCloud(cloud: cloud, stats: first).publishReset(at: Date())
        #expect(cloud.allKeys.allSatisfy { !$0.hasPrefix(DailyResultsCloud.pastMonthKeyPrefix) })

        sync(second, with: cloud)

        #expect(second.pastDailyResults.isEmpty)
        let pastKeys = cloud.allKeys.filter { $0.hasPrefix(DailyResultsCloud.pastMonthKeyPrefix) }
        #expect(pastKeys.isEmpty, "And it isn't published back")
    }
}
