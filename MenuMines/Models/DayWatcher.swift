import AppKit
import Foundation

/// The start of the next puzzle day after a given moment.
func nextDailyPuzzleDate(after date: Date) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    let today = calendar.startOfDay(for: date)
    return calendar.date(byAdding: .day, value: 1, to: today) ?? date.addingTimeInterval(86_400)
}

/// Rolls the game over when the UTC day changes, whether or not the popover is open.
///
/// The menu bar icon is the only prompt to play, so it can't wait for the player to open the
/// popover to find out that a new puzzle exists. This lives outside any view for that reason.
/// A timer alone isn't enough, because a sleeping Mac doesn't fire one on time.
@MainActor
final class DayWatcher {
    private let onDayMayHaveChanged: () -> Void
    private var timer: Timer?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    init(onDayMayHaveChanged: @escaping () -> Void) {
        self.onDayMayHaveChanged = onDayMayHaveChanged
    }

    func start() {
        guard observers.isEmpty else { return }

        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification)
        observe(.default, .NSSystemClockDidChange)
        scheduleNextDay()
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        observers.append((center, token))
    }

    private func refresh() {
        onDayMayHaveChanged()
        scheduleNextDay()
    }

    private func scheduleNextDay() {
        timer?.invalidate()
        let timer = Timer(fire: nextDailyPuzzleDate(after: Date()), interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
