import Foundation

/// Distinguishes today's daily puzzle from the other kinds of play.
enum PuzzleType: String, Codable {
    /// Today's puzzle, played on its day. The only kind that counts toward on-the-day
    /// completion, daily stats, streaks and the leaderboard.
    case daily
    /// A generated board for continuous play once the daily is done.
    case random
    /// A replay of an earlier day's board that the player already has a result for.
    ///
    /// Records nothing, so a day's result can't be improved by playing it again.
    case practice
    /// An earlier day's board, played for the first time after its day has passed.
    ///
    /// Recorded once per day, but in storage of its own (`StatsStore.pastDailyResults`), which
    /// nothing that computes streaks, daily stats or the leaderboard reads. That is what keeps
    /// a streak meaning "played on the day": a missed day can be filled in on the calendar,
    /// and it shows there as played later, but it can never join or repair a streak.
    ///
    /// Versions up to 1.0.22 can't decode this raw value. They never meet it: past dailies
    /// are saved under keys of their own, on this Mac and in iCloud, that those versions
    /// don't read.
    case pastDaily

    /// Whether a win here counts on the leaderboard.
    var isRanked: Bool {
        self == .daily
    }

    /// Whether the board is a day's own board, played by the daily rules: fully determined by
    /// the seed, with a marked opening cell and no mines moved for the first click.
    var usesDailyBoard: Bool {
        self != .random
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

    /// Which kind of puzzle this was.
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
