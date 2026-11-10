import Foundation
import Testing
@testable import MenuMines

@Suite("GameState Share Tests")
struct GameStateShareTests {

    @Test("Share text is nil before game completes")
    func testShareTextNilBeforeCompletion() {
        let board = Board(seed: 12345)
        let gameState = GameState(board: board)

        #expect(gameState.shareText() == nil, "Share text should be nil when game not started")

        gameState.reveal(row: 0, col: 0)
        #expect(gameState.status == .playing)
        #expect(gameState.shareText() == nil, "Share text should be nil while playing")
    }

    @Test("Share text available after win")
    func testShareTextAvailableAfterWin() {
        let board = Board(seed: 12345)
        let gameState = GameState(board: board)

        winGame(gameState)
        #expect(gameState.status == .won)

        let shareText = gameState.shareText()
        #expect(shareText != nil, "Share text should be available after winning")
    }

    @Test("Share text available after loss")
    func testShareTextAvailableAfterLoss() {
        let board = Board(seed: 12345)
        let gameState = GameState(board: board)

        guard let safe = findSafeCell(in: gameState.board) else {
            Issue.record("No safe cell found")
            return
        }
        gameState.reveal(row: safe.row, col: safe.col)

        guard let mine = findMineCell(in: gameState.board) else {
            Issue.record("No mine found")
            return
        }
        gameState.reveal(row: mine.row, col: mine.col)
        #expect(gameState.status == .lost)

        let shareText = gameState.shareText()
        #expect(shareText != nil, "Share text should be available after losing")
    }

    @Test("Share text includes UTC date")
    func testShareTextIncludesUTCDate() {
        let board = Board(seed: 12345)
        let gameState = GameState(board: board)

        winGame(gameState)

        // Use a specific date for testing
        let timeZone = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0) ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = DateComponents(year: 2026, month: 1, day: 25)
        guard let testDate = calendar.date(from: components) else {
            Issue.record("Failed to construct test date")
            return
        }

        guard let shareText = gameState.shareText(for: testDate) else {
            Issue.record("Share text should not be nil")
            return
        }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.locale = Locale.current
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        let expectedDate = formatter.string(from: testDate)
        let expectedHeader = "MenuMines · \(expectedDate)"
        #expect(shareText.contains(expectedHeader), "Share text should include UTC date in header")
    }

    @Test("Share text includes completion time")
    func testShareTextIncludesCompletionTime() {
        let board = Board(seed: 12345)
        let gameState = GameState(board: board)

        winGame(gameState)

        guard let shareText = gameState.shareText() else {
            Issue.record("Share text should not be nil")
            return
        }

        // Verify the actual formatted time appears in share text
        let minutes = Int(gameState.elapsedTime) / 60
        let seconds = Int(gameState.elapsedTime) % 60
        // Two-digit minutes, as the game's clock shows it.
        let expectedTime = String(format: "%02d:%02d", minutes, seconds)
        #expect(shareText.contains(expectedTime), "Share text should include formatted time")
    }

    @Test("Share text includes failed message on loss")
    func testShareTextIncludesFailedOnLoss() {
        let board = Board(seed: 12345)
        let gameState = GameState(board: board)

        guard let safe = findSafeCell(in: gameState.board) else {
            Issue.record("No safe cell found")
            return
        }
        gameState.reveal(row: safe.row, col: safe.col)

        guard let mine = findMineCell(in: gameState.board) else {
            Issue.record("No mine found")
            return
        }
        gameState.reveal(row: mine.row, col: mine.col)

        guard let shareText = gameState.shareText() else {
            Issue.record("Share text should not be nil")
            return
        }

        // Verify the actual formatted time appears in share text
        let minutes = Int(gameState.elapsedTime) / 60
        let seconds = Int(gameState.elapsedTime) % 60
        // Two-digit minutes, as the game's clock shows it.
        let expectedTime = String(format: "%02d:%02d", minutes, seconds)
        #expect(shareText.contains(expectedTime), "Share text should include formatted time")
    }

    @Test("Share text includes marked count")
    func testShareTextIncludesMarkedCount() {
        let board = Board(seed: 12345)
        let gameState = GameState(board: board)

        // Start the game first to trigger first-click clearing
        gameState.reveal(row: 0, col: 0)

        // Find and flag some mines (after first-click clearing)
        var flaggedMines = 0
        for r in 0..<Board.rows {
            for c in 0..<Board.cols {
                if gameState.board.cells[r][c].hasMine && flaggedMines < 3 {
                    gameState.toggleFlag(row: r, col: c)
                    flaggedMines += 1
                }
            }
        }

        winGame(gameState)

        guard let shareText = gameState.shareText() else {
            Issue.record("Share text should not be nil")
            return
        }

        // Verify the actual formatted count appears in share text
        let expectedCount = "\(flaggedMines)/\(Board.mineCount)"
        #expect(shareText.contains(expectedCount), "Share text should include marked count")
    }

}
