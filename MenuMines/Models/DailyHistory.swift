import Foundation

/// Which earlier days can be played, and what playing one means.
///
/// Every day from launch through yesterday has a board. A day the player has no result for
/// can be played once as a recorded past daily, and after that, like any day they played on
/// time, only as an unrecorded replay.
enum DailyHistory {
    /// The first day MenuMines was publicly available, the same for everyone: v1.0.0 was
    /// published on 2026-01-31 (UTC). Earlier days have no puzzle to go back to.
    static let launchSeed: Int64 = 2026_01_31

    /// What the player has done with one day.
    enum Day: Equatable {
        /// Before launch, or not a date at all.
        case beforeLaunch
        /// Not here yet.
        case future
        /// The ranked puzzle, which is played in the panel as itself.
        case today
        /// No result. Playing it is recorded as a past daily.
        case unplayed
        /// A past daily started and left. Playing it carries on from there.
        case inProgress
        /// Finished on its own day.
        case playedOnTheDay(GameResult)
        /// Finished afterwards, as a past daily.
        case playedLater(GameResult)

        /// What picking this day does, if anything.
        var play: Play? {
            switch self {
            case .beforeLaunch, .future, .today:
                return nil
            case .unplayed:
                return .recorded
            case .inProgress:
                return .resume
            case .playedOnTheDay, .playedLater:
                return .practice
            }
        }
    }

    /// What picking a day starts.
    enum Play: Equatable {
        /// A past daily, recorded once it's finished.
        case recorded
        /// A past daily picked up where it was left.
        case resume
        /// A replay that records nothing.
        case practice
    }

    /// Whether the seed is a real calendar day, rather than something like the 31st of February.
    static func isDate(_ seed: Int64) -> Bool {
        guard seed > 0, let date = dateFromSeed(seed) else { return false }
        return seedFromDate(date) == seed
    }

    /// Whether the seed is a day from launch through the day before `todaySeed`.
    static func isPastPuzzleDay(_ seed: Int64, todaySeed: Int64) -> Bool {
        seed >= launchSeed && seed < todaySeed && isDate(seed)
    }

    /// Classifies one day. A result from the day itself wins over one from later.
    static func day(
        forSeed seed: Int64,
        todaySeed: Int64,
        onTheDay: [Int64: GameResult],
        later: [Int64: GameResult],
        inProgress: Set<Int64>
    ) -> Day {
        guard isDate(seed), seed >= launchSeed else { return .beforeLaunch }
        if seed == todaySeed { return .today }
        if seed > todaySeed { return .future }

        if let result = onTheDay[seed] { return .playedOnTheDay(result) }
        if let result = later[seed] { return .playedLater(result) }
        return inProgress.contains(seed) ? .inProgress : .unplayed
    }

    /// The most recent day before `todaySeed` that has no result, back to launch.
    /// - Parameters:
    ///   - played: Days with a result of either kind.
    ///   - excluded: A day to pass over, such as one finished a moment ago.
    static func mostRecentMissedSeed(todaySeed: Int64, played: Set<Int64>, excluding excluded: Int64? = nil) -> Int64? {
        guard isDate(todaySeed), var date = dateFromSeed(todaySeed) else { return nil }

        while let previous = Calendar.utc.date(byAdding: .day, value: -1, to: date) {
            let seed = seedFromDate(previous)
            guard seed >= launchSeed else { return nil }
            if seed != excluded, !played.contains(seed) { return seed }
            date = previous
        }
        return nil
    }

    /// The first day of the launch month, which is as far back as the calendar pages.
    static var launchMonthStart: Date {
        dateFromSeed(launchSeed / 100 * 100 + 1) ?? .distantPast
    }
}
