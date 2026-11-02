import Foundation

/// Distinguishes today's daily puzzle from the two kinds of unranked play.
enum PuzzleType: String, Codable {
    /// Today's puzzle. The only kind that counts toward completion, stats and streaks.
    case daily
    /// A generated board for continuous play once the daily is done.
    case random
    /// A replay of an earlier day's board.
    ///
    /// Deliberately unranked: letting a replay record a result would mean a missed day could
    /// be filled in afterwards, which would make streaks meaningless.
    case practice

    /// Whether a win here counts on the leaderboard.
    var isRanked: Bool {
        self == .daily
    }
}

/// Represents the outcome of a single completed game.
/// Stores raw data to enable computing derived metrics at runtime.
struct GameResult: Codable, Equatable {
    /// Whether the player won this game.
    let won: Bool

    /// Time taken to complete the game in seconds.
    let elapsedTime: TimeInterval

    /// The UTC date of the daily puzzle (stored as seed: YYYYMMDD).
    let dailySeed: Int64

    /// Timestamp when the game was completed.
    let completedAt: Date

    /// Whether this was a daily puzzle or a random continuous play puzzle.
    let puzzleType: PuzzleType

    /// Creates a game result from the current game state.
    /// - Parameters:
    ///   - won: Whether the player won.
    ///   - elapsedTime: Time taken in seconds.
    ///   - dailySeed: The daily puzzle seed.
    ///   - puzzleType: Whether this was a daily or random puzzle.
    init(won: Bool, elapsedTime: TimeInterval, dailySeed: Int64, completedAt: Date = Date(), puzzleType: PuzzleType = .daily) {
        self.won = won
        self.elapsedTime = elapsedTime
        self.dailySeed = dailySeed
        self.completedAt = completedAt
        self.puzzleType = puzzleType
    }

    /// Coding keys for backward-compatible decoding.
    private enum CodingKeys: String, CodingKey {
        case won, elapsedTime, dailySeed, completedAt, puzzleType
    }

    /// Custom decoder to provide backward compatibility for existing records without puzzleType.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        won = try container.decode(Bool.self, forKey: .won)
        elapsedTime = try container.decode(TimeInterval.self, forKey: .elapsedTime)
        dailySeed = try container.decode(Int64.self, forKey: .dailySeed)
        completedAt = try container.decode(Date.self, forKey: .completedAt)
        puzzleType = try container.decodeIfPresent(PuzzleType.self, forKey: .puzzleType) ?? .daily
    }
}
