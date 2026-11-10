import Foundation

/// What the reset command would do with the board in front of the player, so it can be named
/// for what it does: a random board is a new game, an earlier day's board is restarted.
enum ResetAction: Equatable {
    /// Deals a new random board.
    case newGame
    /// Moves on to today's puzzle, which hasn't been played, from a random board or from a daily
    /// carried over from an earlier day and finished since.
    case startToday
    /// Today's puzzle before its first reveal, which only takes the flags off.
    case restartToday
    /// A past daily before its first reveal, which only takes the flags off.
    case restartPastDaily
    /// A finished past daily, played again as an unrecorded replay.
    case replayPastDaily
    /// A replay, from the start.
    case restartReplay
}

extension ResetAction {
    /// The command's name, in the gear menu, the face's tooltip and VoiceOver. Mac games call
    /// dealing a fresh board New Game, and starting the same one over Restart.
    var title: String {
        switch self {
        case .newGame, .startToday:
            String(localized: "reset_new_game")
        case .restartToday, .restartPastDaily, .replayPastDaily, .restartReplay:
            String(localized: "reset_restart")
        }
    }

    /// What it does, for VoiceOver and the confirmation.
    var hint: String {
        switch self {
        case .newGame:
            String(localized: "reset_hint_new_game")
        case .startToday:
            String(localized: "reset_hint_start_today")
        case .restartToday:
            String(localized: "reset_hint_restart_today")
        case .restartPastDaily:
            String(localized: "reset_hint_restart_past_daily")
        case .replayPastDaily:
            String(localized: "reset_hint_replay_past_daily")
        case .restartReplay:
            String(localized: "reset_hint_restart_replay")
        }
    }

    var confirmationTitle: String {
        switch self {
        case .newGame, .startToday:
            String(localized: "reset_confirmation_title_new_game")
        case .restartToday, .restartPastDaily, .replayPastDaily, .restartReplay:
            String(localized: "reset_confirmation_title_restart")
        }
    }
}
