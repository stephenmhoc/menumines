import AppKit
import Foundation

#if GAME_CENTER_ENABLED
import GameKit
#endif

/// Submits daily times to Game Center.
///
/// Only today's puzzle is ever submitted. Replays and random boards are unranked, and a
/// recurring daily leaderboard would be meaningless if yesterday's board could be posted to
/// today's list.
///
/// Connected in the App Store build only: the entitlement lives in that target's entitlements
/// file, and the direct build has no provisioning profile to carry it.
@MainActor
enum Leaderboard {
    /// Matches the recurring leaderboard configured in App Store Connect, which resets daily
    /// at 00:00 UTC to line up with the puzzle itself.
    static let dailyTimeID = "com.merimerimeri.MenuMines.daily.time"

    private static let pendingScoreKey = "pendingLeaderboardScore"

    /// A score still waiting to reach Game Center.
    private struct PendingScore: Codable {
        let seed: Int64
        let seconds: Int
    }

    /// The whole seconds to submit for a finished game, or nil if it shouldn't be submitted.
    ///
    /// Losses are not submitted, because a list of boards nobody finished would rank whoever
    /// hit a mine fastest. A game carried past midnight isn't either, because the leaderboard
    /// has already moved on to a board it wasn't played on. Seconds are floored to match the
    /// clock the player saw.
    nonisolated static func submittableSeconds(
        elapsedTime: TimeInterval,
        puzzleType: PuzzleType,
        won: Bool,
        seed: Int64,
        todaySeed: Int64
    ) -> Int? {
        guard puzzleType.isRanked, won, seed == todaySeed else { return nil }
        let seconds = Int(elapsedTime)
        return seconds > 0 ? seconds : nil
    }

    /// Submits a finished game's time, if it counts.
    static func submitDailyTime(elapsedTime: TimeInterval, puzzleType: PuzzleType, won: Bool, seed: Int64) {
        guard let seconds = submittableSeconds(
            elapsedTime: elapsedTime,
            puzzleType: puzzleType,
            won: won,
            seed: seed,
            todaySeed: seedFromDate(Date())
        ) else { return }

        send(PendingScore(seed: seed, seconds: seconds))
    }

    /// Tries again with a score that couldn't be sent. Stale ones are dropped.
    static func retryPendingScore() {
        guard let data = UserDefaults.standard.data(forKey: pendingScoreKey),
              let score = try? JSONDecoder().decode(PendingScore.self, from: data) else { return }

        clearPendingScore()
        if score.seed == seedFromDate(Date()) {
            send(score)
        }
    }

    private static func queue(_ score: PendingScore) {
        guard let data = try? JSONEncoder().encode(score) else { return }
        UserDefaults.standard.set(data, forKey: pendingScoreKey)
    }

    private static func clearPendingScore() {
        UserDefaults.standard.removeObject(forKey: pendingScoreKey)
    }

    #if GAME_CENTER_ENABLED
    static let isAvailable = true

    private(set) static var isAuthenticated = false
    /// Game Center's sign-in sheet, kept until the player asks for the leaderboard. This is
    /// an agent app, so showing it unprompted would mean forcing a window on them at launch.
    private static var signInController: NSViewController?

    /// Signs the player in. Safe to call when Game Center is unavailable or declined — the
    /// player simply gets no leaderboard, and everything else keeps working.
    static func authenticate() {
        GKLocalPlayer.local.authenticateHandler = { viewController, error in
            MainActor.assumeIsolated {
                signInController = viewController

                if let error {
                    // Declining the sign-in is a normal outcome, not something to report.
                    if !isCancellation(error) {
                        Telemetry.report(error, area: "game_center", step: "authenticate")
                    }
                    isAuthenticated = false
                    return
                }

                isAuthenticated = viewController == nil && GKLocalPlayer.local.isAuthenticated
                if isAuthenticated {
                    retryPendingScore()
                }
            }
        }
    }

    /// Shows the daily leaderboard, or asks the player to sign in first.
    static func show() {
        if let signInController = signInController as? (NSViewController & GKViewController) {
            GKDialogController.shared().parentWindow = NSApp.keyWindow
            GKDialogController.shared().present(signInController)
        } else {
            GKAccessPoint.shared.trigger(state: .leaderboards) {}
        }
    }

    private static func send(_ score: PendingScore) {
        guard isAuthenticated else {
            queue(score)
            return
        }

        GKLeaderboard.submitScore(
            score.seconds,
            context: 0,
            player: GKLocalPlayer.local,
            leaderboardIDs: [dailyTimeID]
        ) { error in
            guard let error else { return }
            MainActor.assumeIsolated {
                queue(score)
                Telemetry.report(error, area: "game_center", step: "submit")
            }
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == GKErrorDomain
            && (nsError.code == GKError.cancelled.rawValue || nsError.code == GKError.userDenied.rawValue)
    }
    #else
    static let isAvailable = false
    static func authenticate() {}
    static func show() {}
    private static func send(_ score: PendingScore) {}
    #endif
}
