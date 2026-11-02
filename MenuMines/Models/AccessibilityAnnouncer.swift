import AppKit
import Foundation

/// Handles VoiceOver announcements with debouncing to prevent overlapping messages.
final class AccessibilityAnnouncer {
    /// Task for debouncing selection change announcements.
    private var announcementTask: Task<Void, Never>?

    /// Debounce delay in milliseconds before announcing.
    private let debounceDelay: UInt64

    init(debounceDelay: UInt64 = 150) {
        self.debounceDelay = debounceDelay
    }

    /// Announces a cell selection change for VoiceOver users.
    /// Debounced to prevent overlapping announcements during rapid navigation.
    /// - Parameters:
    ///   - row: The selected row (0-indexed).
    ///   - col: The selected column (0-indexed).
    ///   - cell: The cell at the selected position.
    func announceSelectionChange(row: Int, col: Int, cell: Cell) {
        announcementTask?.cancel()

        announcementTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(debounceDelay))
            guard !Task.isCancelled else { return }

            let stateDescription = cellStateDescription(cell)
            let message = String(
                format: String(localized: "announcement_selection_changed"),
                row + 1,
                col + 1,
                stateDescription
            )
            AccessibilityNotification.Announcement(message).post()
        }
    }

    /// Returns a description of the cell state for accessibility announcements.
    func cellStateDescription(_ cell: Cell) -> String {
        if cell.isExploded {
            return String(localized: "cell_state_exploded_mine")
        }

        switch cell.state {
        case .hidden:
            return String(localized: "cell_state_covered")
        case .flagged:
            return String(localized: "cell_state_flagged")
        case .revealed(let adjacentMines):
            if cell.hasMine {
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

    /// Cancels any pending announcement.
    func cancelPendingAnnouncement() {
        announcementTask?.cancel()
        announcementTask = nil
    }
}
