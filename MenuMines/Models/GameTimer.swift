import Foundation

extension TimeInterval {
    /// `MM:SS`, the way a stopwatch shows it. Not localized on purpose.
    var clockString: String {
        let totalSeconds = Int(self)
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

/// Measures how long a game has been actively played.
///
/// Time comes from a monotonic clock, and the repeating timer only prompts a redraw. Counting
/// ticks instead would lose the partial second on every pause, so someone who peeks at the
/// board in short visits would play for free, and a ranked time would be wrong.
///
/// `systemUptime` stops while the Mac sleeps, so closing the lid costs the player nothing.
/// Pause state is managed by the caller (GameState) for observability.
final class GameTimer {
    private var timer: Timer?
    private var accumulated: TimeInterval = 0
    private var runningSince: TimeInterval?
    private let now: () -> TimeInterval

    /// Called every second while running, with the total elapsed time.
    var onTick: ((TimeInterval) -> Void)?

    init(now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.now = now
    }

    var isRunning: Bool {
        runningSince != nil
    }

    /// Total time played, including the run in progress.
    var elapsed: TimeInterval {
        accumulated + (runningSince.map { now() - $0 } ?? 0)
    }

    /// Starts timing from the given elapsed time. A timer already running is replaced.
    func start(from elapsed: TimeInterval = 0) {
        timer?.invalidate()
        accumulated = elapsed
        runningSince = now()

        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.onTick?(self.elapsed)
        }
        // Scheduling in .common keeps the display moving while AppKit is tracking events.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Stops timing, keeping what has been measured so far.
    func stop() {
        accumulated = elapsed
        runningSince = nil
        timer?.invalidate()
        timer = nil
    }
}
