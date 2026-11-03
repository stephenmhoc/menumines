import Foundation
import Testing
@testable import MenuMines

/// A cloud to sync against, kept in memory.
private final class FakeCloud: CloudKeyValueStoring {
    var values: [String: Any] = [:]

    func data(forKey key: String) -> Data? { values[key] as? Data }
    func set(_ data: Data?, forKey key: String) { values[key] = data }
    func double(forKey key: String) -> Double { values[key] as? Double ?? 0 }
    func set(_ value: Double, forKey key: String) { values[key] = value }
    func removeObject(forKey key: String) { values[key] = nil }
    var allKeys: [String] { Array(values.keys) }
    func synchronize() -> Bool { true }
}

private func daily(_ seed: Int64, won: Bool = true, at date: Date = Date(timeIntervalSinceReferenceDate: 1_000)) -> GameResult {
    GameResult(won: won, elapsedTime: 60, dailySeed: seed, completedAt: date, puzzleType: .daily)
}

private func encoded(_ results: [GameResult]) throws -> Data {
    try JSONEncoder().encode(results)
}

/// Serialized because these share UserDefaults with each other.
@Suite("Daily game lifecycle", .serialized)
struct DailyLifecycleTests {
    private func expectNoSnapshots() {
        #expect(GameSnapshot.loadAnyDay() == nil)
    }

    /// Plays one safe move on a fresh daily, leaving the game in progress.
    private func startedDaily(seed: Int64) throws -> GameState {
        let state = GameState(board: Board(dailySeed: seed), dailySeed: seed, puzzleType: .daily)
        let cell = try #require(hiddenSafeCellThatLeavesGameOpen(in: state.board))
        state.reveal(row: cell.row, col: cell.col)
        try #require(state.status == .playing)
        return state
    }

    private func hiddenSafeCellThatLeavesGameOpen(in board: Board) -> (row: Int, col: Int)? {
        for row in 0..<Board.rows {
            for col in 0..<Board.cols {
                guard case .hidden = board.cells[row][col].state, !board.cells[row][col].hasMine else { continue }
                return (row, col)
            }
        }
        return nil
    }

    @Test("A fresh launch deals the same board as everyone else", arguments: [false, true])
    func testFreshLaunchBoardIsCanonical(continuousPlay: Bool) {
        let cleanup = setupCleanPersistenceState(continuousPlay: continuousPlay)
        defer { cleanup() }

        let state = GameState.restored()

        #expect(state.board == Board(dailySeed: seedFromDate(Date())))
        #expect(countRevealedCells(in: state.board) > 0, "The daily ships with its opening revealed")
    }

    @Test("Rolling over to a new day deals the same board as everyone else")
    func testRolloverBoardIsCanonical() {
        let cleanup = setupCleanPersistenceState(continuousPlay: false)
        defer { cleanup() }

        let yesterday = Int64(20200101)
        let state = GameState(board: Board(dailySeed: yesterday), dailySeed: yesterday, puzzleType: .daily)
        state.checkForDailyRollover()

        #expect(state.board == Board(dailySeed: seedFromDate(Date())))
    }

    @Test("Relaunching keeps today's game with continuous play on, clock included")
    func testRelaunchKeepsGameInProgress() throws {
        let cleanup = setupCleanPersistenceState(continuousPlay: true)
        defer { cleanup() }

        let state = try startedDaily(seed: seedFromDate(Date()))
        state.elapsedTime = 90
        state.pauseTimer()
        state.elapsedTime = 90
        state.save()

        let restored = GameState.restored()

        #expect(restored.status == .playing)
        #expect(restored.board == state.board)
        #expect(restored.elapsedTime == 90)
        #expect(restored.isPaused, "Nothing is timing a restored game until the popover opens")
        #expect(restored.playLog == state.playLog)
    }

    @Test("Today's game can't be reset once it has started")
    func testStartedDailyIsLocked() throws {
        let cleanup = setupCleanPersistenceState(continuousPlay: true)
        defer { cleanup() }

        let state = try startedDaily(seed: seedFromDate(Date()))
        state.pauseTimer()
        let board = state.board

        #expect(!state.canReset)
        state.reset()
        #expect(state.board == board)
        #expect(state.status == .playing)
    }

    @Test("A game carried over from yesterday can be abandoned for today's")
    func testYesterdaysGameCanBeReset() throws {
        let cleanup = setupCleanPersistenceState(continuousPlay: false)
        defer { cleanup() }

        let state = try startedDaily(seed: 20200101)
        state.pauseTimer()

        #expect(state.canReset)
        state.reset()
        #expect(state.dailySeed == seedFromDate(Date()))
        #expect(state.status == .notStarted)
    }

    @Test("Replaying a past day leaves today's game untouched, and the replay stays")
    func testReplayKeepsTodaysGame() throws {
        let cleanup = setupCleanPersistenceState(continuousPlay: true)
        defer { cleanup() }

        let todaySeed = seedFromDate(Date())
        let state = try startedDaily(seed: todaySeed)
        let todaysBoard = state.board
        let todaysLog = state.playLog

        state.startPractice(seed: 20200101)
        state.checkForDailyRollover()

        #expect(state.puzzleType == .practice, "Opening the popover must not discard the replay")
        #expect(state.dailySeed == 20200101)

        state.returnToToday()

        #expect(state.puzzleType == .daily)
        #expect(state.board == todaysBoard)
        #expect(state.status == .playing)
        #expect(state.playLog == todaysLog)
    }

    @Test("Leaving a replay shows a finished daily even with continuous play on")
    func testReturnToFinishedDaily() throws {
        let cleanup = setupCleanPersistenceState(continuousPlay: true)
        defer { cleanup() }

        let todaySeed = seedFromDate(Date())
        let state = GameState(board: Board(dailySeed: todaySeed), dailySeed: todaySeed, puzzleType: .daily)
        winGame(state)
        try #require(state.status == .won)

        state.startPractice(seed: 20200101)
        state.returnToToday()

        #expect(state.puzzleType == .daily)
        #expect(state.status == .won)
    }

    @Test("Replays aren't recorded")
    @MainActor
    func testReplaysAreNotRecorded() async throws {
        let cleanup = setupCleanPersistenceState(continuousPlay: true)
        defer { cleanup() }
        StatsStore.shared.reset()
        defer { UserDefaults.standard.removeObject(forKey: "statsResetAt") }

        let state = GameState(board: Board(seed: 1), dailySeed: seedFromDate(Date()), puzzleType: .random)
        state.startPractice(seed: 20200101)
        winGame(state)
        await Task.yield()

        #expect(StatsStore.shared.results.isEmpty)
    }

    @Test("Random games are recorded")
    @MainActor
    func testRandomGamesAreRecorded() async throws {
        let cleanup = setupCleanPersistenceState(continuousPlay: true)
        defer { cleanup() }
        StatsStore.shared.reset()
        defer {
            StatsStore.shared.reset()
            UserDefaults.standard.removeObject(forKey: "statsResetAt")
        }

        let state = GameState(board: Board(seed: 1), dailySeed: -5, puzzleType: .random)
        winGame(state)
        await Task.yield()

        #expect(StatsStore.shared.results.map(\.puzzleType) == [.random])
    }

    @Test("A result from another Mac shows on an unstarted board")
    @MainActor
    func testSyncedCompletionShowsOnUnstartedBoard() {
        let cleanup = setupCleanPersistenceState(continuousPlay: true)
        defer {
            cleanup()
            StatsStore.shared.reset()
            UserDefaults.standard.removeObject(forKey: "statsResetAt")
        }

        let todaySeed = seedFromDate(Date())
        let state = GameState(board: Board(dailySeed: todaySeed), dailySeed: todaySeed, puzzleType: .daily)

        let changed = StatsStore.shared.merge(dailyResults: [daily(todaySeed, won: false, at: Date())])
        state.adoptSyncedCompletion()

        #expect(changed)
        #expect(isDailyPuzzleComplete(forSeed: todaySeed))
        #expect(state.status == .lost)
    }

    @Test("A result from another Mac doesn't take away a game in progress")
    @MainActor
    func testSyncedCompletionLeavesGameInProgress() throws {
        let cleanup = setupCleanPersistenceState(continuousPlay: true)
        defer {
            cleanup()
            StatsStore.shared.reset()
            UserDefaults.standard.removeObject(forKey: "statsResetAt")
        }

        let todaySeed = seedFromDate(Date())
        let state = try startedDaily(seed: todaySeed)
        state.pauseTimer()

        StatsStore.shared.merge(dailyResults: [daily(todaySeed, at: Date())])
        state.adoptSyncedCompletion()

        #expect(state.status == .playing)
    }

    @Test("A loss on the very first move still counts as finishing a game")
    @MainActor
    func firstMoveLossIsAFinish() throws {
        let cleanup = setupCleanPersistenceState(continuousPlay: true)
        defer { cleanup() }

        let seed = seedFromDate(Date())
        let state = GameState(board: Board(dailySeed: seed), dailySeed: seed, puzzleType: .daily)
        let mine = try #require(
            (0..<Board.rows).flatMap { row in (0..<Board.cols).map { (row, $0) } }
                .first { state.board.cells[$0.0][$0.1].hasMine }
        )

        state.reveal(row: mine.0, col: mine.1)

        #expect(state.status == .lost)
        #expect(state.finishedGameCount == 1)
    }

    @Test("Going back to a finished daily isn't a new finish")
    @MainActor
    func returningToFinishedDailyIsNotAFinish() throws {
        let cleanup = setupCleanPersistenceState(continuousPlay: true)
        defer { cleanup() }

        let seed = seedFromDate(Date())
        let state = GameState(board: Board(dailySeed: seed), dailySeed: seed, puzzleType: .daily)
        let mine = try #require(
            (0..<Board.rows).flatMap { row in (0..<Board.cols).map { (row, $0) } }
                .first { state.board.cells[$0.0][$0.1].hasMine }
        )
        state.reveal(row: mine.0, col: mine.1)
        state.startPractice(seed: yesterdaySeed())

        state.returnToToday()

        #expect(state.status == .lost)
        #expect(state.finishedGameCount == 1)
    }

    @Test("Finishing yesterday's game doesn't undo today's completion")
    func completionOnlyMovesForward() {
        let cleanup = setupCleanPersistenceState(continuousPlay: true)
        defer { cleanup() }

        markDailyPuzzleComplete(forSeed: seedFromDate(Date()))
        markDailyPuzzleComplete(forSeed: yesterdaySeed())

        #expect(isDailyPuzzleComplete())
    }

    @Test("When Macs disagree about today, this one drops its own version")
    @MainActor
    func conflictingResultReplacesLocalVersion() {
        let cleanup = setupCleanPersistenceState(continuousPlay: true)
        defer {
            cleanup()
            StatsStore.shared.reset()
            UserDefaults.standard.removeObject(forKey: "statsResetAt")
        }

        let seed = seedFromDate(Date())
        // Other tests can leave a result for today behind, which would win the merge.
        StatsStore.shared.reset()
        // Ahead of the clock, so both results fall after that reset.
        let finishedHere = Date().addingTimeInterval(120)
        StatsStore.shared.merge(dailyResults: [daily(seed, won: true, at: finishedHere)])
        let snapshot = GameSnapshot(
            board: Board(dailySeed: seed), status: .won, elapsedTime: 10, flagCount: 0,
            selectedRow: 0, selectedCol: 0, dailySeed: seed
        )
        GameSnapshot.withStorageKey(GameSnapshot.dailyNamespace) { snapshot.save() }

        StatsStore.shared.merge(dailyResults: [daily(seed, won: false, at: finishedHere.addingTimeInterval(-60))])

        #expect(getStats(forSeed: seed)?.won == false)
        #expect(GameSnapshot.withStorageKey(GameSnapshot.dailyNamespace) { GameSnapshot.loadAnyDay() } == nil)
    }

    @Test("Reset clears the play tally")
    func testResetClearsTally() {
        let cleanup = setupCleanPersistenceState(continuousPlay: false)
        defer { cleanup() }

        let state = GameState(board: Board(seed: 1), dailySeed: -5, puzzleType: .daily)
        state.clickCount = 3
        state.playLog = [.open]
        state.reset()

        #expect(state.clickCount == 0)
        #expect(state.playLog.isEmpty)
    }
}

@Suite("Game timer")
struct GameTimerTests {
    private final class Clock {
        var now: TimeInterval = 100
    }

    @Test("Short visits add up instead of each losing its partial second")
    func testShortRunsAccumulate() {
        let clock = Clock()
        let timer = GameTimer(now: { clock.now })

        for _ in 0..<10 {
            timer.start(from: timer.elapsed)
            clock.now += 0.7
            timer.stop()
        }

        #expect(abs(timer.elapsed - 7) < 0.001)
    }

    @Test("Time spent stopped doesn't count")
    func testStoppedTimeIsNotCounted() {
        let clock = Clock()
        let timer = GameTimer(now: { clock.now })

        timer.start(from: 5)
        clock.now += 2
        timer.stop()
        clock.now += 500

        #expect(timer.elapsed == 7)
        #expect(!timer.isRunning)
    }
}

@Suite("Leaderboard rules")
struct LeaderboardRulesTests {
    private func seconds(
        _ elapsed: TimeInterval = 61.9,
        type: PuzzleType = .daily,
        won: Bool = true,
        seed: Int64 = 20260102
    ) -> Int? {
        Leaderboard.submittableSeconds(
            elapsedTime: elapsed, puzzleType: type, won: won, seed: seed, todaySeed: 20260102
        )
    }

    @Test("Today's win is submitted as the seconds the player saw")
    func testTodaysWin() {
        #expect(seconds() == 61)
    }

    @Test("Yesterday's board never reaches today's leaderboard")
    func testYesterdaysBoard() {
        #expect(seconds(seed: 20260101) == nil)
    }

    @Test("Losses and unranked puzzles aren't submitted")
    func testUnsubmitted() {
        #expect(seconds(won: false) == nil)
        #expect(seconds(type: .random) == nil)
        #expect(seconds(type: .practice) == nil)
        #expect(seconds(0.4) == nil)
    }
}

/// Serialized because a store writes through to UserDefaults.
@Suite("iCloud sync", .serialized)
@MainActor
struct DailyResultsCloudTests {
    private func makeStore(_ results: [GameResult] = []) -> StatsStore {
        UserDefaults.standard.removeObject(forKey: "statsResetAt")
        return StatsStore.forTesting(with: results)
    }

    private func expectSeeds(_ store: StatsStore, _ seeds: Set<Int64>) {
        #expect(Set(store.dailyResults.map(\.dailySeed)) == seeds)
    }

    @Test("Two Macs converge on the union of what they've played")
    func testMacsConverge() {
        let cloud = FakeCloud()
        let first = makeStore([daily(20260101)])
        let second = makeStore([daily(20260102)])

        DailyResultsCloud(cloud: cloud, stats: first).sync()
        DailyResultsCloud(cloud: cloud, stats: second).sync()
        DailyResultsCloud(cloud: cloud, stats: first).sync()

        expectSeeds(first, [20260101, 20260102])
        expectSeeds(second, [20260101, 20260102])
    }

    @Test("A Mac that hasn't downloaded yet can't erase other months")
    func testPartialMacOnlyTouchesItsMonth() throws {
        let cloud = FakeCloud()
        let established = makeStore([daily(20251231), daily(20260101)])
        DailyResultsCloud(cloud: cloud, stats: established).sync()
        let december = cloud.data(forKey: "results.202512")

        // Before anything has arrived, this Mac's view of the cloud is empty.
        let newMac = makeStore([daily(20260102)])
        DailyResultsCloud(cloud: FakeCloud(), stats: newMac).sync()
        let january = try #require(cloud.data(forKey: "results.202601"))
        cloud.set(try encoded([daily(20260102)]), forKey: "results.202601")

        #expect(cloud.data(forKey: "results.202512") == december)
        #expect(january != cloud.data(forKey: "results.202601"))

        // The Mac that knows more puts the month back the next time it syncs.
        DailyResultsCloud(cloud: cloud, stats: established).sync()
        let repaired = makeStore()
        DailyResultsCloud(cloud: cloud, stats: repaired).sync()
        expectSeeds(repaired, [20251231, 20260101, 20260102])
    }

    @Test("Years of results stay within the store's limits")
    func testLongHistoryFits() throws {
        let cloud = FakeCloud()
        // Written as loops because nested closures here time out the type checker on CI.
        var results: [GameResult] = []
        for year in 2026...2045 {
            for month in 1...12 {
                for day in 1...28 {
                    let seed = Int64(year) * 10000 + Int64(month) * 100 + Int64(day)
                    results.append(daily(seed))
                }
            }
        }
        DailyResultsCloud(cloud: cloud, stats: makeStore(results)).sync()

        #expect(cloud.allKeys.count == 240)
        let largest = cloud.allKeys.compactMap { cloud.data(forKey: $0)?.count }.max() ?? 0
        #expect(largest < 64_000)
    }

    @Test("History in the old single key comes across and isn't rewritten")
    func testLegacyKeyIsRead() throws {
        let cloud = FakeCloud()
        let legacy = try encoded([daily(20250101)])
        cloud.set(legacy, forKey: DailyResultsCloud.legacyKey)
        let store = makeStore()

        DailyResultsCloud(cloud: cloud, stats: store).sync()

        expectSeeds(store, [20250101])
        #expect(cloud.data(forKey: DailyResultsCloud.legacyKey) == legacy)
    }

    @Test("Conflicting results for a day settle the same way on both Macs")
    func testConflictsConverge() {
        let cloud = FakeCloud()
        let earlier = daily(20260101, won: false, at: Date(timeIntervalSinceReferenceDate: 100))
        let later = daily(20260101, won: true, at: Date(timeIntervalSinceReferenceDate: 200))
        let first = makeStore([later])
        let second = makeStore([earlier])

        DailyResultsCloud(cloud: cloud, stats: first).sync()
        DailyResultsCloud(cloud: cloud, stats: second).sync()
        DailyResultsCloud(cloud: cloud, stats: first).sync()

        #expect(first.dailyResults == [earlier])
        #expect(second.dailyResults == [earlier])
    }

    @Test("Resetting statistics reaches other Macs and stays reset")
    func testResetPropagates() {
        let cloud = FakeCloud()
        let resetDate = Date(timeIntervalSinceReferenceDate: 5_000)
        let otherMac = makeStore([daily(20260101)])
        DailyResultsCloud(cloud: cloud, stats: otherMac).sync()

        DailyResultsCloud(cloud: cloud, stats: makeStore()).publishReset(at: resetDate)
        #expect(cloud.allKeys == [DailyResultsCloud.resetKey])

        DailyResultsCloud(cloud: cloud, stats: otherMac).sync()

        #expect(otherMac.dailyResults.isEmpty)
        #expect(cloud.allKeys == [DailyResultsCloud.resetKey], "A reset Mac must not re-publish")
    }

    @Test("A result finished after a reset survives it")
    func testResultAfterResetSurvives() {
        let cloud = FakeCloud()
        DailyResultsCloud(cloud: cloud, stats: makeStore()).publishReset(at: Date(timeIntervalSinceReferenceDate: 500))

        let store = makeStore([daily(20260101, at: Date(timeIntervalSinceReferenceDate: 900))])
        DailyResultsCloud(cloud: cloud, stats: store).sync()

        expectSeeds(store, [20260101])
    }
}

@Suite("Sharing")
struct SharingTests {
    private func share(_ steps: [PlayStep], status: GameStatus = .won, type: PuzzleType = .daily) -> String? {
        ShareTextGenerator.generate(
            status: status,
            elapsedTime: 75,
            markedMinesCount: 3,
            play: PlaySummary(clickCount: 2, steps: steps),
            puzzleType: type,
            date: dateFromSeed(20260315) ?? Date()
        )
    }

    @Test("Two players' shares differ by what they did")
    func testSharesDescribeThePlayer() {
        #expect(share([.open, .cascade]) != share([.cascade, .flag, .open]))
    }

    @Test("Moves appear in order and end with the outcome")
    func testStepOrder() throws {
        let won = try #require(share([.open, .cascade, .chord, .flag]))
        #expect(won.hasSuffix("🟦🟩🟨🚩🏁"))

        let lost = try #require(share([.open], status: .lost))
        #expect(lost.hasSuffix("🟦💥"))
    }

    @Test("Long games wrap at nine moves a row")
    func testRowsWrap() throws {
        let text = try #require(share(Array(repeating: .open, count: 10)))
        #expect(text.hasSuffix("🟦🟦🟦🟦🟦🟦🟦🟦🟦\n🟦🏁"))
    }

    @Test("Headers say what kind of game this was")
    func testHeaders() throws {
        let replay = try #require(share([.open], type: .practice))
        #expect(replay.hasPrefix("MenuMines replay - "))
        #expect(replay.contains("2026"))

        let random = try #require(share([.open], type: .random))
        #expect(random.hasPrefix("MenuMines - Random board"))
        #expect(!random.contains("2026"))
    }

    @Test("Finishing a replay shares that day's date, not today's")
    func testReplayShareUsesItsOwnDate() throws {
        let state = GameState(board: Board(dailySeed: 20200315), dailySeed: 20200315, puzzleType: .practice)
        winGame(state)

        #expect(try #require(state.shareText()).contains("2020"))
    }
}

@Suite("Puzzle day")
struct PuzzleDayTests {
    @Test("The next puzzle arrives at midnight UTC")
    func testNextPuzzleDate() throws {
        let lateEvening = Date(timeIntervalSince1970: 1_710_460_800 + 23 * 3600)
        let next = nextDailyPuzzleDate(after: lateEvening)

        #expect(next == Date(timeIntervalSince1970: 1_710_460_800 + 24 * 3600))
        #expect(seedFromDate(next) == 20240316)
    }

    @Test("A finished random game doesn't make today look done")
    func testIconIgnoresOtherPuzzles() {
        for status in [GameStatus.won, .lost, .notStarted] {
            for type in [PuzzleType.random, .practice] {
                #expect(menuBarIconState(gameStatus: status, isPaused: false, isDailyComplete: false, puzzleType: type) == .incomplete)
                #expect(menuBarIconState(gameStatus: status, isPaused: false, isDailyComplete: true, puzzleType: type) == .complete)
            }
        }
    }
}
