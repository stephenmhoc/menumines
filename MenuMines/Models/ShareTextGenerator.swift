import Foundation

/// One thing the player did, in order.
///
/// A share shows these rather than anything about the board. A win opens every safe cell, so
/// any picture of the board marks the mines by what it leaves out, and even a difficulty heat
/// map lets a friend who hasn't played yet work out where most of the safe cells are. The
/// sequence of moves is different for everyone and says nothing about where the mines are.
enum PlayStep: String, Codable, Equatable {
    /// Opened a single cell.
    case open
    /// Opened several cells with one click.
    case cascade
    /// Chorded a number.
    case chord
    /// Placed a flag.
    case flag

    /// Enough for any reasonable game. A share is capped at this, and so is a snapshot.
    static let maximumRecorded = 81

    var emoji: String {
        switch self {
        case .open:
            return "🟦"
        case .cascade:
            return "🟩"
        case .chord:
            return "🟨"
        case .flag:
            return "🚩"
        }
    }
}

/// What the player actually did, as opposed to what the board looked like.
struct PlaySummary: Equatable {
    var clickCount: Int = 0
    var chordCount: Int = 0
    var largestOpening: Int = 0
    var steps: [PlayStep] = []
}

/// Generates Wordle-style share text for completed games.
struct ShareTextGenerator {
    private static let stepsPerRow = 9

    /// Generates share text for a completed game.
    /// - Parameters:
    ///   - status: The game status (must be .won or .lost).
    ///   - elapsedTime: Total time played.
    ///   - markedMinesCount: Number of correctly marked mines at win (before auto-flagging).
    ///   - play: What the player did.
    ///   - puzzleType: Which kind of puzzle this was. Only a daily claims to be a day's result.
    ///   - date: The puzzle's date, shown in UTC.
    /// - Returns: The formatted share text, or nil if the game is not complete.
    static func generate(
        status: GameStatus,
        elapsedTime: TimeInterval,
        markedMinesCount: Int,
        play: PlaySummary = PlaySummary(),
        puzzleType: PuzzleType = .daily,
        date: Date = Date()
    ) -> String? {
        guard status == .won || status == .lost else { return nil }

        var lines = [
            formatHeader(puzzleType: puzzleType, date: date),
            formatResultLine(status: status, elapsedTime: elapsedTime, markedMinesCount: markedMinesCount)
        ]

        if let playLine = formatPlayLine(play) {
            lines.append(playLine)
        }

        lines.append(contentsOf: stepRows(play.steps, status: status))

        return lines.joined(separator: "\n")
    }

    /// Describes how the player got there, without saying anything about where the mines are.
    private static func formatPlayLine(_ play: PlaySummary) -> String? {
        guard play.clickCount > 0 else { return nil }
        return String(
            format: String(localized: "share_play_line"),
            play.clickCount,
            play.chordCount,
            play.largestOpening
        )
    }

    private static func formatHeader(puzzleType: PuzzleType, date: Date) -> String {
        switch puzzleType {
        case .daily:
            return String(format: String(localized: "share_header"), utcDateString(date))
        case .practice:
            return String(format: String(localized: "share_header_replay"), utcDateString(date))
        case .random:
            return String(localized: "share_header_random")
        }
    }

    private static func utcDateString(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: .gmt))
    }

    /// Formats the result line showing time and flag count.
    private static func formatResultLine(status: GameStatus, elapsedTime: TimeInterval, markedMinesCount: Int) -> String {
        let minutes = Int(elapsedTime) / 60
        let seconds = Int(elapsedTime) % 60
        let timeString = String(format: "%d:%02d", minutes, seconds)

        if status == .won {
            return String(format: String(localized: "share_solved"), timeString, markedMinesCount, Board.mineCount)
        } else {
            return String(format: String(localized: "share_failed"), timeString, markedMinesCount, Board.mineCount)
        }
    }

    /// The moves in order, ending with how it finished.
    private static func stepRows(_ steps: [PlayStep], status: GameStatus) -> [String] {
        guard !steps.isEmpty else { return [] }

        var emoji = steps.prefix(PlayStep.maximumRecorded).map(\.emoji)
        emoji.append(status == .won ? "🏁" : "💥")

        return stride(from: 0, to: emoji.count, by: stepsPerRow).map { start in
            emoji[start..<min(start + stepsPerRow, emoji.count)].joined()
        }
    }
}
