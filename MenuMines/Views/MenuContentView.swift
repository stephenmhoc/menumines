import SwiftUI
import AppKit

struct MenuContentView: View {
    var gameState: GameState

    @AppStorage(Constants.SettingsKeys.confirmBeforeReset) private var confirmBeforeReset = false
    @State private var showResetConfirmation = false
    @State private var showCelebration = false
    @State private var isFlagMode = false
    @State private var isHoldingCell = false
    /// The ring only means something once the player is steering with the keyboard.
    @State private var usesKeyboard = false
    @State private var hoveredCell: BoardPosition?
    @FocusState private var isBoardFocused: Bool

    private struct BoardPosition: Equatable {
        let row: Int
        let col: Int
    }

    private var isGameComplete: Bool {
        gameState.status == .won || gameState.status == .lost
    }

    /// The moment the next daily arrives, once there's nothing left to do today.
    private var nextPuzzleDate: Date? {
        let isToday = gameState.currentDaySeed == seedFromDate(Date())
        guard isToday, gameState.puzzleType == .daily, isGameComplete else { return nil }
        return nextDailyPuzzleDate(after: Date())
    }

    private let contentHeight: CGFloat = 372
    private let rowSpacing: CGFloat = 12

    /// Tells VoiceOver which board has just arrived, since nothing else about a covered
    /// board says which day it is or whether it counts.
    private func announceBoard() {
        guard let message = gameState.boardAnnouncement else { return }
        AccessibilityNotification.Announcement(message).post()
    }

    private func copyShareTextToClipboard() {
        guard let text = gameState.shareText() else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Handles the board's keys. They only arrive while the board has keyboard focus, so a
    /// confirmation or a focused button gets Space for itself and can't reveal a hidden cell.
    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        guard press.modifiers.isDisjoint(with: [.command, .control, .option]) else { return .ignored }

        switch press.key {
        case .upArrow:
            moveSelection(.up)
        case .downArrow:
            moveSelection(.down)
        case .leftArrow:
            moveSelection(.left)
        case .rightArrow:
            moveSelection(.right)
        case .space where press.phase == .down, .return where press.phase == .down:
            usesKeyboard = true
            gameState.revealSelected()
        default:
            guard press.characters.lowercased() == "f" else { return .ignored }
            if press.phase == .down {
                flagAtPointerOrSelection()
            }
        }
        return .handled
    }

    private func moveSelection(_ direction: Direction) {
        usesKeyboard = true
        gameState.moveSelection(direction)
    }

    private func flagAtPointerOrSelection() {
        if let hoveredCell, !usesKeyboard {
            gameState.select(row: hoveredCell.row, col: hoveredCell.col)
        }
        gameState.toggleFlagSelected()
    }

    private func reveal(row: Int, col: Int) {
        usesKeyboard = false
        isBoardFocused = true
        gameState.select(row: row, col: col)
        gameState.reveal(row: row, col: col)
    }

    private func chord(row: Int, col: Int) {
        usesKeyboard = false
        isBoardFocused = true
        gameState.select(row: row, col: col)
        gameState.chordReveal(row: row, col: col)
    }

    private func flag(row: Int, col: Int) {
        usesKeyboard = false
        isBoardFocused = true
        gameState.select(row: row, col: col)
        gameState.toggleFlag(row: row, col: col)
    }

    private func handleResetRequest() {
        // Prevent multiple reset requests while confirmation dialog is already showing
        guard !showResetConfirmation else { return }

        if confirmBeforeReset {
            showResetConfirmation = true
        } else {
            gameState.reset()
        }
    }

    private func announceGameResult(won: Bool) {
        let message: String
        if won {
            let seconds = Int(gameState.elapsedTime)
            if seconds == 1 {
                message = String(localized: "announcement_win_one_second")
            } else {
                message = String(format: String(localized: "announcement_win"), seconds)
            }
        } else {
            message = String(localized: "announcement_lose")
        }
        AccessibilityNotification.Announcement(message).post()
    }

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: rowSpacing) {
                HeaderView(
                    status: gameState.status,
                    elapsedTime: gameState.elapsedTime,
                    flagCount: gameState.flagCount,
                    canReset: gameState.canReset,
                    isHoldingCell: isHoldingCell,
                    resetHint: gameState.puzzleType.resetHint,
                    resetLockedHint: gameState.resetLockedHint,
                    onReset: handleResetRequest
                )

                GameBoardView(
                    board: gameState.board,
                    gameStatus: gameState.status,
                    selectedRow: gameState.selectedRow,
                    selectedCol: gameState.selectedCol,
                    showsSelection: usesKeyboard && isBoardFocused,
                    startHint: gameState.startHint,
                    isFlagMode: isFlagMode,
                    onReveal: reveal,
                    onFlag: flag,
                    onChord: chord,
                    onHover: { row, col, isHovering in
                        if isHovering {
                            hoveredCell = BoardPosition(row: row, col: col)
                            usesKeyboard = false
                        } else if hoveredCell == BoardPosition(row: row, col: col) {
                            hoveredCell = nil
                        }
                    },
                    onHoldChanged: { isHoldingCell = $0 },
                    onAccessibilityFocus: { row, col in
                        gameState.select(row: row, col: col)
                    }
                )
                .focusable(!showResetConfirmation)
                .focusEffectDisabled()
                .focused($isBoardFocused)
                .onChange(of: isBoardFocused) { _, focused in
                    // Tabbing back to the board (with Keyboard Navigation on) is steering by
                    // keyboard, so show where the selection is. A click focuses it too, and
                    // says otherwise itself.
                    if focused, NSApp.currentEvent?.type == .keyDown {
                        usesKeyboard = true
                    }
                }
                .onKeyPress(phases: [.down, .repeat], action: handleKey)

                FooterView(
                    isGameComplete: isGameComplete,
                    puzzleType: gameState.puzzleType,
                    canReset: gameState.canReset,
                    isFlagMode: isFlagMode,
                    shareText: isGameComplete ? gameState.shareText() : nil,
                    nextPuzzleDate: nextPuzzleDate,
                    pastDay: gameState.pastDay,
                    resetLockedHint: gameState.resetLockedHint,
                    onReset: handleResetRequest,
                    onToggleFlagMode: {
                        isFlagMode.toggle()
                    },
                    onCopy: copyShareTextToClipboard,
                    onReturnToToday: {
                        gameState.returnToToday()
                        gameState.resumeTimer()
                        isBoardFocused = true
                    },
                    onDailyHistory: {
                        AppWindows.showDailyHistory(gameState: gameState)
                    },
                    onStats: {
                        AppWindows.showStats(gameState: gameState)
                    },
                    onSettings: AppWindows.showSettings,
                    onAbout: AboutWindow.show
                )
            }
            .padding()

            ConfettiView(isActive: showCelebration)

            // Inline reset confirmation overlay
            if showResetConfirmation {
                ResetConfirmationOverlay(
                    message: gameState.puzzleType.resetConfirmationMessage,
                    onCancel: {
                        showResetConfirmation = false
                    },
                    onConfirm: {
                        showResetConfirmation = false
                        gameState.reset()
                    }
                )
            }
        }
        .frame(width: 300, height: contentHeight, alignment: .top)
        // No background of its own: the panel puts it on the system material.
        .onAppear {
            gameState.dayMayHaveChanged()
            gameState.checkContinuousPlaySetting()
            gameState.resumeTimer()
            Leaderboard.retryPendingScore()
            isBoardFocused = true
            if gameState.puzzleType.isPastDay {
                announceBoard()
            }
        }
        .onChange(of: gameState.boardIdentity) {
            // A new board has nothing to celebrate and no cell being held.
            showCelebration = false
            announceBoard()
        }
        .onDisappear {
            isHoldingCell = false
            hoveredCell = nil
            gameState.pauseTimer()
            gameState.save()
        }
        .onChange(of: showResetConfirmation) { _, isShowing in
            if !isShowing {
                isBoardFocused = true
            }
        }
        .onChange(of: gameState.finishedGameCount) {
            let won = gameState.status == .won
            showCelebration = won
            announceGameResult(won: won)
        }
        .onChange(of: gameState.status) { oldStatus, newStatus in
            switch newStatus {
            case .won, .lost:
                isFlagMode = false
            case .playing, .notStarted:
                // Clear celebration when resetting from won state
                if oldStatus == .won {
                    showCelebration = false
                }
            }
        }
    }
}

private extension GameState {
    /// The day on the board, when it's an earlier one.
    var pastDay: Date? {
        puzzleType.isPastDay ? dateFromSeed(dailySeed) : nil
    }

    /// Changes whenever a different board is put in the panel.
    var boardIdentity: String {
        "\(puzzleType.rawValue)-\(dailySeed)"
    }

    /// What to tell VoiceOver about the board, if it's worth saying.
    var boardAnnouncement: String? {
        if let pastDay {
            return puzzleType.pastDayDescription(for: pastDay)
        }
        return puzzleType == .daily ? String(localized: "announcement_todays_puzzle") : nil
    }
}

/// Inline confirmation overlay for reset action.
/// Uses an overlay instead of system alert so that the game panel stays open.
private struct ResetConfirmationOverlay: View {
    let message: String
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .accessibilityHidden(true)

            // Confirmation card
            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    Text(String(localized: "reset_confirmation_title"))
                        .font(.headline)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .accessibilityElement(children: .combine)

                HStack(spacing: 12) {
                    Button(String(localized: "reset_confirmation_cancel")) {
                        onCancel()
                    }
                    .keyboardShortcut(.cancelAction)

                    Button(String(localized: "reset_confirmation_confirm")) {
                        onConfirm()
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
            .padding(20)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .shadow(radius: 10)
            .accessibilityAddTraits(.isModal)
        }
    }
}

#Preview {
    MenuContentView(gameState: GameState(board: Board(seed: 12345)))
}
