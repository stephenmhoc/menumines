import Foundation

// MARK: - GameSnapshot

/// Snapshot of game state for persistence.
/// Includes all data needed to restore an in-progress or completed game.
struct GameSnapshot: Codable {
    let board: Board
    let status: GameStatus
    let elapsedTime: TimeInterval
    let flagCount: Int
    let selectedRow: Int
    let selectedCol: Int
    let dailySeed: Int64
    let puzzleType: PuzzleType
    let markedMinesAtWin: Int
    let clickCount: Int
    let chordCount: Int
    let largestOpening: Int
    let playLog: [PlayStep]

    /// Coding keys for backward-compatible decoding.
    private enum CodingKeys: String, CodingKey {
        case board, status, elapsedTime, flagCount, selectedRow, selectedCol, dailySeed, puzzleType
        case markedMinesAtWin, clickCount, chordCount, largestOpening, playLog
    }

    /// Custom decoder to provide backward compatibility for existing snapshots written
    /// before `puzzleType` and `markedMinesAtWin` were stored.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        board = try container.decode(Board.self, forKey: .board)
        status = try container.decode(GameStatus.self, forKey: .status)
        elapsedTime = try container.decode(TimeInterval.self, forKey: .elapsedTime)
        flagCount = try container.decode(Int.self, forKey: .flagCount)
        selectedRow = try container.decode(Int.self, forKey: .selectedRow)
        selectedCol = try container.decode(Int.self, forKey: .selectedCol)
        dailySeed = try container.decode(Int64.self, forKey: .dailySeed)
        puzzleType = try container.decodeIfPresent(PuzzleType.self, forKey: .puzzleType) ?? .daily
        markedMinesAtWin = try container.decodeIfPresent(Int.self, forKey: .markedMinesAtWin) ?? 0
        clickCount = try container.decodeIfPresent(Int.self, forKey: .clickCount) ?? 0
        chordCount = try container.decodeIfPresent(Int.self, forKey: .chordCount) ?? 0
        largestOpening = try container.decodeIfPresent(Int.self, forKey: .largestOpening) ?? 0
        playLog = try container.decodeIfPresent([PlayStep].self, forKey: .playLog) ?? []
    }

    init(board: Board, status: GameStatus, elapsedTime: TimeInterval, flagCount: Int,
         selectedRow: Int, selectedCol: Int, dailySeed: Int64, puzzleType: PuzzleType = .daily,
         markedMinesAtWin: Int = 0, clickCount: Int = 0, chordCount: Int = 0, largestOpening: Int = 0,
         playLog: [PlayStep] = []) {
        self.board = board
        self.status = status
        self.elapsedTime = elapsedTime
        self.flagCount = flagCount
        self.selectedRow = selectedRow
        self.selectedCol = selectedCol
        self.dailySeed = dailySeed
        self.puzzleType = puzzleType
        self.markedMinesAtWin = markedMinesAtWin
        self.clickCount = clickCount
        self.chordCount = chordCount
        self.largestOpening = largestOpening
        self.playLog = playLog
    }

    private static let baseStorageKey = "gameSnapshot"
    /// Namespace for preserving completed daily puzzle state when playing random puzzles.
    static let dailyNamespace = "daily"
    @TaskLocal private static var storageKeySuffix: String?

    private static var storageKey: String {
        guard let suffix = storageKeySuffix, !suffix.isEmpty else {
            return baseStorageKey
        }
        return "\(baseStorageKey).\(suffix)"
    }

    /// Executes a closure using a namespaced snapshot storage key.
    static func withStorageKey<T>(_ suffix: String, _ body: () throws -> T) rethrows -> T {
        try $storageKeySuffix.withValue(suffix, operation: body)
    }

    /// Saves the snapshot to UserDefaults.
    func save() {
        do {
            let data = try JSONEncoder().encode(self)
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        } catch {
            Telemetry.report(error, area: "persistence", step: "snapshot_save")
        }
    }

    /// Loads a snapshot from UserDefaults if one exists and is for today's puzzle.
    /// - Returns: The snapshot if valid for today, nil otherwise.
    static func load() -> GameSnapshot? {
        guard let snapshot = loadAnyDay() else { return nil }

        let todaySeed = seedFromDate(Date())
        guard snapshot.dailySeed == todaySeed else {
            clear()
            return nil
        }

        return snapshot
    }

    /// Loads a snapshot from UserDefaults regardless of which day it was saved.
    /// Used for rollover logic where we need to check the previous day's game status.
    /// - Returns: The snapshot if one exists and can be decoded, nil otherwise.
    static func loadAnyDay() -> GameSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return nil }

        do {
            let snapshot = try JSONDecoder().decode(GameSnapshot.self, from: data)
            return snapshot
        } catch {
            // Snapshot corruption detected - log to Sentry and clear
            Telemetry.report(error, area: "persistence", step: "snapshot_load")
            clear()
            return nil
        }
    }

    /// Clears any stored snapshot.
    static func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    // MARK: - Carried-over dailies

    /// Today's-daily snapshot that is still under way although its day has ended: a daily
    /// started before UTC midnight and not yet finished.
    ///
    /// It is still the player's game for that day, not a past daily. It stays in the active
    /// snapshot, comes back at launch whatever continuous play is set to, can't be reset, and
    /// counts on its day when it's finished. While it's waiting here, picking its day puts it
    /// back on the board, so there's never a second attempt at the same board.
    /// - Parameter todaySeed: Today's seed. Only an earlier day's game counts as carried over.
    static func carriedOverDaily(todaySeed: Int64) -> GameSnapshot? {
        guard let snapshot = loadAnyDay() else { return nil }
        guard snapshot.puzzleType == .daily, snapshot.status == .playing,
              snapshot.dailySeed < todaySeed else { return nil }
        return snapshot
    }

    // MARK: - Past dailies

    /// Prefix of the namespaces that hold past dailies left in progress, one per day
    /// (`gameSnapshot.past.<seed>`).
    ///
    /// Separate from the active snapshot so that today's game and any number of started past
    /// days can all wait for the player at once, and so that versions that can't decode a
    /// past daily never read one.
    private static let pastDailyNamespacePrefix = "past."

    private static func pastDailyNamespace(forSeed seed: Int64) -> String {
        "\(pastDailyNamespacePrefix)\(seed)"
    }

    /// Saves a past daily that's under way, so it's there when the player picks its day again.
    func saveAsPastDaily() {
        Self.withStorageKey(Self.pastDailyNamespace(forSeed: dailySeed)) { save() }
    }

    /// The past daily left in progress for a day, if there is one.
    static func loadPastDaily(seed: Int64) -> GameSnapshot? {
        withStorageKey(pastDailyNamespace(forSeed: seed)) {
            guard let snapshot = loadAnyDay() else { return nil }
            // Only a game under way is kept. Anything else under this key isn't one of ours.
            guard snapshot.dailySeed == seed, snapshot.status == .playing else {
                clear()
                return nil
            }
            return snapshot
        }
    }

    /// Forgets a day's saved progress, once it's finished or no longer needed.
    static func clearPastDaily(seed: Int64) {
        withStorageKey(pastDailyNamespace(forSeed: seed)) { clear() }
    }

    /// The days that have a past daily saved in progress.
    static func pastDailySeedsInProgress() -> Set<Int64> {
        let prefix = "\(baseStorageKey).\(pastDailyNamespacePrefix)"
        let seeds = UserDefaults.standard.dictionaryRepresentation().keys.compactMap { key in
            key.hasPrefix(prefix) ? Int64(key.dropFirst(prefix.count)) : nil
        }
        return Set(seeds)
    }
}

// MARK: - GamePersistenceCoordinator

/// Coordinates game state persistence with clear decision logic.
/// Single entry point for restore eliminates scattered logic.
///
/// Decision tree for restore:
/// 1. continuousPlay ON → the daily that's under way (today's, or one carried over from its own
///    day), otherwise a fresh game
/// 2. continuousPlay OFF → restore exact saved state
enum GamePersistenceCoordinator {

    /// Restores game state based on saved data and user settings.
    static func restore() -> GameState {
        let todaySeed = seedFromDate(Date())
        let continuousPlay = UserDefaults.standard.bool(
            forKey: Constants.SettingsKeys.continuousPlay
        )

        if continuousPlay {
            return restoreFreshGame(todaySeed: todaySeed)
        } else {
            return restoreSavedState(todaySeed: todaySeed)
        }
    }

    /// Restores today's puzzle in whatever state it was left, including a completed one.
    /// Used to come back from a replay, or to show a result from another Mac.
    static func restoreToday() -> GameState {
        restoreSavedState(todaySeed: seedFromDate(Date()))
    }

    /// Rebuilds a game from a snapshot, paused until something starts its clock.
    static func restoreGame(from snapshot: GameSnapshot) -> GameState {
        restoreFromSnapshot(snapshot)
    }

    /// Restores a past daily the player started and left, exactly as they left it.
    /// - Returns: Nil if there's nothing saved for that day.
    static func restorePastDaily(seed: Int64) -> GameState? {
        guard let snapshot = GameSnapshot.loadPastDaily(seed: seed) else { return nil }
        let state = restoreFromSnapshot(snapshot)
        state.puzzleType = .pastDaily
        return state
    }

    // MARK: - Private Decision Logic

    /// continuousPlay ON: Keep the daily that's under way if there is one, otherwise start fresh.
    /// Continuous play is about what comes after the daily. Losing a game to a restart or an
    /// update would also hand the player a fresh clock on a board they've already seen.
    ///
    /// That includes a daily carried over from an earlier day, exactly as with continuous play
    /// off. Dropping it would leave its day unplayed, so it could be started again as a fresh,
    /// recorded past daily: a free retry, and the player's progress gone.
    /// - If a daily is under way, today's or carried over: restore it
    /// - If daily complete: fresh random puzzle
    /// - If daily not complete: fresh daily puzzle
    private static func restoreFreshGame(todaySeed: Int64) -> GameState {
        if let snapshot = GameSnapshot.loadAnyDay(), snapshot.status == .playing, snapshot.puzzleType == .daily {
            return restoreFromSnapshot(snapshot)
        }

        GameSnapshot.clear()

        if isDailyPuzzleComplete() {
            return createRandomPuzzle()
        } else {
            return createDailyPuzzle(seed: todaySeed)
        }
    }

    /// continuousPlay OFF: Restore exact saved state.
    /// - If snapshot exists for today: restore it
    /// - If snapshot is from previous day and game is playing: restore it (delay rollover)
    /// - If daily namespace snapshot exists: restore it (preserves board state when toggling continuous play off)
    /// - If daily complete: restore from stats (fallback without board state)
    /// - Otherwise: fresh daily puzzle
    private static func restoreSavedState(todaySeed: Int64) -> GameState {
        // Try to restore from active snapshot (only daily puzzles are persisted)
        if let snapshot = GameSnapshot.loadAnyDay() {
            if snapshot.dailySeed == todaySeed {
                return restoreFromSnapshot(snapshot)
            }

            // Delay rollover if game is still in progress
            if snapshot.status == .playing {
                return restoreFromSnapshot(snapshot)
            }

            // Snapshot from previous day, game not in progress - allow rollover
            GameSnapshot.clear()
        }

        // Try daily namespace snapshot (preserved even when playing random puzzles)
        let dailySnapshot: GameSnapshot? = GameSnapshot.withStorageKey(GameSnapshot.dailyNamespace) {
            GameSnapshot.load()  // load() validates against today's seed
        }
        if let snapshot = dailySnapshot {
            return restoreFromSnapshot(snapshot)
        }

        // Fallback to stats (won't have board state, but better than nothing)
        if isDailyPuzzleComplete() {
            let board = Board(dailySeed: todaySeed)
            if let restoredState = restoreFromStats(seed: todaySeed, board: board) {
                return restoredState
            }
        }

        // Create fresh board for today
        return createDailyPuzzle(seed: todaySeed)
    }

    // MARK: - Restore Helpers

    /// Restores a GameState from a snapshot.
    private static func restoreFromSnapshot(_ snapshot: GameSnapshot) -> GameState {
        let state = GameState(board: snapshot.board, dailySeed: snapshot.dailySeed, puzzleType: snapshot.puzzleType)
        state.status = snapshot.status
        state.elapsedTime = snapshot.elapsedTime
        // Nothing is timing a restored game until the popover opens.
        state.isPaused = snapshot.status == .playing

        // Use board's flag count as source of truth
        let actualFlagCount = snapshot.board.flagCount
        if snapshot.flagCount != actualFlagCount {
            Telemetry.warn("Flag count mismatch in snapshot", area: "persistence")
        }
        state.flagCount = actualFlagCount

        state.selectedRow = snapshot.selectedRow
        state.selectedCol = snapshot.selectedCol
        state.markedMinesAtWin = snapshot.markedMinesAtWin
        state.clickCount = snapshot.clickCount
        state.chordCount = snapshot.chordCount
        state.largestOpening = snapshot.largestOpening
        state.playLog = snapshot.playLog
        return state
    }

    /// Attempts to restore game state from stats if today's puzzle was already completed.
    /// - Returns: GameState restored from stats, or nil if stats don't exist or are invalid
    private static func restoreFromStats(seed: Int64, board: Board) -> GameState? {
        guard let stats = getStats(forSeed: seed) else { return nil }

        guard stats.seed == seed else {
            // Data corruption - stats seed doesn't match expected seed
            Telemetry.warn("Stats seed mismatch", area: "persistence")
            return nil
        }

        let state = GameState(board: board, dailySeed: seed)
        state.status = stats.won ? .won : .lost
        state.elapsedTime = stats.elapsedTime
        // Stats restoration uses a fresh board without flags, so trust the stored count
        state.flagCount = stats.flagCount
        state.markedMinesAtWin = stats.won ? stats.flagCount : 0

        // Rebuild what the finished board looked like, as near as a result can say
        if stats.won {
            state.board.revealAllSafeCells()
            state.board.flagAllMines()
        } else {
            state.board.revealAllMines()
        }

        return state
    }

    // MARK: - Create Helpers

    /// Creates a fresh daily puzzle for the given seed.
    private static func createDailyPuzzle(seed: Int64) -> GameState {
        let board = Board(dailySeed: seed)
        return GameState(board: board, dailySeed: seed, puzzleType: .daily)
    }

    /// Creates a fresh random puzzle.
    private static func createRandomPuzzle() -> GameState {
        let seed = GameState.randomPuzzleSeed()
        let board = Board(seed: seed)
        return GameState(board: board, dailySeed: seed, puzzleType: .random)
    }
}
