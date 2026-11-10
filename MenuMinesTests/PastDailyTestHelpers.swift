import Foundation
import Testing
@testable import MenuMines

// MARK: - Helpers shared by the past-daily suites

/// A cloud to sync against, kept in memory.
final class InMemoryCloud: CloudKeyValueStoring {
    var values: [String: Any] = [:]
    private(set) var writeCount = 0

    func data(forKey key: String) -> Data? { values[key] as? Data }
    func set(_ data: Data?, forKey key: String) {
        values[key] = data
        writeCount += 1
    }
    func double(forKey key: String) -> Double { values[key] as? Double ?? 0 }
    func set(_ value: Double, forKey key: String) { values[key] = value }
    func removeObject(forKey key: String) { values[key] = nil }
    var allKeys: [String] { Array(values.keys) }
    func synchronize() -> Bool { true }
}

let pastDailyReferenceDate = Date(timeIntervalSinceReferenceDate: 1_000)

func onTheDayResult(_ seed: Int64, won: Bool = true, at date: Date = pastDailyReferenceDate) -> GameResult {
    GameResult(won: won, elapsedTime: 60, dailySeed: seed, completedAt: date, puzzleType: .daily)
}

func pastDailyResult(_ seed: Int64, won: Bool = true, at date: Date = pastDailyReferenceDate) -> GameResult {
    GameResult(won: won, elapsedTime: 90, dailySeed: seed, completedAt: date, puzzleType: .pastDaily)
}

/// The seed for the day `days` before today.
func pastSeed(daysAgo days: Int) -> Int64 {
    seedFromDate(Date().addingTimeInterval(-86_400 * Double(days)))
}

func clearPastDailyProgress() {
    for seed in GameSnapshot.pastDailySeedsInProgress() {
        GameSnapshot.clearPastDaily(seed: seed)
    }
}

/// Starts from no saved games and no results, and puts things back afterwards.
@MainActor
func setupCleanPastDailyState(continuousPlay: Bool = true) -> () -> Void {
    let cleanup = setupCleanPersistenceState(continuousPlay: continuousPlay)
    clearPastDailyProgress()
    StatsStore.shared.reset()

    return {
        cleanup()
        clearPastDailyProgress()
        StatsStore.shared.reset()
        UserDefaults.standard.removeObject(forKey: "statsResetAt")
    }
}

/// Lets the task that records a finished game run.
@MainActor
func waitForRecording() async {
    for _ in 0..<5 {
        await Task.yield()
    }
}

func freshTodaysDaily() -> GameState {
    let seed = seedFromDate(Date())
    return GameState(board: Board(dailySeed: seed), dailySeed: seed, puzzleType: .daily)
}

/// Opens the day's marked starting cell, which is always safe and never wins outright.
func makeOpeningMove(_ state: GameState) throws {
    let opening = try #require(state.startHint)
    state.reveal(row: opening.row, col: opening.col)
    try #require(state.status == .playing)
}

func loseGame(_ state: GameState) throws {
    let mine = try #require(findMineCell(in: state.board))
    state.reveal(row: mine.row, col: mine.col)
    try #require(state.status == .lost)
}

func minePositions(_ board: Board) -> [Bool] {
    board.cells.flatMap { $0.map(\.hasMine) }
}
