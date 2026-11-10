import AppKit
import Observation

/// Draws the menu bar icon as a template image, so the system tints it for the menu bar's
/// appearance, the highlight, and an inactive or tinted menu bar, as it does its own icons.
@MainActor
enum StatusIconImage {
    /// Size of the grid glyph. Menu bar symbols sit at about this size.
    static let basePointSize: CGFloat = 15
    static let badgePointSize: CGFloat = 8
    /// Clear ring cut around the badge, so it stays apart from the grid even at 1x.
    static let badgeMargin: CGFloat = 1.5
    /// Room around the glyph for the badge to sit on its corner.
    static let inset: CGFloat = 1.5

    /// The icon for a state, or nil if a symbol is missing.
    static func make(for state: MenuBarIconState, showingResult: Bool) -> NSImage? {
        make(
            base: state.baseSymbol(showingResult: showingResult),
            badge: state.overlaySymbol(showingResult: showingResult)
        )
    }

    static func make(base: String, badge: String?) -> NSImage? {
        let baseConfiguration = NSImage.SymbolConfiguration(pointSize: basePointSize, weight: .regular)
        guard let baseImage = NSImage(systemSymbolName: base, accessibilityDescription: nil)?
            .withSymbolConfiguration(baseConfiguration) else { return nil }

        let badgeConfiguration = NSImage.SymbolConfiguration(pointSize: badgePointSize, weight: .bold)
        let badgeImage = badge.flatMap {
            NSImage(systemSymbolName: $0, accessibilityDescription: nil)?.withSymbolConfiguration(badgeConfiguration)
        }

        let baseSize = baseImage.size
        let size = NSSize(width: baseSize.width + inset * 2, height: baseSize.height + inset * 2)

        // Drawn on demand, so it's rendered afresh at each screen's scale rather than scaled.
        let image = NSImage(size: size, flipped: false) { _ in
            baseImage.draw(in: NSRect(origin: NSPoint(x: inset, y: inset), size: baseSize))

            guard let badgeImage else { return true }
            let badgeSize = badgeImage.size
            let badgeRect = NSRect(
                x: size.width - badgeSize.width,
                y: 0,
                width: badgeSize.width,
                height: badgeSize.height
            )

            if let context = NSGraphicsContext.current {
                context.saveGraphicsState()
                context.compositingOperation = .destinationOut
                NSColor.black.setFill()
                NSBezierPath(ovalIn: badgeRect.insetBy(dx: -badgeMargin, dy: -badgeMargin)).fill()
                context.restoreGraphicsState()
            }
            badgeImage.draw(in: badgeRect)
            return true
        }
        image.isTemplate = true
        return image
    }
}

/// Keeps the status item's image and VoiceOver label in step with the game.
///
/// `MenuBarIconState` decides what the icon shows; this only follows the things it depends on:
/// the game (through observation), the settings and completion (in user defaults), and
/// whether VoiceOver is listening, which is the only time the label needs the clock.
@MainActor
final class StatusIconUpdater {
    private let gameState: GameState
    private weak var button: NSStatusBarButton?
    nonisolated(unsafe) private var defaultsObserver: NSObjectProtocol?
    private var voiceOverObservation: NSKeyValueObservation?
    private var isVoiceOverRunning = NSWorkspace.shared.isVoiceOverEnabled
    private var shownIcon: (base: String, badge: String?)?

    init(gameState: GameState, button: NSStatusBarButton) {
        self.gameState = gameState
        self.button = button

        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        voiceOverObservation = NSWorkspace.shared.observe(\.isVoiceOverEnabled) { [weak self] workspace, _ in
            let isEnabled = workspace.isVoiceOverEnabled
            Task { @MainActor in
                self?.isVoiceOverRunning = isEnabled
                self?.update()
            }
        }
        update()
    }

    deinit {
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
    }

    private var state: MenuBarIconState {
        guard UserDefaults.standard.object(forKey: Constants.SettingsKeys.showMenuBarIndicators) as? Bool ?? true else {
            return .normal
        }
        return menuBarIconState(
            gameStatus: gameState.status,
            isPaused: gameState.isPaused,
            isDailyComplete: isDailyPuzzleComplete(forSeed: gameState.currentDaySeed),
            puzzleType: gameState.puzzleType
        )
    }

    private var showsResult: Bool {
        UserDefaults.standard.object(forKey: Constants.SettingsKeys.showMenuBarResult) as? Bool ?? true
    }

    /// Redraws now and again whenever something the icon reads from the game changes.
    private func update() {
        withObservationTracking {
            refresh()
        } onChange: { [weak self] in
            // Called before the change lands, so the redraw waits for it.
            Task { @MainActor in self?.update() }
        }
    }

    private func refresh() {
        guard let button else { return }
        let state = state
        let showsResult = showsResult
        let base = state.baseSymbol(showingResult: showsResult)
        let badge = state.overlaySymbol(showingResult: showsResult)

        if shownIcon?.base != base || shownIcon?.badge != badge {
            button.image = StatusIconImage.make(base: base, badge: badge)
            shownIcon = (base, badge)
        }
        button.setAccessibilityLabel(accessibilityLabel(for: state))
    }

    /// The elapsed time is only read while VoiceOver is running. Reading it otherwise would
    /// redraw the status item every second for a label nothing is listening to.
    private var announcedElapsedTime: TimeInterval {
        isVoiceOverRunning ? gameState.elapsedTime : 0
    }

    private func accessibilityLabel(for state: MenuBarIconState) -> String {
        switch state {
        case .normal:
            return String(localized: "menu_bar_title")
        case .incomplete:
            return String(localized: "menu_bar_accessibility_incomplete")
        case .playing:
            return String(format: String(localized: "menu_bar_accessibility_playing"), announcedElapsedTime.clockString)
        case .paused:
            return String(format: String(localized: "menu_bar_accessibility_paused"), announcedElapsedTime.clockString)
        case .complete:
            return String(format: String(localized: "menu_bar_accessibility_complete"), StatsStore.shared.currentStreak)
        case .lost:
            return String(localized: "menu_bar_accessibility_lost")
        }
    }
}
