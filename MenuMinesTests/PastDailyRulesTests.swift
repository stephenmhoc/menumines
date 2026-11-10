import Foundation
import Testing
@testable import MenuMines

// MARK: - Unranked

@Suite("Past dailies are unranked")
struct PastDailyUnrankedTests {
    @Test("A past daily is never submitted to the leaderboard")
    func testNeverSubmitted() {
        #expect(!PuzzleType.pastDaily.isRanked)

        // Even a win, and even if the seed were somehow today's.
        #expect(Leaderboard.submittableSeconds(
            elapsedTime: 61, puzzleType: .pastDaily, won: true, seed: 2026_11_09, todaySeed: 2026_11_09
        ) == nil)
        #expect(Leaderboard.submittableSeconds(
            elapsedTime: 61, puzzleType: .pastDaily, won: true, seed: 2026_11_08, todaySeed: 2026_11_09
        ) == nil)
    }

    @Test("Only today's daily is ranked")
    func testOnlyDailyIsRanked() {
        #expect(PuzzleType.daily.isRanked)
        for type in [PuzzleType.random, .practice, .pastDaily] {
            #expect(!type.isRanked)
        }
    }

    @Test("A past daily uses the day's own board, like a daily and a replay")
    func testUsesDailyBoard() {
        for type in [PuzzleType.daily, .practice, .pastDaily] {
            #expect(type.usesDailyBoard)
        }
        #expect(!PuzzleType.random.usesDailyBoard)
    }

    private func icon(
        _ status: GameStatus,
        paused: Bool = false,
        todayDone: Bool,
        type: PuzzleType = .pastDaily
    ) -> MenuBarIconState {
        menuBarIconState(gameStatus: status, isPaused: paused, isDailyComplete: todayDone, puzzleType: type)
    }

    @Test("A finished or unstarted past daily leaves the icon saying how today stands")
    func testIconKeepsTodaysState() {
        for status in [GameStatus.won, .lost, .notStarted] {
            #expect(icon(status, todayDone: false) == .incomplete)
            #expect(icon(status, todayDone: true) == .complete)
        }
    }

    @Test("A past daily under way shows the clock, as a replay does")
    func testIconWhilePlaying() {
        for type in [PuzzleType.practice, .pastDaily] {
            #expect(icon(.playing, todayDone: true, type: type) == .playing)
            #expect(icon(.playing, paused: true, todayDone: false, type: type) == .paused)
        }
    }
}

// MARK: - Share text

@Suite("Past daily share text")
struct PastDailyShareTests {
    private func share(_ type: PuzzleType, status: GameStatus = .won, seed: Int64 = 2026_03_15) throws -> String {
        let date = try #require(dateFromSeed(seed))
        return try #require(ShareTextGenerator.generate(
            status: status,
            elapsedTime: 75,
            markedMinesCount: 7,
            play: PlaySummary(
                clickCount: 4, chordCount: 1, largestOpening: 20, steps: [.cascade, .flag, .chord, .open]
            ),
            puzzleType: type,
            date: date
        ))
    }

    private func utcDate(_ seed: Int64) throws -> String {
        try #require(dateFromSeed(seed))
            .formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: .gmt))
    }

    @Test("The header names the puzzle's date and says it was played later")
    func testHeader() throws {
        let text = try share(.pastDaily)
        let header = try #require(text.components(separatedBy: "\n").first)

        let date = try utcDate(2026_03_15)
        #expect(header == "MenuMines - \(date) (played later)")
        #expect(date.contains("2026"))
    }

    @Test("It can't be mistaken for an on-the-day result or a replay")
    func testHeaderIsDistinct() throws {
        let pastDaily = try #require(share(.pastDaily).components(separatedBy: "\n").first)
        let daily = try #require(share(.daily).components(separatedBy: "\n").first)
        let replay = try #require(share(.practice).components(separatedBy: "\n").first)

        #expect(pastDaily != daily)
        #expect(pastDaily != replay)
        #expect(pastDaily.hasPrefix(daily), "The day's own header, with a note after it")
        #expect(!daily.contains("played later"))
    }

    @Test("Everything after the header is the same as any other result, and gives nothing away")
    func testBodyIsSpoilerFree() throws {
        let pastDaily = try share(.pastDaily, status: .lost).components(separatedBy: "\n")
        let daily = try share(.daily, status: .lost).components(separatedBy: "\n")

        #expect(Array(pastDaily.dropFirst()) == Array(daily.dropFirst()))
        #expect(pastDaily.last == "🟩🚩🟨🟦💥")
        #expect(!pastDaily.joined().contains("💣"))
        #expect(pastDaily.count == 4, "Header, result, play line and one row of moves: no board")
    }

    @Test("A finished past daily shares its own day, not today")
    @MainActor
    func testSharesItsOwnDate() async throws {
        let cleanup = setupCleanPastDailyState()
        defer { cleanup() }

        let state = freshTodaysDaily()
        state.playPastDay(seed: DailyHistory.launchSeed)
        #expect(state.shareText() == nil, "Nothing to share until it's finished")
        winGame(state)
        try #require(state.status == .won)
        await waitForRecording()

        let shareText = try #require(state.shareText())
        let header = try #require(shareText.components(separatedBy: "\n").first)
        let launchDay = try utcDate(2026_01_31)
        #expect(header == "MenuMines - \(launchDay) (played later)")
    }
}

// MARK: - Compatibility

/// Data in the shapes the current release (1.0.22) writes, spelled out rather than encoded
/// here, so that a change to how this version decodes them can't pass unnoticed.
@Suite("Past daily compatibility")
struct PastDailyCompatibilityTests {
    private func cellJSON(_ state: String = #"{"type":"hidden"}"#, mine: Bool = false) -> String {
        #"{"state":\#(state),"hasMine":\#(mine),"isExploded":false}"#
    }

    /// A 9x9 board with a mine, an opened cell and a flag on it.
    private var boardJSON: String {
        var rows: [String] = []
        for row in 0..<9 {
            var cells: [String] = []
            for col in 0..<9 {
                switch (row, col) {
                case (0, 0):
                    cells.append(cellJSON(mine: true))
                case (4, 4):
                    cells.append(cellJSON(#"{"type":"revealed","adjacentMines":2}"#))
                case (8, 8):
                    cells.append(cellJSON(#"{"type":"flagged"}"#))
                default:
                    cells.append(cellJSON())
                }
            }
            rows.append("[" + cells.joined(separator: ",") + "]")
        }
        return #"{"cells":["# + rows.joined(separator: ",") + "]}"
    }

    private func snapshotJSON(puzzleType: String?) -> Data {
        let type = puzzleType.map { #""puzzleType":"\#($0)","# } ?? ""
        let fields = [
            #""board":\#(boardJSON)"#,
            #""status":"playing","elapsedTime":42.5,"flagCount":1,"selectedRow":4,"selectedCol":4"#,
            #""dailySeed":20261108,\#(type)"markedMinesAtWin":0,"clickCount":1,"chordCount":0"#,
            #""largestOpening":1,"playLog":["open","flag"]"#
        ]
        let json = "{" + fields.joined(separator: ",") + "}"
        return Data(json.utf8)
    }

    @Test("A snapshot written by the current release decodes, whatever kind of game it holds",
          arguments: ["daily", "random", "practice"])
    func testReleaseSnapshotsDecode(type: String) throws {
        let snapshot = try JSONDecoder().decode(GameSnapshot.self, from: snapshotJSON(puzzleType: type))

        #expect(snapshot.puzzleType.rawValue == type)
        #expect(snapshot.status == .playing)
        #expect(snapshot.elapsedTime == 42.5)
        #expect(snapshot.dailySeed == 2026_11_08)
        #expect(snapshot.playLog == [.open, .flag])
        #expect(snapshot.board.flagCount == 1)
        #expect(snapshot.board.cells[0][0].hasMine)
        #expect(snapshot.board.cells[4][4].state == .revealed(adjacentMines: 2))
    }

    @Test("A snapshot from before puzzle types were stored still decodes as a daily")
    func testLegacySnapshotDecodes() throws {
        let snapshot = try JSONDecoder().decode(GameSnapshot.self, from: snapshotJSON(puzzleType: nil))
        #expect(snapshot.puzzleType == .daily)
    }

    @Test("This version decodes the past-daily snapshots it writes")
    func testPastDailySnapshotRoundTrips() throws {
        let fromJSON = try JSONDecoder().decode(GameSnapshot.self, from: snapshotJSON(puzzleType: "pastDaily"))
        #expect(fromJSON.puzzleType == .pastDaily)

        let original = GameSnapshot(
            board: Board(dailySeed: 2026_11_08), status: .playing, elapsedTime: 12, flagCount: 0,
            selectedRow: 1, selectedCol: 2, dailySeed: 2026_11_08, puzzleType: .pastDaily,
            clickCount: 3, playLog: [.cascade]
        )
        let decoded = try JSONDecoder().decode(GameSnapshot.self, from: JSONEncoder().encode(original))

        #expect(decoded.puzzleType == .pastDaily)
        #expect(decoded.board == original.board)
        #expect(decoded.elapsedTime == 12)
        #expect(decoded.playLog == [.cascade])
    }

    @Test("Stats written by the current release decode, and hold no past dailies")
    @MainActor
    func testReleaseStatsDecode() throws {
        let json = """
        [{"won":true,"elapsedTime":61.5,"dailySeed":20261108,"completedAt":800000000,"puzzleType":"daily"},
         {"won":false,"elapsedTime":12,"dailySeed":20261107,"completedAt":799900000.25,"puzzleType":"daily"},
         {"won":true,"elapsedTime":30,"dailySeed":-7731,"completedAt":800000100,"puzzleType":"random"},
         {"won":true,"elapsedTime":99,"dailySeed":20260201,"completedAt":790000000}]
        """
        let results = try JSONDecoder().decode([GameResult].self, from: Data(json.utf8))

        #expect(results.map(\.puzzleType) == [.daily, .daily, .random, .daily])
        #expect(results[0].completedAt == Date(timeIntervalSinceReferenceDate: 800_000_000))

        let store = StatsStore.forTesting(with: results)
        #expect(store.gamesPlayed == 4)
        #expect(store.dailyGamesPlayed == 3)
        #expect(store.longestStreak == 2)
        #expect(store.pastDailyResults.isEmpty)
        #expect(store.pastDailyGamesPlayed == 0)
        #expect(store.playedDailySeeds == [2026_11_08, 2026_11_07, 2026_02_01])
    }

    @Test("A past-daily result round-trips, and is spelled the way the cloud keys expect")
    func testPastDailyResultRoundTrips() throws {
        let original = pastDailyResult(2026_03_01, won: false)
        let data = try JSONEncoder().encode([original])

        #expect(String(data: data, encoding: .utf8)?.contains(#""puzzleType":"pastDaily""#) == true)
        #expect(try JSONDecoder().decode([GameResult].self, from: data) == [original])
    }

    @Test("The stored names of the puzzle types haven't changed")
    func testRawValuesAreStable() {
        #expect(PuzzleType.daily.rawValue == "daily")
        #expect(PuzzleType.random.rawValue == "random")
        #expect(PuzzleType.practice.rawValue == "practice")
        #expect(PuzzleType.pastDaily.rawValue == "pastDaily")
    }
}
