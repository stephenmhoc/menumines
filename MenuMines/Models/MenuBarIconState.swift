import Foundation

/// The base SF Symbol for the menu bar icon.
let menuBarBaseIcon = "circle.grid.3x3.fill"

/// Represents the visual state of the menu bar icon.
enum MenuBarIconState: Equatable {
    /// Default icon with no indicator (daily complete, no active game or won).
    case normal

    /// Daily puzzle not yet completed.
    case incomplete

    /// Game is actively being played.
    case playing

    /// Game is in progress but paused (popover closed).
    case paused

    /// Today's daily puzzle is complete.
    case complete

    /// Game is lost.
    case lost

    /// Returns the SF Symbol name for the overlay indicator, or nil for normal state.
    var overlaySymbol: String? {
        switch self {
        case .normal:
            return nil
        case .incomplete:
            return "circle.fill"
        case .playing:
            return "timer"
        case .paused:
            return "pause.fill"
        case .complete:
            return "checkmark.circle.fill"
        case .lost:
            return "xmark.circle.fill"
        }
    }

    /// Whether this state reports how today's game ended.
    var isResult: Bool {
        self == .complete || self == .lost
    }

    /// The overlay to draw, given whether the player wants the result shown on the icon.
    func overlaySymbol(showingResult: Bool) -> String? {
        isResult && !showingResult ? nil : overlaySymbol
    }

    /// The grid symbol under the overlay. With the result hidden, a finished day looks
    /// the same however it ended, so a loss doesn't show through the grid instead.
    func baseSymbol(showingResult: Bool) -> String {
        switch self {
        case .normal, .complete:
            return "square.grid.3x3.fill"
        case .incomplete:
            return "square.grid.3x3"
        case .playing, .paused:
            return "square.grid.3x3.topleft.filled"
        case .lost:
            return showingResult ? "square.grid.3x3.bottomright.filled" : "square.grid.3x3.fill"
        }
    }

    /// Returns the SF Symbol name for this icon state (legacy, for tests).
    var systemImageName: String {
        switch self {
        case .normal:
            return "circle.grid.3x3.fill"
        case .incomplete:
            return "circle.grid.3x3.fill.badge.ellipsis"
        case .playing:
            return "timer"
        case .paused:
            return "pause.circle.fill"
        case .complete:
            return "checkmark.circle.fill"
        case .lost:
            return "xmark.circle.fill"
        }
    }
}

/// Derives the menu bar icon state from game state and daily completion status.
func menuBarIconState(
    gameStatus: GameStatus,
    isPaused: Bool,
    isDailyComplete: Bool,
    puzzleType: PuzzleType = .daily
) -> MenuBarIconState {
    // The icon is the prompt to play today's puzzle, so a finished random game or replay
    // mustn't look like today is done.
    if puzzleType != .daily, gameStatus != .playing {
        return isDailyComplete ? .complete : .incomplete
    }

    switch gameStatus {
    case .lost:
        return .lost
    case .playing:
        if isPaused {
            return .paused
        }
        return .playing
    case .won:
        return .complete
    case .notStarted:
        if isDailyComplete {
            return .complete
        }
        return .incomplete
    }
}
