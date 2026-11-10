import AppKit
import SwiftUI

// Draws the App Store screenshots in `AppStoreScreenshots/`. Debug builds only, and only when
// launched with MENUMINES_EXPORT_APP_STORE_SCREENSHOTS=1 (see docs/APPSTORE_SETUP.md). The
// views here are a styled mock-up for the store page, not the app's own views.

#if DEBUG
enum AppStoreScreenshotVariant: String, CaseIterable {
    case daily
    case playing
    case complete

    static let seed: Int64 = 20260513

    var fileName: String {
        switch self {
        case .daily:
            return "01-daily-puzzle.png"
        case .playing:
            return "02-fast-play.png"
        case .complete:
            return "03-daily-result.png"
        }
    }

    var title: String {
        switch self {
        case .daily:
            return "Minesweeper in your menu bar"
        case .playing:
            return "A quick puzzle, one click away"
        case .complete:
            return "Track the daily, then keep playing"
        }
    }

    var subtitle: String {
        switch self {
        case .daily:
            return "A new 9x9 board every day, with the same puzzle for everyone on Earth."
        case .playing:
            return "Reveal cells, flag mines, and keep the compact board tucked beside your work."
        case .complete:
            return "Daily results lock in after a win or loss, with local stats and a shareable grid."
        }
    }

    var accentColor: Color {
        switch self {
        case .daily:
            return ScreenshotStyle.indigo
        case .playing:
            return ScreenshotStyle.green
        case .complete:
            return ScreenshotStyle.purple
        }
    }

    var eyebrow: String {
        switch self {
        case .daily:
            return "GLOBAL DAILY PUZZLE"
        case .playing:
            return "CONTINUOUS PLAY"
        case .complete:
            return "STATS & STREAKS"
        }
    }

    var bullets: [String] {
        switch self {
        case .daily:
            return ["Same daily board", "Safe opening every day", "No setup required"]
        case .playing:
            return ["Keyboard friendly", "Flag mode included", "Unlimited random boards"]
        case .complete:
            return ["Local stats", "Current and best streaks", "Shareable result grid"]
        }
    }
}

private enum ScreenshotStyle {
    static let backgroundStart = Color(hex: 0x1A1A2E)
    static let backgroundMiddle = Color(hex: 0x16213E)
    static let backgroundEnd = Color(hex: 0x0F3460)
    static let panel = Color(hex: 0x1E293B)
    static let panelHeader = Color(hex: 0x374151)
    static let panelBorder = Color(hex: 0x334155)
    static let cellHiddenTop = Color(hex: 0x4A5568)
    static let cellHiddenBottom = Color(hex: 0x2D3748)
    static let cellHiddenHighlight = Color(hex: 0x718096)
    static let cellHiddenShadow = Color(hex: 0x1A202C)
    static let cellRevealed = Color(hex: 0xE2E8F0)
    static let cellRevealedShadow = Color(hex: 0xCBD5E0)
    static let textPrimary = Color(hex: 0xF3F4F6)
    static let textSecondary = Color(hex: 0x9CA3AF)
    static let textMuted = Color(hex: 0x6B7280)
    static let indigo = Color(hex: 0x818CF8)
    static let indigoDark = Color(hex: 0x667EEA)
    static let purple = Color(hex: 0xC084FC)
    static let green = Color(hex: 0x4ADE80)
    static let blue = Color(hex: 0x60A5FA)
    static let orange = Color(hex: 0xFB923C)
    static let red = Color(hex: 0xDC2626)
}

private extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: opacity
        )
    }
}

@MainActor
enum AppStoreScreenshotExporter {
    private static let canvasSize = CGSize(width: 1440, height: 900)
    private static let scale: CGFloat = 2

    static func exportAll() throws {
        let outputDirectory = outputDirectory()
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        for variant in AppStoreScreenshotVariant.allCases {
            let view = AppStoreScreenshotCanvas(variant: variant)
                .frame(width: canvasSize.width, height: canvasSize.height)
            let renderer = ImageRenderer(content: view)
            renderer.scale = scale

            guard let image = renderer.nsImage,
                  let tiffData = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmap.representation(using: .png, properties: [:])
            else {
                throw CocoaError(.fileWriteUnknown)
            }

            let fileURL = outputDirectory.appendingPathComponent(variant.fileName)
            try pngData.write(to: fileURL, options: .atomic)
            print("Wrote \(fileURL.path)")
        }
    }

    private static func outputDirectory() -> URL {
        if let path = ProcessInfo.processInfo.environment["MENUMINES_SCREENSHOT_OUTPUT_DIR"],
           !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("AppStoreScreenshots", isDirectory: true)
    }
}

private struct AppStoreScreenshotCanvas: View {
    let variant: AppStoreScreenshotVariant

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    ScreenshotStyle.backgroundStart,
                    ScreenshotStyle.backgroundMiddle,
                    ScreenshotStyle.backgroundEnd
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 0) {
                screenshotHero

                HStack(alignment: .center, spacing: 58) {
                    ScreenshotMenuSurface(variant: variant)
                        .shadow(color: .black.opacity(0.44), radius: 38, x: 0, y: 24)

                    copyBlock
                        .frame(width: 520, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 112)
                .padding(.bottom, 74)
            }
        }
        .foregroundStyle(ScreenshotStyle.textPrimary)
    }

    private var screenshotHero: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.grid.3x3.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(variant.accentColor)

            Text("MENU MINES")
                .font(.system(size: 54, weight: .bold, design: .monospaced))
                .foregroundStyle(ScreenshotStyle.indigo)

            Text("A new puzzle every day.")
                .font(.system(size: 22, weight: .medium, design: .monospaced))
                .foregroundStyle(ScreenshotStyle.textSecondary)
        }
        .padding(.top, 52)
        .frame(maxWidth: .infinity)
    }

    private var copyBlock: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(variant.eyebrow)
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundStyle(variant.accentColor)

            Text(variant.title)
                .font(.system(size: 48, weight: .bold, design: .monospaced))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Text(variant.subtitle)
                .font(.system(size: 22, weight: .medium, design: .monospaced))
                .lineSpacing(6)
                .foregroundStyle(ScreenshotStyle.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(variant.bullets, id: \.self) { bullet in
                    HStack(spacing: 10) {
                        Text("✓")
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundStyle(ScreenshotStyle.green)
                        Text(bullet)
                            .font(.system(size: 18, weight: .semibold, design: .monospaced))
                            .foregroundStyle(ScreenshotStyle.textPrimary.opacity(0.9))
                    }
                }
            }
            .padding(.top, 4)

            Text("No ads. No account. No clutter.")
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .foregroundStyle(ScreenshotStyle.textMuted)
                .padding(.top, 2)
        }
        .padding(34)
        .background(ScreenshotStyle.panel.opacity(0.54), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        )
    }
}

private struct ScreenshotMenuSurface: View {
    let variant: AppStoreScreenshotVariant

    private var state: GameState {
        ScreenshotFixture.state(for: variant)
    }

    private var isComplete: Bool {
        state.status == .won || state.status == .lost
    }

    var body: some View {
        VStack(spacing: 12) {
            ScreenshotHeaderView(
                status: state.status,
                elapsedTime: state.elapsedTime,
                flagCount: state.flagCount,
                canReset: state.status != .won
            )

            ScreenshotGameBoardView(
                board: state.board,
                gameStatus: state.status,
                selectedRow: state.selectedRow,
                selectedCol: state.selectedCol,
                isFlagMode: variant == .playing
            )

            ScreenshotFooterView(
                isGameComplete: isComplete,
                puzzleType: .daily,
                isFlagMode: variant == .playing
            )
        }
        .padding()
        .frame(width: 392, height: 520, alignment: .top)
        .background(ScreenshotStyle.panel, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(ScreenshotStyle.panelBorder, lineWidth: 3)
        )
        .foregroundStyle(ScreenshotStyle.textPrimary)
    }
}

private struct ScreenshotHeaderView: View {
    let status: GameStatus
    let elapsedTime: TimeInterval
    let flagCount: Int
    let canReset: Bool

    private var mineCounterDisplay: String {
        String(format: "%03d", max(0, Board.mineCount - flagCount))
    }

    private var statusEmoji: String {
        switch status {
        case .notStarted, .playing:
            return "🙂"
        case .won:
            return "😎"
        case .lost:
            return "😵"
        }
    }

    var body: some View {
        HStack {
            HStack(spacing: 4) {
                Text("🚩")
                Text(mineCounterDisplay)
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
            }
            .frame(minWidth: 82, alignment: .leading)

            Spacer()

            Text(statusEmoji)
                .font(.system(size: 28))
                .opacity(canReset ? 1 : 0.75)

            Spacer()

            Text(elapsedTime.clockString)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .frame(minWidth: 82, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(ScreenshotStyle.panelHeader, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(ScreenshotStyle.panelBorder.opacity(0.75), lineWidth: 1)
        )
    }
}

private struct ScreenshotGameBoardView: View {
    let board: Board
    let gameStatus: GameStatus
    let selectedRow: Int
    let selectedCol: Int
    let isFlagMode: Bool

    var body: some View {
        VStack(spacing: 2) {
            ForEach(0..<Board.rows, id: \.self) { row in
                HStack(spacing: 2) {
                    ForEach(0..<Board.cols, id: \.self) { col in
                        ScreenshotCellView(
                            cell: board.cells[row][col],
                            row: row,
                            col: col,
                            gameStatus: gameStatus,
                            isSelected: row == selectedRow && col == selectedCol,
                            isChordReady: isChordReady(row: row, col: col),
                            isFlagMode: isFlagMode
                        )
                    }
                }
            }
        }
        .padding(12)
        .background(ScreenshotStyle.panel.opacity(0.88), in: RoundedRectangle(cornerRadius: 8))
    }

    private func isChordReady(row: Int, col: Int) -> Bool {
        guard gameStatus == .playing else { return false }
        guard case .revealed(let adjacentMines) = board.cells[row][col].state, adjacentMines > 0 else {
            return false
        }
        return board.adjacentFlagCount(row: row, col: col) == adjacentMines
    }
}

private struct ScreenshotCellView: View {
    let cell: Cell
    let row: Int
    let col: Int
    let gameStatus: GameStatus
    let isSelected: Bool
    let isChordReady: Bool
    let isFlagMode: Bool

    private static let cellSize: CGFloat = 34

    var body: some View {
        ZStack {
            background
            if isChordReady {
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color.accentColor.opacity(0.75), lineWidth: 2)
                    .padding(2)
            }
            content
        }
        .frame(width: Self.cellSize, height: Self.cellSize)
        .overlay(selectionBorder)
    }

    @ViewBuilder
    private var background: some View {
        if cell.isExploded {
            ScreenshotStyle.red
        } else if case .revealed = cell.state {
            ScreenshotStyle.cellRevealed
        } else {
            ScreenshotRaisedCellBackground()
        }
    }

    @ViewBuilder
    private var content: some View {
        if cell.isExploded {
            Text("💣")
                .font(.system(size: 14))
        } else {
            switch cell.state {
            case .hidden:
                EmptyView()
            case .flagged:
                Text("🚩")
                    .font(.system(size: 14))
            case .revealed(let adjacentMines):
                if cell.hasMine {
                    Text("💣")
                        .font(.system(size: 14))
                } else if adjacentMines > 0 {
                    Text("\(adjacentMines)")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundStyle(color(for: adjacentMines))
                }
            }
        }
    }

    @ViewBuilder
    private var selectionBorder: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 2)
                .stroke(ScreenshotStyle.indigoDark, lineWidth: 2)
        }
    }

    private func color(for adjacentMines: Int) -> Color {
        switch adjacentMines {
        case 1:
            return Color(hex: 0x3B82F6)
        case 2:
            return Color(hex: 0x22C55E)
        case 3:
            return Color(hex: 0xEF4444)
        case 4:
            return Color(hex: 0x1E40AF)
        case 5:
            return Color(hex: 0x92400E)
        case 6:
            return Color(hex: 0x0891B2)
        case 7:
            return Color(hex: 0x374151)
        case 8:
            return Color(hex: 0x6B7280)
        default:
            return .primary
        }
    }
}

private struct ScreenshotRaisedCellBackground: View {
    private let bevelWidth: CGFloat = 4

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size.width
            let inset = bevelWidth

            ZStack {
                LinearGradient(
                    colors: [
                        ScreenshotStyle.cellHiddenTop,
                        ScreenshotStyle.cellHiddenBottom
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Path { path in
                    path.move(to: CGPoint(x: 0, y: size))
                    path.addLine(to: CGPoint(x: 0, y: 0))
                    path.addLine(to: CGPoint(x: size, y: 0))
                    path.addLine(to: CGPoint(x: size - inset, y: inset))
                    path.addLine(to: CGPoint(x: inset, y: inset))
                    path.addLine(to: CGPoint(x: inset, y: size - inset))
                    path.closeSubpath()
                }
                .fill(ScreenshotStyle.cellHiddenHighlight.opacity(0.9))

                Path { path in
                    path.move(to: CGPoint(x: size, y: 0))
                    path.addLine(to: CGPoint(x: size, y: size))
                    path.addLine(to: CGPoint(x: 0, y: size))
                    path.addLine(to: CGPoint(x: inset, y: size - inset))
                    path.addLine(to: CGPoint(x: size - inset, y: size - inset))
                    path.addLine(to: CGPoint(x: size - inset, y: inset))
                    path.closeSubpath()
                }
                .fill(ScreenshotStyle.cellHiddenShadow.opacity(0.9))
            }
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
    }
}

private struct ScreenshotFooterView: View {
    let isGameComplete: Bool
    let puzzleType: PuzzleType
    let isFlagMode: Bool

    private var puzzleTypeLabel: String { puzzleType.label }

    private var puzzleTypeIconName: String { puzzleType.iconName }

    var body: some View {
        HStack {
            if isGameComplete {
                Text(String(localized: "share_button"))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(ScreenshotStyle.panel.opacity(0.8), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(ScreenshotStyle.panelBorder, lineWidth: 1)
                    )
                    .fixedSize()
            } else {
                HStack(spacing: 4) {
                    Image(systemName: puzzleTypeIconName)
                        .font(.caption)
                    Text(puzzleTypeLabel)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundStyle(ScreenshotStyle.textSecondary)
                .fixedSize()
            }

            Spacer()

            Image(systemName: isFlagMode ? "flag.fill" : "flag")
                .foregroundStyle(isFlagMode ? ScreenshotStyle.indigo : ScreenshotStyle.textPrimary)

            Image(systemName: "questionmark.circle")
                .foregroundStyle(ScreenshotStyle.textPrimary)

            Image(systemName: "gearshape")
                .foregroundStyle(ScreenshotStyle.textPrimary)
        }
        .font(.system(size: 14, weight: .medium, design: .monospaced))
        .padding(.horizontal, 16)
        .frame(width: 360, height: 48)
        .background(ScreenshotStyle.panelHeader, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(ScreenshotStyle.panelBorder.opacity(0.75), lineWidth: 1)
        )
    }
}

private enum ScreenshotFixture {
    static func state(for variant: AppStoreScreenshotVariant) -> GameState {
        switch variant {
        case .daily:
            let state = GameState(
                board: Board(seed: AppStoreScreenshotVariant.seed),
                dailySeed: AppStoreScreenshotVariant.seed,
                puzzleType: .random
            )
            state.selectedRow = 4
            state.selectedCol = 4
            return state
        case .playing:
            let board = playingBoard()
            let state = GameState(
                board: board,
                dailySeed: AppStoreScreenshotVariant.seed,
                puzzleType: .random
            )
            state.status = .playing
            state.elapsedTime = 94
            state.flagCount = board.flagCount
            state.selectedRow = 5
            state.selectedCol = 6
            return state
        case .complete:
            let state = GameState(
                board: completedBoard(),
                dailySeed: AppStoreScreenshotVariant.seed,
                puzzleType: .random
            )
            state.status = .won
            state.elapsedTime = 187
            state.flagCount = Board.mineCount
            state.selectedRow = 0
            state.selectedCol = 0
            return state
        }
    }

    private static func playingBoard() -> Board {
        var board = Board(seed: AppStoreScreenshotVariant.seed)
        board.clearAreaForOpening(centerRow: 4, centerCol: 4, seed: AppStoreScreenshotVariant.seed)

        for (row, col) in [(4, 4), (1, 6), (7, 2)] where !board.cells[row][col].hasMine {
            _ = board.reveal(row: row, col: col)
        }

        var flagsPlaced = 0
        for row in 0..<Board.rows {
            for col in 0..<Board.cols where board.cells[row][col].hasMine && flagsPlaced < 4 {
                board.toggleFlag(row: row, col: col)
                flagsPlaced += 1
            }
        }

        return board
    }

    private static func completedBoard() -> Board {
        let source = Board(seed: AppStoreScreenshotVariant.seed)
        var cells = source.cells

        for row in 0..<Board.rows {
            for col in 0..<Board.cols {
                if cells[row][col].hasMine {
                    cells[row][col].state = .flagged
                } else {
                    cells[row][col].state = .revealed(adjacentMines: source.adjacentMineCount(row: row, col: col))
                }
            }
        }

        return Board(cells: cells)
    }
}
#endif
