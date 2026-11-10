import AppKit
import Foundation

/// Handles VoiceOver announcements with debouncing to prevent overlapping messages.
final class AccessibilityAnnouncer {
    /// Task for debouncing selection change announcements.
    private var announcementTask: Task<Void, Never>?

    /// How long the selection has to rest on a cell before it's announced.
    private let debounceDelay: Duration = .milliseconds(150)

    /// Announces a cell selection change for VoiceOver users.
    /// Debounced to prevent overlapping announcements during rapid navigation.
    /// - Parameters:
    ///   - row: The selected row (0-indexed).
    ///   - col: The selected column (0-indexed).
    ///   - cell: The cell at the selected position.
    func announceSelectionChange(row: Int, col: Int, cell: Cell) {
        announcementTask?.cancel()

        announcementTask = Task { @MainActor in
            try? await Task.sleep(for: debounceDelay)
            guard !Task.isCancelled else { return }

            let message = String(
                format: String(localized: "announcement_selection_changed"),
                row + 1,
                col + 1,
                cell.accessibilityStateDescription()
            )
            AccessibilityNotification.Announcement(message).post()
        }
    }

    /// Cancels any pending announcement.
    func cancelPendingAnnouncement() {
        announcementTask?.cancel()
        announcementTask = nil
    }
}

extension Cell {
    /// What VoiceOver says about this cell, for its label and for selection announcements.
    /// - Parameter isStartHint: Whether this is the day's marked safe opening cell.
    func accessibilityStateDescription(isStartHint: Bool = false) -> String {
        if isExploded {
            return String(localized: "cell_state_exploded_mine")
        }

        switch state {
        case .hidden where isStartHint:
            return String(localized: "cell_state_covered_safe_start")
        case .hidden:
            return String(localized: "cell_state_covered")
        case .flagged:
            return String(localized: "cell_state_flagged")
        case .revealed(let adjacentMines):
            if hasMine {
                return String(localized: "cell_state_mine")
            } else if adjacentMines == 0 {
                return String(localized: "cell_state_empty")
            } else if adjacentMines == 1 {
                return String(localized: "cell_state_one_mine")
            } else {
                return String(format: String(localized: "cell_state_mines"), adjacentMines)
            }
        }
    }
}
