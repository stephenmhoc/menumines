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
    // Note: internal(set) allows GamePersistenceCoordinator and checkContinuousPlaySetting to set these
    internal(set) var board: Board
    internal(set) var status: GameStatus = .notStarted
    internal(set) var elapsedTime: TimeInterval = 0
    internal(set) var flagCount: Int = 0
    internal(set) var selectedRow: Int = 0
    internal(set) var selectedCol: Int = 0
    internal(set) var dailySeed: Int64
    internal(set) var puzzleType: PuzzleType = .daily
    internal(set) var isPaused: Bool = false
    /// The current puzzle day, so that anything showing it updates when the day changes.
    private(set) var currentDaySeed: Int64 = seedFromDate(Date())
    /// Count of correctly marked mines at the time of winning (before auto-flagging).
    /// Used for share text to show player's actual skill.
    /// Persisted, because winning auto-flags every mine — recomputing it from a restored
    /// board would always report a perfect 12/12 regardless of how the player actually did.
    internal(set) var markedMinesAtWin: Int = 0
    /// Cells the player opened themselves, excluding everything a cascade opened for free.
    internal(set) var clickCount: Int = 0
    /// Chord reveals the player performed.
    internal(set) var chordCount: Int = 0
    /// Most cells opened by a single action, cascade included.
    internal(set) var largestOpening: Int = 0
    /// What the player did, in order, for sharing.
    internal(set) var playLog: [PlayStep] = []

    /// Timer for tracking elapsed game time.
    private let gameTimer = GameTimer()
    /// Handles VoiceOver announcements with debouncing.
    private let announcer = AccessibilityAnnouncer()
    /// Cache the last UTC daily seed we checked for rollover to avoid redundant calculations.
    private var lastRolloverCheckSeed: Int64?

    /// Whether continuous play mode is enabled.
    private var isContinuousPlayEnabled: Bool {
        UserDefaults.standard.bool(forKey: Constants.SettingsKeys.continuousPlay)
    }

    /// Whether reset is allowed.
    /// Today's puzzle can't be reset once it's started, and once it's completed, reset only
    /// moves on to a random puzzle if continuous play is enabled.
    var canReset: Bool {
        // The lock exists to stop today's result being rerolled. A replay has no result to
        // protect, so it stays restartable even once today's puzzle is settled.
        if puzzleType == .practice { return true }
        // The board never changes, so restarting the clock on it would let anyone learn the
        // mines and then post a fast time. A game carried over from yesterday isn't ranked.
        if puzzleType == .daily, status == .playing, dailySeed == seedFromDate(Date()) {
            return false
        }
        if isDailyPuzzleComplete() {
            return isContinuousPlayEnabled
        }
        return true
    }

    init(board: Board, dailySeed: Int64 = seedFromDate(Date()), puzzleType: PuzzleType = .daily) {
        self.board = board
        self.dailySeed = dailySeed
        self.puzzleType = puzzleType
        gameTimer.onTick = { [weak self] elapsed in
            self?.elapsedTime = elapsed
        }
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
            // Daily boards already ship with a safe opening revealed, and must not be
            // touched: clearing an area around the player's click is what made two people
            // playing the same day play different boards. Random puzzles are not compared
            // to anyone, so they keep the forgiving first-click-is-always-safe behaviour.
            if puzzleType == .random {
                board.clearAreaForOpening(centerRow: row, centerCol: col, seed: dailySeed)
            }
            startTimer()
            status = .playing
        }

        let result = board.reveal(row: row, col: col)
        clickCount += 1
        if case .safe(let revealed) = result {
            largestOpening = max(largestOpening, revealed)
            logStep(revealed > 1 ? .cascade : .open)
        } else {
            logStep(.open)
        }

        switch result {
        case .mine:
            status = .lost
            board.revealAllMines()
            handleGameComplete(won: false)
        case .safe:
            if checkWinCondition() {
                markedMinesAtWin = countFlaggedMines()
                status = .won
                board.flagAllMines()
                flagCount = Board.mineCount
                handleGameComplete(won: true)
            }
        }
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
    /// Flags are only allowed after the game has started (first reveal).
    func toggleFlag(row: Int, col: Int) {
        guard status == .playing else { return }
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
    }

    /// Starts a replay of an earlier day's board.
    ///
    /// Unranked by construction: nothing about the result is recorded, so a missed day cannot
    /// be filled in after the fact and streaks keep meaning what they say.
    /// - Parameter seed: The daily seed to replay, in `YYYYMMDD` form.
    func startPractice(seed: Int64) {
        stopTimer()
        announcer.cancelPendingAnnouncement()

        // The player is only visiting this board, so today's game has to be there when
        // they come back, with its time.
        save()

        board = Board(dailySeed: seed)
        dailySeed = seed
        puzzleType = .practice
        status = .notStarted
        elapsedTime = 0
        flagCount = 0
        selectedRow = 0
        selectedCol = 0
        resetPlayTally()
    }

    /// Leaves a replay and goes back to today's puzzle, exactly as it was left.
    func returnToToday() {
        guard puzzleType == .practice else { return }
        stopTimer()
        announcer.cancelPendingAnnouncement()
        apply(GamePersistenceCoordinator.restoreToday())
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

        // If continuous play is enabled and daily is complete, start a random puzzle
        if isContinuousPlayEnabled && isDailyPuzzleComplete() {
            resetToRandomPuzzle()
        } else {
            // Reset to today's daily puzzle
            let seed = seedFromDate(Date())
            board = Board(dailySeed: seed)
            dailySeed = seed
            puzzleType = .daily
            status = .notStarted
            elapsedTime = 0
            flagCount = 0
            selectedRow = 0
            selectedCol = 0
            resetPlayTally()
            GameSnapshot.clear()
        }
    }

    /// Resets to a new random puzzle for continuous play mode.
    private func resetToRandomPuzzle() {
        let randomSeed = generateRandomSeed()
        board = Board(seed: randomSeed)
        dailySeed = randomSeed
        puzzleType = .random
        status = .notStarted
        elapsedTime = 0
        flagCount = 0
        selectedRow = 0
        selectedCol = 0
        resetPlayTally()
        // Don't persist random puzzles
        GameSnapshot.clear()
    }

    /// Generates a random seed that won't collide with daily seeds (YYYYMMDD format).
    /// Uses negative values to ensure no collision.
    private func generateRandomSeed() -> Int64 {
        -Int64.random(in: 1...Int64.max)
    }

    // MARK: - Persistence

    /// Saves the current game state to persistent storage.
    /// Saves in-progress and completed daily games so state persists across app restarts.
    /// Does not save if game hasn't started yet or if it's a random puzzle.
    func save() {
        guard status != .notStarted else { return }
        // Don't persist random puzzles - they're discarded on app close
        guard puzzleType == .daily else { return }

        makeSnapshot().save()
    }

    /// Clears the record of what the player did, so a new board starts from nothing.
    private func resetPlayTally() {
        markedMinesAtWin = 0
        clickCount = 0
        chordCount = 0
        largestOpening = 0
        playLog = []
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
    func resumeTimer() {
        guard status == .playing else { return }
        gameTimer.start(from: elapsedTime)
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
    /// A replay stays until the player leaves it, which is what `returnToToday` is for.
    func checkForDailyRollover() {
        let todaySeed = seedFromDate(Date())

        if puzzleType == .practice { return }

        if puzzleType != .daily {
            guard !isDailyPuzzleComplete(forSeed: todaySeed) else { return }
            guard status != .playing else { return }

            rolloverToNewDay(seed: todaySeed)
            return
        }

        // Check if we've already confirmed this UTC daily seed is current.
        if lastRolloverCheckSeed == todaySeed, dailySeed == todaySeed {
            return
        }

        // Already on today's puzzle
        guard dailySeed != todaySeed else {
            lastRolloverCheckSeed = todaySeed
            return
        }

        // Game is in progress - delay rollover
        guard status != .playing else { return }

        // Roll over to today's puzzle
        rolloverToNewDay(seed: todaySeed)
    }

    /// Performs a rollover to a new day's puzzle.
    private func rolloverToNewDay(seed: Int64) {
        stopTimer()
        announcer.cancelPendingAnnouncement()
        board = Board(dailySeed: seed)
        dailySeed = seed
        puzzleType = .daily
        status = .notStarted
        elapsedTime = 0
        flagCount = 0
        // Reset to top-left cell selection
        selectedRow = 0
        selectedCol = 0
        resetPlayTally()
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
        announcer.announceSelectionChange(row: selectedRow, col: selectedCol, cell: cell)
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

        let chordResult = board.chordReveal(row: row, col: col)
        if case .safe(let revealed) = chordResult, revealed > 0 {
            chordCount += 1
            largestOpening = max(largestOpening, revealed)
            logStep(.chord)
        }

        switch chordResult {
        case .mine:
            chordCount += 1
            logStep(.chord)
            status = .lost
            board.revealAllMines()
            handleGameComplete(won: false)
        case .safe:
            if checkWinCondition() {
                markedMinesAtWin = countFlaggedMines()
                status = .won
                board.flagAllMines()
                flagCount = Board.mineCount
                handleGameComplete(won: true)
            }
        }
    }

    /// Performs a chord reveal on the currently selected cell.
    func chordRevealSelected() {
        chordReveal(row: selectedRow, col: selectedCol)
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
    private func recordGameResult(won: Bool) {
        let result = GameResult(
            won: won,
            elapsedTime: elapsedTime,
            dailySeed: dailySeed,
            puzzleType: puzzleType
        )
        Task { @MainActor in
            guard StatsStore.shared.record(result) else { return }
            Leaderboard.submitDailyTime(
                elapsedTime: result.elapsedTime,
                puzzleType: result.puzzleType,
                won: result.won,
                seed: result.dailySeed
            )
        }
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
    /// Replays record nothing.
    private func handleGameComplete(won: Bool) {
        stopTimer()

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
