import Foundation

/// The current status of the game.
enum GameStatus: String, Equatable, Codable {
    case notStarted
    case playing
    case won
    case lost
}

/// Direction for keyboard navigation.
enum Direction {
    case up, down, left, right
}

/// Observable game state that owns the board and manages game logic.
@Observable
final class GameState {
    // Settable so that GamePersistenceCoordinator can rebuild a saved game. Views only read these.
    var board: Board
    var status: GameStatus = .notStarted
    var elapsedTime: TimeInterval = 0
    var flagCount: Int = 0
    var selectedRow: Int = 0
    var selectedCol: Int = 0
    var dailySeed: Int64
    var puzzleType: PuzzleType = .daily
    var isPaused: Bool = false
    /// The current puzzle day, so that anything showing it updates when the day changes.
    private(set) var currentDaySeed: Int64 = seedFromDate(Date())
    /// Goes up when a game ends in play. A status can't say this: it also changes when the
    /// player goes back to a game that finished hours ago, and a loss on the first move goes
    /// from not started straight to lost.
    private(set) var finishedGameCount = 0
    /// Count of correctly marked mines at the time of winning (before auto-flagging).
    /// Used for share text to show player's actual skill.
    /// Persisted, because winning auto-flags every mine — recomputing it from a restored
    /// board would always report a perfect 12/12 regardless of how the player actually did.
    var markedMinesAtWin: Int = 0
    /// Cells the player opened themselves, excluding everything a cascade opened for free.
    var clickCount: Int = 0
    /// Chord reveals the player performed.
    var chordCount: Int = 0
    /// Most cells opened by a single action, cascade included.
    var largestOpening: Int = 0
    /// What the player did, in order, for sharing.
    var playLog: [PlayStep] = []
    /// Goes up when a past daily's saved progress changes. That lives in UserDefaults, which
    /// views can't observe, so they read it through this.
    private var pastDailyProgressRevision = 0
    /// A random game the player was in the middle of when they went to a past day, so that
    /// Back to Today returns to it. Kept in memory only, like every random game.
    private var parkedRandomGame: GameSnapshot?

    /// Timer for tracking elapsed game time.
    private let gameTimer = GameTimer()
    /// Handles VoiceOver announcements with debouncing.
    private let announcer = AccessibilityAnnouncer()

    /// Whether continuous play mode is enabled.
    private var isContinuousPlayEnabled: Bool {
        UserDefaults.standard.bool(forKey: Constants.SettingsKeys.continuousPlay)
    }

    /// Whether reset is allowed.
    /// A daily can't be reset once it's started, whichever day it's from, and once today's is
    /// completed, reset only moves on to a random puzzle if continuous play is enabled.
    var canReset: Bool {
        // The lock exists to stop today's result being rerolled. A replay has no result to
        // protect, so it stays restartable even once today's puzzle is settled.
        if puzzleType == .practice { return true }
        // A past daily is recorded, so once it's started it has to be played out: restarting
        // would be a free retry at a board the player has now seen. Before the first reveal
        // there's nothing to protect, and afterwards a reset replays it unrecorded.
        if puzzleType == .pastDaily { return status != .playing }
        // The board never changes, so restarting the clock on it would let anyone learn the
        // mines and then post a fast time. A daily carried over from an earlier day is locked
        // too: it still counts on its day, and dropping it would leave the day unplayed, free
        // to start again as a recorded past daily on a board the player has now seen.
        if puzzleType == .daily, status == .playing {
            return false
        }
        if isDailyPuzzleComplete() {
            return isContinuousPlayEnabled
        }
        return true
    }

    /// Whether the board holds a daily started on an earlier day and still under way.
    var isCarriedOverDaily: Bool {
        puzzleType == .daily && status == .playing && dailySeed < currentDaySeed
    }

    init(board: Board, dailySeed: Int64 = seedFromDate(Date()), puzzleType: PuzzleType = .daily) {
        self.board = board
        self.dailySeed = dailySeed
        self.puzzleType = puzzleType
        gameTimer.onTick = { [weak self] elapsed in
            self?.elapsedTime = elapsed
        }
    }

    /// The day's safe opening cell, marked for the player until they make their first reveal.
    ///
    /// Daily, past daily and replay boards start fully covered, so this is how a player knows
    /// where to begin without the board being moved for them. Random puzzles have no marked
    /// cell: their first click is made safe instead.
    var startHint: (row: Int, col: Int)? {
        guard puzzleType.usesDailyBoard, status == .notStarted else { return nil }
        let opening = Board.openingCell(forSeed: dailySeed)
        guard case .hidden = board.cells[opening.row][opening.col].state else { return nil }
        return opening
    }

    /// Generates a Wordle-style share text for the completed game.
    /// - Parameter date: The date to use for the header (defaults to the puzzle's own date).
    /// - Returns: The formatted share text, or nil if the game is not complete.
    func shareText(for date: Date? = nil) -> String? {
        ShareTextGenerator.generate(
            status: status,
            elapsedTime: elapsedTime,
            markedMinesCount: countCorrectlyMarkedMines(),
            play: PlaySummary(
                clickCount: clickCount,
                chordCount: chordCount,
                largestOpening: largestOpening,
                steps: playLog
            ),
            puzzleType: puzzleType,
            date: date ?? puzzleDate
        )
    }

    /// The date of the puzzle on the board. A random puzzle's seed isn't a date.
    private var puzzleDate: Date {
        puzzleType == .random ? Date() : dateFromSeed(dailySeed) ?? Date()
    }

    /// Counts the number of flags placed on actual mines.
    /// For won games, returns the count captured before auto-flagging to reflect player skill.
    private func countCorrectlyMarkedMines() -> Int {
        if status == .won {
            return markedMinesAtWin
        }
        return countFlaggedMines()
    }

    /// Reveals the cell at the given position.
    /// If the cell is already revealed with a number, performs a chord reveal instead.
    func reveal(row: Int, col: Int) {
        guard status == .notStarted || status == .playing else { return }
        guard row >= 0, row < Board.rows, col >= 0, col < Board.cols else { return }

        if case .revealed(let adjacentMines) = board.cells[row][col].state, adjacentMines > 0 {
            chordReveal(row: row, col: col)
            return
        }

        guard case .hidden = board.cells[row][col].state else { return }

        let isFirstClick = (status == .notStarted)
        if isFirstClick {
            // Daily boards already ship with a safe, marked opening, and must not be
            // touched: clearing an area around the player's click is what made two people
            // playing the same day play different boards. Random puzzles are not compared
            // to anyone, so they keep the forgiving first-click-is-always-safe behaviour.
            if !puzzleType.usesDailyBoard {
                board.clearAreaForOpening(centerRow: row, centerCol: col, seed: dailySeed)
            }
            startTimer()
            status = .playing
        }

        clickCount += 1
        switch board.reveal(row: row, col: col) {
        case .mine:
            logStep(.open)
            finishAsLost()
        case .safe(let revealed):
            largestOpening = max(largestOpening, revealed)
            logStep(revealed > 1 ? .cascade : .open)
            finishIfWon()
        }

        saveRecordedProgress()
    }

    /// Counts the number of flags currently placed on mines.
    private func countFlaggedMines() -> Int {
        var count = 0
        for row in board.cells {
            for cell in row {
                if case .flagged = cell.state, cell.hasMine {
                    count += 1
                }
            }
        }
        return count
    }

    /// Toggles the flag on the cell at the given position.
    /// Flags can go down before the first reveal. They don't start the clock, which only
    /// starts on a reveal.
    func toggleFlag(row: Int, col: Int) {
        guard status == .notStarted || status == .playing else { return }
        guard row >= 0, row < Board.rows, col >= 0, col < Board.cols else { return }

        let previousState = board.cells[row][col].state
        board.toggleFlag(row: row, col: col)
        let newState = board.cells[row][col].state

        // Update flag count
        if case .flagged = newState {
            flagCount += 1
            logStep(.flag)
        } else if case .flagged = previousState {
            if flagCount > 0 {
                flagCount -= 1
            } else {
                // This should never happen in normal operation.
                Telemetry.warn("Attempted to decrement flagCount below zero", area: "game_state")
            }
        }
        saveRecordedProgress()
    }

    /// Starts an unrecorded replay of an earlier day's board.
    ///
    /// Nothing about the result is recorded, so a day's result can't be improved by playing
    /// it again. `playPastDay` is what the app calls: it only gets here for a day that
    /// already has a result.
    /// - Parameter seed: The daily seed to replay, in `YYYYMMDD` form.
    func startPractice(seed: Int64) {
        leaveCurrentGame()
        startFresh(Board(dailySeed: seed), seed: seed, type: .practice)
    }

    /// Puts an earlier day's board in the panel, from launch day through yesterday.
    ///
    /// A day with no result is played as a past daily: recorded once, apart from streaks and
    /// on-the-day stats, and picked up where it was left if it was started before. A day that
    /// already has a result, from its own day or from later, is an unrecorded replay.
    ///
    /// Whatever was on the board is saved first, so today's game is there to come back to.
    /// - Parameter seed: The day to play, in `YYYYMMDD` form.
    /// - Returns: Whether that day's board is now in place. False for today, the future and
    ///   anything before launch.
    @discardableResult
    func playPastDay(seed: Int64) -> Bool {
        guard DailyHistory.isPastPuzzleDay(seed, todaySeed: seedFromDate(Date())) else { return false }

        let isFinished = status == .won || status == .lost
        if dailySeed == seed {
            // That day's game is already here to be played: a past daily, or a daily carried
            // over from its own day. Starting it again would be a way around the reset lock.
            let isRecordedGame = puzzleType == .pastDaily || puzzleType == .daily
            if isRecordedGame, !isFinished, puzzleType == .pastDaily || status == .playing {
                return true
            }
        }
        // Results are recorded a moment after a game ends, so a game finished on this board
        // is counted here too rather than left to the store.
        let justFinishedThatDay = dailySeed == seed && isFinished && puzzleType != .practice && puzzleType != .random

        leaveCurrentGame()

        if let carriedOver = GameSnapshot.carriedOverDaily(todaySeed: seedFromDate(Date())),
           carriedOver.dailySeed == seed {
            // The player started this day's daily on the day and hasn't finished it. That game
            // is the day's only attempt, so it comes back rather than a fresh past daily that
            // could be used to learn the board. Anything saved under the day's own key is a
            // second attempt that should never have existed, and goes.
            clearPastDailyProgress(seed: seed)
            apply(GamePersistenceCoordinator.restoreGame(from: carriedOver))
        } else if justFinishedThatDay || StatsStore.shared.hasDailyResult(forSeed: seed) {
            // Progress saved here is from before another Mac finished the day.
            clearPastDailyProgress(seed: seed)
            startFresh(Board(dailySeed: seed), seed: seed, type: .practice)
        } else if let saved = GamePersistenceCoordinator.restorePastDaily(seed: seed) {
            apply(saved)
        } else {
            startFresh(Board(dailySeed: seed), seed: seed, type: .pastDaily)
        }
        return true
    }

    /// Leaves a past day and goes back to today's puzzle, exactly as it was left. A past
    /// daily that's under way is kept for the next time its day is picked.
    ///
    /// A random game the player left to visit a past day comes back instead, as long as it
    /// still makes sense: continuous play is on, today's puzzle is done and no daily is under
    /// way. Otherwise today's puzzle comes back as usual.
    func returnToToday() {
        guard puzzleType == .practice || puzzleType == .pastDaily else { return }
        leaveCurrentGame()

        let parked = parkedRandomGame
        parkedRandomGame = nil
        let todaySeed = seedFromDate(Date())
        if let parked, isContinuousPlayEnabled, isDailyPuzzleComplete(forSeed: todaySeed),
           GameSnapshot.carriedOverDaily(todaySeed: todaySeed) == nil {
            apply(GamePersistenceCoordinator.restoreGame(from: parked))
        } else {
            apply(GamePersistenceCoordinator.restoreToday())
        }
    }

    /// Stops the clock and saves the game on the board, before another takes its place. The
    /// player is only visiting the next board, so this one has to be there when they come
    /// back, with its time.
    ///
    /// A random game is never saved to disk, so one under way is held in memory for Back to
    /// Today instead.
    private func leaveCurrentGame() {
        stopTimer()
        announcer.cancelPendingAnnouncement()
        if puzzleType == .random, status == .playing {
            parkedRandomGame = makeSnapshot()
        }
        save()
        // A daily saved here may be one carried over from its day, which the calendar shows.
        pastDailyProgressRevision += 1
    }

    /// The days that picking resumes a game already under way: past dailies started and not
    /// yet finished, and a daily carried over from its own day.
    var pastDailySeedsInProgress: Set<Int64> {
        _ = pastDailyProgressRevision
        var seeds = GameSnapshot.pastDailySeedsInProgress()
        if puzzleType == .pastDaily, status == .playing {
            seeds.insert(dailySeed)
        }
        if let carriedOver = carriedOverDailySeed {
            seeds.insert(carriedOver)
        }
        return seeds
    }

    /// The day of a daily started on that day and still under way, if there is one: on the
    /// board, or waiting in the saved game while the player visits a past day.
    ///
    /// That day isn't missed and isn't unplayed. Picking it puts this game back, and finishing
    /// it counts on its day.
    var carriedOverDailySeed: Int64? {
        _ = pastDailyProgressRevision
        if puzzleType == .daily, status == .playing {
            // A daily on the board is the saved game, so there's nothing else to look at.
            return dailySeed < currentDaySeed ? dailySeed : nil
        }
        return GameSnapshot.carriedOverDaily(todaySeed: currentDaySeed)?.dailySeed
    }

    private func clearPastDailyProgress(seed: Int64) {
        GameSnapshot.clearPastDaily(seed: seed)
        pastDailyProgressRevision += 1
    }

    /// Resets the game to a fresh state.
    /// If continuous play is enabled and daily puzzle is complete, starts a random puzzle.
    /// Otherwise resets to today's daily puzzle.
    /// Does nothing if reset is locked.
    func reset() {
        guard canReset else { return }
        stopTimer()
        announcer.cancelPendingAnnouncement()

        // Restarting a replay should restart that board, not drop the player somewhere else.
        if puzzleType == .practice {
            startPractice(seed: dailySeed)
            return
        }

        if puzzleType == .pastDaily {
            if status == .notStarted {
                // Nothing has been revealed, so this only takes the flags off.
                startFresh(Board(dailySeed: dailySeed), seed: dailySeed, type: .pastDaily)
            } else {
                // The day has its result. Playing its board again is a replay.
                startPractice(seed: dailySeed)
            }
            return
        }

        if isContinuousPlayEnabled && isDailyPuzzleComplete() {
            let seed = Self.randomPuzzleSeed()
            startFresh(Board(seed: seed), seed: seed, type: .random)
        } else {
            let seed = seedFromDate(Date())
            startFresh(Board(dailySeed: seed), seed: seed, type: .daily)
        }
        // A fresh board has nothing to restore, and random puzzles are never persisted.
        GameSnapshot.clear()
    }

    /// A seed for a random puzzle. Negative, so it can never be mistaken for a daily seed
    /// (`YYYYMMDD`).
    static func randomPuzzleSeed() -> Int64 {
        -Int64.random(in: 1...Int64.max)
    }

    /// Puts a new, untouched board in place.
    private func startFresh(_ board: Board, seed: Int64, type: PuzzleType) {
        self.board = board
        dailySeed = seed
        puzzleType = type
        status = .notStarted
        elapsedTime = 0
        flagCount = 0
        selectedRow = 0
        selectedCol = 0
        markedMinesAtWin = 0
        clickCount = 0
        chordCount = 0
        largestOpening = 0
        playLog = []
    }

    // MARK: - Persistence

    /// Saves the current game state to persistent storage.
    /// Saves in-progress and completed daily games so state persists across app restarts,
    /// and a past daily that's under way under its own day's key.
    /// Does not save if game hasn't started yet, or if it's a random puzzle or a replay.
    func save() {
        guard status != .notStarted else { return }

        switch puzzleType {
        case .daily:
            makeSnapshot().save()
        case .pastDaily:
            // Kept only while it's under way. A finished one lives on as its result.
            guard status == .playing else { return }
            makeSnapshot().saveAsPastDaily()
            pastDailyProgressRevision += 1
        case .random, .practice:
            // Random puzzles and replays are discarded when the player moves on.
            return
        }
    }

    /// Saves a game that will be recorded, after every move while it's under way.
    ///
    /// A daily (today's, or one carried over from its day) or a past daily can't be started
    /// over once it's begun, so what's on disk must keep up with the board. If it only caught
    /// up when the panel closed, a crash or a force quit would roll the game back to an older
    /// position with an older clock, or for a daily that had just begun, to a fresh board.
    /// A snapshot is one small JSON value, so this is cheap.
    private func saveRecordedProgress() {
        guard status == .playing, puzzleType == .daily || puzzleType == .pastDaily else { return }
        // The clock only updates `elapsedTime` once a second, so take it exactly.
        captureElapsedTime()
        save()
    }

    private func logStep(_ step: PlayStep) {
        guard playLog.count < PlayStep.maximumRecorded else { return }
        playLog.append(step)
    }

    private func makeSnapshot() -> GameSnapshot {
        GameSnapshot(
            board: board,
            status: status,
            elapsedTime: elapsedTime,
            flagCount: flagCount,
            selectedRow: selectedRow,
            selectedCol: selectedCol,
            dailySeed: dailySeed,
            puzzleType: puzzleType,
            markedMinesAtWin: markedMinesAtWin,
            clickCount: clickCount,
            chordCount: chordCount,
            largestOpening: largestOpening,
            playLog: playLog
        )
    }

    /// Takes on another state's game, whole, so a field added later can't be left behind.
    private func apply(_ other: GameState) {
        board = other.board
        dailySeed = other.dailySeed
        puzzleType = other.puzzleType
        status = other.status
        elapsedTime = other.elapsedTime
        flagCount = other.flagCount
        selectedRow = other.selectedRow
        selectedCol = other.selectedCol
        markedMinesAtWin = other.markedMinesAtWin
        clickCount = other.clickCount
        chordCount = other.chordCount
        largestOpening = other.largestOpening
        playLog = other.playLog
        isPaused = other.isPaused
    }

    /// Creates a GameState by restoring from a saved snapshot or stats if available,
    /// otherwise creates a fresh game with today's daily board.
    /// Delegates to GamePersistenceCoordinator for centralized persistence logic.
    static func restored() -> GameState {
        GamePersistenceCoordinator.restore()
    }

    /// Pauses the timer (e.g., when popover closes).
    func pauseTimer() {
        captureElapsedTime()
        gameTimer.stop()
        if status == .playing {
            isPaused = true
        }
    }

    /// Resumes the timer (e.g., when popover reopens).
    ///
    /// Harmless when the clock is already running: a second call, such as the panel appearing
    /// just after a past day was put on the board, leaves it alone rather than restarting it
    /// from the last displayed second.
    func resumeTimer() {
        guard status == .playing else { return }
        if !gameTimer.isRunning {
            gameTimer.start(from: elapsedTime)
        }
        isPaused = false
    }

    /// Reacts to the puzzle day possibly having changed.
    func dayMayHaveChanged() {
        currentDaySeed = seedFromDate(Date())
        checkForDailyRollover()
    }

    /// Shows a result from another Mac, if today's board hasn't been started here.
    ///
    /// A game already under way carries on, because taking it away mid-move would be worse.
    /// Its result can't change anything: the first result for a day stands, and it isn't
    /// submitted to the leaderboard a second time.
    func adoptSyncedCompletion() {
        let todaySeed = seedFromDate(Date())
        guard puzzleType == .daily, dailySeed == todaySeed, status == .notStarted,
              isDailyPuzzleComplete(forSeed: todaySeed) else { return }

        apply(GamePersistenceCoordinator.restoreToday())
    }

    /// Checks if we should roll over to today's puzzle and performs the rollover if needed.
    /// Called when the popover appears and when the day changes.
    ///
    /// Rollover happens when:
    /// - The current game is a daily puzzle (not random)
    /// - The current game's seed is from a previous day
    /// - AND the game is not in progress (status != .playing)
    ///
    /// If game is in progress, it continues until completion.
    /// Random puzzles are not date-bound, but should yield to a new daily puzzle
    /// once today's daily is available and incomplete.
    /// A replay or past daily stays until the player leaves it, which is what
    /// `returnToToday` is for.
    func checkForDailyRollover() {
        let todaySeed = seedFromDate(Date())

        switch puzzleType {
        case .practice, .pastDaily:
            return
        case .random:
            guard !isDailyPuzzleComplete(forSeed: todaySeed) else { return }
        case .daily:
            guard dailySeed != todaySeed else { return }
        }

        // A game in progress is left to finish.
        guard status != .playing else { return }

        rolloverToNewDay(seed: todaySeed)
    }

    /// Performs a rollover to a new day's puzzle.
    ///
    /// A daily carried over from its day is never thrown away here. If one is waiting in the
    /// saved game, it's what comes back, because clearing it would make its day playable again
    /// as a fresh, recorded past daily.
    private func rolloverToNewDay(seed: Int64) {
        stopTimer()
        announcer.cancelPendingAnnouncement()
        if let carriedOver = GameSnapshot.carriedOverDaily(todaySeed: seed) {
            apply(GamePersistenceCoordinator.restoreGame(from: carriedOver))
            return
        }
        startFresh(Board(dailySeed: seed), seed: seed, type: .daily)
        GameSnapshot.clear()
        // Clear daily namespace too since we're starting a new day
        GameSnapshot.withStorageKey(GameSnapshot.dailyNamespace) { GameSnapshot.clear() }
    }

    /// Checks if continuous play was disabled while on a random puzzle.
    /// If so, restores the completed daily puzzle state.
    ///
    /// This handles the scenario where:
    /// 1. User completes daily puzzle with continuous play enabled
    /// 2. User plays random puzzles
    /// 3. User disables continuous play
    /// 4. User should now see their completed daily puzzle (locked)
    func checkContinuousPlaySetting() {
        // Only applies when on a random puzzle with continuous play disabled
        guard puzzleType == .random, !isContinuousPlayEnabled else { return }

        // If daily is complete, restore that state using the coordinator
        guard isDailyPuzzleComplete() else { return }

        stopTimer()
        apply(GamePersistenceCoordinator.restore())
    }

    /// Moves the keyboard selection in the given direction.
    func moveSelection(_ direction: Direction) {
        let oldRow = selectedRow
        let oldCol = selectedCol

        switch direction {
        case .up:
            selectedRow = max(0, selectedRow - 1)
        case .down:
            selectedRow = min(Board.rows - 1, selectedRow + 1)
        case .left:
            selectedCol = max(0, selectedCol - 1)
        case .right:
            selectedCol = min(Board.cols - 1, selectedCol + 1)
        }

        if selectedRow != oldRow || selectedCol != oldCol {
            announceSelectedCell()
        }
    }

    /// Puts the selection on a cell the player pointed at or moved VoiceOver to, so the
    /// keyboard carries on from where they are.
    func select(row: Int, col: Int) {
        guard row >= 0, row < Board.rows, col >= 0, col < Board.cols else { return }
        selectedRow = row
        selectedCol = col
    }

    /// Announces the currently selected cell for VoiceOver users.
    /// Debounced to prevent overlapping announcements during rapid navigation.
    private func announceSelectedCell() {
        let cell = board.cells[selectedRow][selectedCol]
        announcer.announceSelectionChange(row: selectedRow, col: selectedCol, cell: cell, isGameLost: status == .lost)
    }

    /// Reveals the currently selected cell.
    func revealSelected() {
        reveal(row: selectedRow, col: selectedCol)
    }

    /// Toggles the flag on the currently selected cell.
    func toggleFlagSelected() {
        toggleFlag(row: selectedRow, col: selectedCol)
    }

    /// Performs a chord reveal on the cell at the given position.
    func chordReveal(row: Int, col: Int) {
        guard status == .playing else { return }
        guard row >= 0, row < Board.rows, col >= 0, col < Board.cols else { return }

        switch board.chordReveal(row: row, col: col) {
        case .mine:
            chordCount += 1
            logStep(.chord)
            finishAsLost()
        case .safe(let revealed):
            if revealed > 0 {
                chordCount += 1
                largestOpening = max(largestOpening, revealed)
                logStep(.chord)
            }
            finishIfWon()
        }
        saveRecordedProgress()
    }

    // MARK: - Private

    private func startTimer() {
        gameTimer.start(from: elapsedTime)
    }

    private func stopTimer() {
        captureElapsedTime()
        gameTimer.stop()
        isPaused = false
    }

    /// Takes the exact time, since `elapsedTime` otherwise only moves with the display.
    private func captureElapsedTime() {
        if gameTimer.isRunning {
            elapsedTime = gameTimer.elapsed
        }
    }

    /// Records the result, and submits a daily time if this is the day's first result. If
    /// another Mac already finished today, this game doesn't count and has nothing to submit.
    /// A past daily is recorded apart from on-the-day results, and never submitted.
    private func recordGameResult(won: Bool) {
        let result = GameResult(
            won: won,
            elapsedTime: elapsedTime,
            dailySeed: dailySeed,
            puzzleType: puzzleType
        )
        Task { @MainActor in
            guard StatsStore.shared.record(result), result.puzzleType.isRanked else { return }
            Leaderboard.submitDailyTime(
                elapsedTime: result.elapsedTime,
                puzzleType: result.puzzleType,
                won: result.won,
                seed: result.dailySeed
            )
        }
    }

    private func finishAsLost() {
        status = .lost
        board.revealAllMines()
        handleGameComplete(won: false)
    }

    /// Ends the game as a win once every safe cell is open.
    private func finishIfWon() {
        guard checkWinCondition() else { return }
        markedMinesAtWin = countFlaggedMines()
        status = .won
        board.flagAllMines()
        flagCount = Board.mineCount
        handleGameComplete(won: true)
    }

    private func checkWinCondition() -> Bool {
        for row in board.cells {
            for cell in row where !cell.hasMine {
                guard case .revealed = cell.state else {
                    return false
                }
            }
        }
        return true
    }

    /// Handles game completion (win or loss).
    /// For daily puzzles: marks complete, records stats, saves state, and saves to daily namespace.
    /// For random puzzles: records stats only (no daily tracking).
    /// For past dailies: records the day's past-daily result and drops its saved progress.
    /// Today's completion and daily stats are left alone.
    /// Replays record nothing.
    private func handleGameComplete(won: Bool) {
        stopTimer()
        finishedGameCount += 1

        if puzzleType == .pastDaily {
            clearPastDailyProgress(seed: dailySeed)
        }

        if puzzleType == .daily {
            // Only mark daily completion and record daily stats for daily puzzles
            markCompleteAndRecordStats(forSeed: dailySeed, won: won, elapsedTime: elapsedTime, flagCount: flagCount)

            // Save to daily namespace for restoration when continuous play is toggled off.
            // This is intentionally a separate save from save() below - the daily namespace
            // preserves the completed board state even when the user plays random puzzles,
            // allowing correct visual restoration when toggling continuous play off.
            let snapshot = makeSnapshot()
            GameSnapshot.withStorageKey(GameSnapshot.dailyNamespace) {
                snapshot.save()
            }
        }

        if puzzleType != .practice {
            recordGameResult(won: won)
        }
        save()
    }
}
