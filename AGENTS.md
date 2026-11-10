# MenuMines - Development Guide

## Project Overview

MenuMines is a menu bar Minesweeper game for macOS. It features a 9x9 board with 12 mines, generating the same daily puzzle for all players using deterministic seeding.

## Technology Stack

- **Language:** Swift 5.9+
- **UI Framework:** SwiftUI
- **Target:** macOS 14+ (Sonoma) - required for @Observable macro
- **Key APIs:**
  - `NSStatusItem` and a non-activating `NSPanel` hosting SwiftUI (`MenuBarExtra` can't be opened, closed or given focus reliably)
  - `GameplayKit` `GKLinearCongruentialRandomSource` for seeded RNG
  - `.focusable()` + `.onKeyPress` on the board for keyboard input
  - `SMAppService.mainApp` for Launch at Login (no UserDefaults — system is source of truth)

## Directory Structure

```
MenuMines/
├── MenuMinesApp.swift          # App entry point, lifecycle and the menu bar icon view
├── AppWindows.swift            # Stats, Settings and About windows
├── StatusItemController.swift  # Menu bar icon and game panel: opening, closing, dismissal
├── StatusItemController+Position.swift # Where the panel goes: always under the icon
├── StatusItemController+Menu.swift # The icon's right-click menu
├── GamePanel.swift             # The non-activating panel and its material backdrop
├── StatusIcon.swift            # Template image for the menu bar icon, kept in step with the game
├── GlobalHotKey.swift          # Optional global shortcut that opens the panel (Carbon hot key)
├── Constants.swift             # UserDefaults keys for settings
├── UpdateManager.swift         # Build channel detection; Sparkle, direct build only
├── AppStoreScreenshotExporter.swift # Debug-only mock-up that renders AppStoreScreenshots/
├── Info.plist, Info-Direct.plist
├── MenuMines.entitlements, MenuMines-Direct.entitlements, MenuMines-Dev.entitlements
├── PrivacyInfo.xcprivacy
├── Models/
│   ├── AccessibilityAnnouncer.swift # Debounced VoiceOver announcements, cell descriptions
│   ├── Board.swift             # 9x9 grid, mine placement, reveal logic
│   ├── Cell.swift              # Cell state enum
│   ├── DailyBoard.swift        # UTC seed/date conversion, daily completion and per-day stats
│   ├── DailyHistory.swift      # Launch date, which past days can be played and how
│   ├── DayWatcher.swift        # Rolls the game over at UTC midnight, wake and clock change
│   ├── GameResult.swift        # Win/loss result with timing, and PuzzleType
│   ├── GameState.swift         # @Observable game state
│   ├── MenuBarIconState.swift  # Menu bar icon state machine
│   ├── GamePersistence.swift   # Snapshots and restore rules
│   ├── GameTimer.swift         # Monotonic game clock, MM:SS formatting
│   ├── Leaderboard.swift       # Game Center, App Store build only
│   ├── ShareTextGenerator.swift # Spoiler-free share text and play strip
│   ├── StatsStore.swift        # Persistent stats storage
│   ├── StatsStore+PastDailies.swift # Past-daily results: metrics, recording, merging
│   ├── StatsSync.swift         # iCloud key-value sync, App Store build only
│   └── Telemetry.swift         # The only file that talks to Sentry
├── Views/
│   ├── AboutWindow.swift       # About window
│   ├── CellView.swift          # One cell: state, accessibility, hover/press and motion
│   ├── CellTile.swift          # Tiles, flag and mine glyphs, number colours, the cell's click view
│   ├── ConfettiView.swift      # Win celebration animation
│   ├── ControlsPopoverView.swift # The footer's keyboard and mouse help
│   ├── FooterView.swift        # Share, flag mode, controls help and the gear menu
│   ├── FooterIconButtons.swift # The footer's hover-backed icon button and toggle styles
│   ├── GameBoardView.swift     # 9x9 grid of cells
│   ├── HeaderView.swift        # Timer, flag count, reset
│   ├── MenuContentView.swift   # Game panel content and keyboard handling
│   ├── SettingsView.swift      # App settings
│   ├── ShortcutRecorderView.swift # Records the global shortcut in Settings
│   └── StatsWindow.swift       # Statistics, and the Daily History calendar where past days are picked
├── Resources/
│   ├── Assets.xcassets         # App icons (AppIcon, AppIcon-Dev), accent color
│   └── en.lproj/Localizable.strings
MenuMinesTests/                 # XCTest and Swift Testing suites, hosted by the Debug app
├── AuditRegressionTests.swift  # Daily lifecycle, timer, leaderboard, iCloud sync, sharing, puzzle day
├── BoardTests.swift, DailyBoardTests.swift, DailyBoardFairnessTests.swift
├── DailyCompletionTests.swift, DailyRolloverTests.swift
├── DailyHistoryTests.swift     # Launch bound, and which days are playable, practice or unavailable
├── GamePanelTests.swift        # Real key events sent to a real panel; windows, menus, icon
├── GlobalShortcutTests.swift   # Shortcut validation, storage and registration
├── GamePanelPastDayTests.swift # Same suite: Daily History to the panel
├── PastDaily*Tests.swift       # Play, recording, progress, replays, stats, iCloud, rules and compatibility
├── PastDailyTestHelpers.swift
├── GameState*Tests.swift       # Basic, chord, Codable, pause, persistence, selection, share, timer, win/lose
├── GameStateTestHelpers.swift
├── MenuBarIconStateTests.swift, SettingsTests.swift, SettingsViewLayoutTests.swift
└── StatsStoreTests.swift
scripts/                        # test.sh, set-version.sh, release-direct.sh
Tools/app_store_connect_signing.rb # Signing assets for the App Store release workflow
docs/APPSTORE_SETUP.md          # App Store Connect setup and screenshots
```

## Project File and Build Identities

`project.yml` is the source of truth for the Xcode project; edit it and run `xcodegen generate`.
The generated `MenuMines.xcodeproj` stays committed so CI doesn't need XcodeGen.

| Configuration | Bundle ID | Icon | iCloud / Game Center / Sparkle |
| --- | --- | --- | --- |
| Debug | `com.merimerimeri.MenuMines.dev` | `AppIcon-Dev` | None |
| Release | `com.merimerimeri.MenuMines` | `AppIcon` | iCloud, Game Center |
| Release-Direct | `com.merimerimeri.MenuMines` | `AppIcon` | Sparkle |

Debug has its own identity so it can't touch a real install's defaults, stats or iCloud data.
Because Debug compiles none of the service code, `scripts/test.sh` also builds both shipping
configurations.

## Key Patterns

### Game Logic is Pure Swift
All game logic (`Board`, `Cell`, `GameState`) has no UI dependencies. This enables comprehensive unit testing without SwiftUI test harnesses.

### Views are Stateless
Views read from `@Observable GameState` and call methods on it. No view-local game state.

### Daily Seed Formula
```swift
// IMPORTANT: Use UTC timezone so all players get same puzzle globally
var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(identifier: "UTC")!
let seed = Int64(year * 10000 + month * 100 + day)
// Example: 2024-03-15 → 20240315
```

### Menu Bar Shell
AppKit owns the shell and SwiftUI draws the content. `StatusItemController` runs the icon and the
non-activating game panel, and `AppWindows` builds Stats, Settings and About. Each panel open makes
a new hosting controller, because `MenuContentView`'s `onAppear`/`onDisappear` start and stop the
game clock. The SwiftUI `Settings` scene is an empty placeholder, since an app must declare a scene.
`GamePanelTests` sends real key events to a real panel, so run them after changing focus handling.

- **Icon:** `StatusIconUpdater` draws a template `NSImage` per `MenuBarIconState` (an SF Symbol
  grid with a badge in a punched-out ring) into the square status item, following the game by
  observation and the settings through user defaults. The button stays highlighted while the panel
  is up. Only a right-click or a Control-*click* opens the icon's menu: VoiceOver presses with
  Control held and must open the game. The menu carries the gear menu's app-wide items (keep the
  two in step); Reset and Back to Today stay in the gear menu.
- **Panel:** opens instantly and fades out over 0.15s (no fade under Reduce Motion). `isOpen` turns
  false and the clock pauses the moment it starts closing; input is dropped during the fade, and
  opening again during the fade brings the same content straight back (a new host there would have
  the old one's disappear pause the clock after the new one's appear). The content sits on Liquid Glass (`NSGlassEffectView`) on
  macOS 26 and the popover material with a hairline outline before it (`PanelBackdropController`);
  `MenuContentView` has no background of its own, and the board has a solid plate. Esc and ⌘W close
  it. It also closes on a Space change, another app activating, display sleep, screen lock and a
  user switch, and follows the icon when the screens change.
- **Position:** the panel always hangs directly under the icon, centred on it and clamped to the
  icon's screen, whichever way it opens (click, shortcut, relaunch, `openFromWindow`). The icon's
  frame is read afresh each time (`iconAnchor`), and content that changes height keeps the top edge
  pinned and grows downwards. Only when the button has no window, its window isn't up, or it lies
  off every screen (a hidden icon) does it fall back to the top middle of the main screen.
  `StatusItemController.panelOrigin(for:under:fallbackScreen:)` is pure, and tested as such.
- **Ways in:** a click, the optional global shortcut (`GlobalHotKey`, off by default, set in
  Settings, saved under `Constants.SettingsKeys.globalShortcut`), and launching the app again from
  Finder or Spotlight (`applicationShouldHandleReopen`). The last two leave the app active when one
  of its windows is in front, so they open as `openFromWindow` does and closing gives focus back.
- **Windows:** Stats, Settings and About can't be minimised, join the active Space over full-screen
  apps, and Stats and Settings reopen where they were left. A closed window's controller is let go.
  `yieldFocusIfNoWindowsRemain` hides the app only when no titled window of any kind (Sparkle,
  Game Center, alerts) is left besides the closing one. The main menu routes About, ⌘, and ⌘W to
  the app's own windows, since the SwiftUI `Settings` scene is a placeholder.

### Board and Panel Content

- **Look:** covered cells are raised tiles (`RaisedTile`, continuous corners, top highlight), opened
  cells flat (`RecessedTile`: lighter than the plate in light mode, set into it in dark), on a solid
  `BoardPlate`. Numbers are SF Rounded bold in system colours (`NumberPalette`); the flag is the
  `flag.fill` symbol in system red everywhere (`FlagGlyph`) and the mine is drawn (`MineGlyph`).
  After a loss a flag on a safe cell shows as `flag.slash.fill`, and VoiceOver says so. With
  Increase Contrast, tile edges and digits get heavier. Nothing on the board is colour-only.
- **Hit areas:** cells sit edge to edge (`CellMetrics.size` 29pt) and draw their gap inside, so no
  click lands between cells. `ClickableNSView` accepts the first mouse; left click reveals on
  release, right/Control-click flags on press, middle click chords. A covered cell draws sunken
  while held. Hover and press feedback only while the game is in play.
- **Keyboard:** arrows, Space or Return, F. The selection ring shows once the player steers by
  keyboard, including when Tab (Keyboard Navigation) brings focus back to the board.
- **Redraws:** only `GameClockText` in the header reads `elapsedTime`, and `CellView` is
  `Equatable`, so the clock's tick doesn't rebuild the board. Keep body reads of `elapsedTime` out
  of `MenuContentView`.
- **Motion:** reveals are instant. Flags pop in over 0.12s, a lost game's mines spread from the one
  that went off over about 0.2s, the reset confirmation fades in, confetti eases and is cleared when
  a new board arrives. All of it is off under Reduce Motion (read from the environment).
- **Footer:** icon buttons are 24pt with a hover backing; flag mode is a toggle. Share hands over the
  result's text (and drags it), Copy puts it on the clipboard and keeps its width when it says
  Copied. On a finished past day, Back to Today shrinks to an icon so the footer fits the board.
  The reset confirmation's default button is Cancel.

Picking a day in Daily History goes through `AppWindows.playPastDay`: Stats closes and the panel
opens on that board (`StatusItemController.openFromWindow`). The app is still active at that
point because Stats activated it, so `AppWindows.yieldFocusIfNoWindowsRemain` leaves it alone while
the panel is up, and closing the panel is what hands focus back.

### Agent App Configuration
Set `LSUIElement = YES` in Info.plist to hide from Dock. The UI must provide a Quit button since there's no Dock icon to right-click. `LSApplicationCategoryType` is set to `public.app-category.utilities` (not `puzzle-games`) to prevent macOS Game Mode from activating.

## Direct Distribution & Sparkle Auto-Updates

The app ships two variants: **App Store** (MenuMines target) and **Direct** (MenuMinesDirect target). The Direct build uses Sparkle 2.x for auto-updates.

### How Updates Work

- **DMG** is for first-time manual downloads (drag-to-Applications UX)
- **ZIP** is for Sparkle auto-updates — Sparkle handles ZIP natively without XPC installer services
- The `appcast.xml` `<enclosure>` points to the ZIP, not the DMG
- Release notes use inline `<description><![CDATA[...]]></description>` in the appcast (not `<sparkle:releaseNotesLink>` which renders the full GitHub page in Sparkle's WebKit view)
- Custom release notes can be passed via `RELEASE_NOTES_HTML` env var; defaults to a generic message

### Entitlements

The two targets use separate entitlements files:

- `MenuMines.entitlements` — App Store target: sandboxed (`com.apple.security.app-sandbox`)
- `MenuMines-Direct.entitlements` — Direct target: **not sandboxed**, only `network.client`

The Direct build must NOT be sandboxed. Sparkle's installer fails with sandbox enabled because its XPC services cannot communicate through the sandbox boundary. The App Store target stays sandboxed as required by Apple.

### Release Flow

Both `scripts/release-direct.sh` and `.github/workflows/release-direct.yml` follow the same pipeline:

1. Build & archive with `MenuMines-Direct` scheme / `Release-Direct` configuration
2. Notarize the app, then create and notarize the DMG
3. Create a ZIP from the same staged `MenuMines.app` for Sparkle
4. Sign the **ZIP** (not DMG) with Sparkle's `sign_update` tool
5. Generate `appcast.xml` with inline release notes and ZIP enclosure
6. Upload DMG + ZIP + appcast to GitHub release

### Key Files

- `MenuMines/Info-Direct.plist` — `SUFeedURL`, `SUPublicEDKey`, `SUEnableAutomaticChecks`
- `MenuMines/UpdateManager.swift` — `SPUStandardUpdaterController` init (behind `SPARKLE_ENABLED` flag)
- `MenuMines/MenuMines-Direct.entitlements` — unsandboxed entitlements for Direct build

## Releasing

See the [Distribution section in README.md](README.md#distribution) for release workflows, tag conventions, and required GitHub Secrets.

## Build Commands

```bash
# Regenerate the project, run tests, and build both shipping configurations
scripts/test.sh

# Build release
xcodebuild -scheme MenuMines -configuration Release

# Run tests (code signing must be disabled to avoid Team ID mismatch errors)
xcodebuild test -scheme MenuMines CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=""

# Clean build
xcodebuild clean -scheme MenuMines
```

## Testing Requirements

**Tests must always be run:**
- After any substantive code change, even if not explicitly asked
- Before every commit

This is non-negotiable. CI runs on PRs, but only after a push, so a local run comes first.

## Accessibility

MenuMines must be fully playable with VoiceOver. Accessibility is a core requirement, not an afterthought.

### Required Accessibility Features

1. **Cell Labels** - Every cell needs a descriptive accessibility label:
   - Hidden cells: "Row X, Column Y, covered" or "Row X, Column Y, flagged"
   - Revealed cells: "Row X, Column Y, [number] adjacent mines" or "Row X, Column Y, empty"
   - Mines: "Row X, Column Y, mine"

2. **State Announcements** - Use `AccessibilityNotification.Announcement` to announce:
   - Game win: "Congratulations! You won in X seconds"
   - Game loss: "Game over. You hit a mine"
   - Timer updates (on demand, not continuously)

3. **Keyboard Navigation** - Already implemented via arrow keys + Space/Return/F (see Controls)

4. **Control Labels** - All buttons need accessibility labels:
   - Reset button: "Reset game"
   - Timer display: "Elapsed time: X seconds"
   - Mine counter: "X mines remaining"

### Implementation Notes

```swift
// Cell accessibility label example
.accessibilityLabel(cellAccessibilityLabel(row: row, col: col, cell: cell))
.accessibilityHint("Double-tap to reveal, or use F to flag")

// State announcement example
AccessibilityNotification.Announcement("Game over").post()
```

### Testing Accessibility

Use these tools to verify accessibility:
- **Accessibility Inspector** (Xcode → Open Developer Tool): Check labels and traits
- **VoiceOver** (Cmd+F5): Play through the entire game with VoiceOver enabled
- Test all game states: initial, in-progress, won, lost

## Code Style

- SwiftLint with default rules (`swiftlint lint MenuMines MenuMinesTests`). Nothing runs it automatically and the tree
  doesn't lint clean yet, mostly short `r`/`c` loop names, so the rule for now is not to add violations
- No force unwraps (`!`) - use `guard let` or `if let`
- Prefer `struct` over `class` where possible
- Use `@Observable` (Swift 5.9) over `@ObservableObject`

## Game Constants

- Board size: 9x9 (81 cells)
- Mine count: 12
- **Daily puzzles**: the board is fully determined by the seed and is never modified during
  play. Mines are placed avoiding a seed-derived opening cell. The board starts fully covered
  and that cell is marked with a dot (`GameState.startHint`) until the first reveal, so every
  player can start from the identical position. Opening a mine loses — nothing is relocated
  to protect the player. Flags can be placed before the first reveal; they don't start the clock.
- **Past dailies and replays**: an earlier day's board, by the daily rules above. Nothing is
  relocated (`PuzzleType.usesDailyBoard`).
- **Random puzzles**: first click is always safe; mines are relocated out of a 3x3 around the
  click via `clearAreaForOpening`, so the board depends on where the player clicked.

The split exists because relocating mines around the first click made two people playing the
same daily play *different* boards. Do not
reintroduce relocation for daily puzzles — `DailyBoardFairnessTests` guards this.

## Workflow

### Linear
User stories are tracked in Linear under the MenuMines project.

**Before starting work:**
1. Move the issue to "In Progress" status
2. Read the full issue description to understand acceptance criteria
3. Check blocking issues are resolved

**While working:**
- Commit incrementally as you complete parts of the story
- Update AGENTS.md with new learnings or instructions

**When done:**
- Ensure all acceptance criteria are met
- Leave the issue in "In Progress" status (do NOT move to "Done" - another process handles that)

### Linear Details
- Organization: `merimerimeri`
- Project: MenuMines (`sweep-f5976e94df09`)
- Issue prefix: `MER` (e.g., `MER-23`)
- Workflow: Todo → In Progress → Done

### Subagent Models
- Use Fable only for planning: designing an approach, auditing, investigating a root cause.
- Use Opus or Sonnet for execution: editing code, running tests, making the changes.

## State Management Rules

The app maintains consistent behavior across resume, pause, completion, and recovery scenarios.

### Puzzle Types

| `PuzzleType` | What it is | Recorded | Streaks, daily stats, leaderboard | Reset |
| --- | --- | --- | --- | --- |
| `.daily` | Today's board, started on its day (may be finished after it, see below) | `StatsStore.results`, once per day | Yes (leaderboard only if finished on the day) | Locked once started |
| `.random` | Continuous play after the daily | `StatsStore.results`, every game | All-games stats only | Free |
| `.pastDaily` | An earlier day with no result, played for the first time | `StatsStore.pastDailyResults`, once per day | Never | Locked once started |
| `.practice` | An earlier day that already has a result | Never | Never | Free |

**Streaks mean "played on the day", and that is kept by storage, not by filtering.** Past-daily
results live in their own array, UserDefaults key and iCloud keys. Nothing that computes streaks,
daily stats, all-games stats or the leaderboard reads them, so a missed day can be filled in on
the calendar without ever joining or repairing a streak. Do not move them into `results`.

- Past days run from `DailyHistory.launchSeed` (2026-01-31, the day v1.0.0 was published) through
  yesterday, UTC. Earlier days, today and future days can't be picked.
- `GameState.playPastDay(seed:)` is the one way in. A day with no result starts or resumes a
  `.pastDaily`, and a day with a result of either kind is a `.practice` replay.
- If a day has both an on-the-day result and a past-daily result (two Macs, before syncing), the
  on-the-day one is shown and counted. `pastDailyResults` leaves that day out, so no day counts twice.
- A past daily never touches `dailyCompletionSeed`, `dailyStats_<seed>` or the menu bar icon's
  "today" state, and is never submitted to Game Center.
- Daily History is the only way to an earlier day. The panel doesn't offer one: an earlier
  "Play a Missed Day" button and gear-menu item duplicated the calendar and were removed.
  Continuous play is unchanged: reset still deals a random board.
- A random game under way when the player goes to a past day is held in memory (never on disk) and
  Back to Today returns to it, if continuous play is still on, today is still done and no daily is
  under way. Otherwise Back to Today goes to today's puzzle as usual.
- Versions up to 1.0.22 can't decode `"pastDaily"`. Past dailies are only ever written under keys
  those versions don't read, so keep them out of `gameSnapshot`, `gameSnapshot.daily`,
  `gameResults` and the `results.*` iCloud keys.

### Carried-Over Dailies

A daily started before UTC midnight and still `.playing` afterwards is **carried over**. It's the
player's one attempt at that day, so it's treated as that day's game in progress everywhere:

- **It stays a `.daily` and counts on its day.** Finishing it records an on-the-day result for its
  seed (streak, daily stats, `dailyCompletionSeed` only moves forward), whenever it's finished. It's
  never submitted to Game Center, which only takes a win finished on the day itself. The rule is
  simply "started on its day": it doesn't depend on continuous play, relaunches or visiting other days.
- **It's never dropped.** It lives in `gameSnapshot` (or on the board) until it's finished. Launch
  restores it whichever way continuous play is set (`restoreFreshGame` used to drop it with continuous
  play on), rollover never clears it, and Back to Today from a past day returns to it.
- **It can't be reset.** Today's puzzle waits until it's finished.
- **There's never a second attempt at its board.** `GameState.playPastDay` puts the carried-over game
  back when its day is picked, instead of starting a `.pastDaily`, and clears any `gameSnapshot.past.<seed>`
  for that day. Daily History shows the day as `DailyHistory.Day.carriedOver` (in progress, "counts as
  played on the day"), ahead of any result synced from another Mac, because picking it always resumes
  this game. It's in `pastDailySeedsInProgress`.
- `GameSnapshot.carriedOverDaily(todaySeed:)` and `GameState.carriedOverDailySeed` find it.

Why not convert it into a `.pastDaily`: midnight UTC falls in the afternoon or evening for much of the
world, so games that span it are common, and they've always counted on their day. Converting only on
some paths (say, a relaunch with continuous play on) would make the same game count differently
depending on the setting.

### Completion
- **Completion = win or loss**: A daily puzzle is complete when the game status becomes `.won` or `.lost`
- Both outcomes mark `dailyCompletionSeed` in UserDefaults
- Both outcomes record stats (once per day, deduped by seed)

### Timer Behavior
- **Starts**: On first `reveal()` call (not on flag)
- **Pauses**: When menu bar popover closes (`onDisappear`)
- **Resumes**: When popover reopens (`onAppear`) if status is `.playing`, and whenever another board is
  put in an open panel (Back to Today, and `AppWindows.playPastDay`, which can run
  with the panel already up when a calendar tile is activated from the keyboard or VoiceOver).
  `resumeTimer()` leaves a running clock alone, so a second call is harmless
- **Stops**: On win, loss, or reset

### Reset Lock
- Once today's puzzle is complete (win or loss), reset is disabled for the rest of the day
- Today's daily also can't be reset once started, because a reset would be a free retry at a ranked board
- A daily carried over from an earlier day can't be reset either: dropping it would leave its day
  unplayed, free to start again as a recorded past daily on a board the player has seen
- `canReset` returns false for any `.playing` daily, and otherwise checks `isDailyPuzzleComplete()` using UTC date
- A past daily can't be reset once its first cell is revealed, for the same reason. Before that a reset
  only clears flags, and once it's finished a reset replays the board as unrecorded practice
- A replay (`.practice`) can always be reset
- Enforced in: HeaderView emoji, FooterView menu, keyboard shortcut (⌘R)

### Persistence

**Storage Keys:**
- `gameSnapshot`: Active game state (cleared when starting random puzzles). A daily, today's or carried
  over, is saved here after every move (reveal, chord, flag) while it's under way, so a crash or force
  quit never rolls it back or hands out a fresh board
- `gameSnapshot.daily`: Completed daily puzzle with full board state (preserved until day changes)
- `dailyCompletionSeed`: Tracks if today's puzzle was completed
- `dailyStatsRecordedSeed`: Prevents duplicate stats recording
- `dailyStats_<seed>`: Stores DailyStats struct for each completed day
- `gameSnapshot.past.<seed>`: A past daily left in progress, one per day. Written after every move
  and whenever the game is left, cleared when it's finished. This is what stops a restart being a retry.
  Never exists for a day that has a carried-over daily
- `gameResults`: On-the-day daily results and random results (`StatsStore.results`)
- `pastDailyResults`: Past-daily results (`StatsStore.storedPastDailyResults`), one per day
- `statsResetAt`: When statistics were last erased. Covers both kinds of result

**iCloud keys (App Store build):** `results.<yyyymm>` for on-the-day results, `past.<yyyymm>` for
past dailies, `statsResetAt`, and the read-only legacy `dailyResults`. Both kinds merge the same
way: one result per day, the first finished.

**IMPORTANT: The daily namespace (`gameSnapshot.daily`) is absolutely necessary.**

When a user completes a daily puzzle with continuous play ON, then plays random puzzles, then turns continuous play OFF, they must see their completed daily puzzle with the exact revealed cell pattern—not a fresh hidden board. The stats fallback only stores metadata (won/lost, time, flags) but NOT the board state. The daily namespace preserves the full board state so the visual representation is correct when toggling continuous play off.

Do NOT attempt to simplify by removing the daily namespace in favor of stats-only restoration.

### Error Recovery
When app launches:
0. A daily in progress always comes back, today's or carried over from an earlier day, whichever way
   continuous play is set. Otherwise a launch starts on today: a past daily in progress waits under
   its own key until its day is picked again from Daily History
1. Try to load snapshot → restore full state if valid and today's seed
2. If snapshot missing/corrupted but daily complete → restore from stats (won/lost, time, flags)
3. Otherwise → fresh game with today's board

### Share Text
Boards are identical for everyone, so a grid would hand out the solution. Share text carries a
strip of `PlayStep`s (opens, cascades, chords, flags) describing how the player got there, and
says nothing about where. The header says what kind of game it was: a past daily names its day and
adds "(played later)", and a replay says it's a replay.

### Share Availability
- Share button visible when `status == .won || status == .lost`
- Persists after relaunch because snapshot preserves status

### Daily Seed
```swift
// All date-based logic uses UTC timezone
let seed = Int64(year * 10000 + month * 100 + day)
// Example: 2026-01-25 → 20260125
```

## Testing Strategy

Core game logic must be thoroughly tested since we use concrete types without protocols. Test the actual classes directly—no mocks needed.

**Required coverage:**
- Unit test all game logic (Board, GameState, DailyBoard functions)
- Test win/lose conditions
- Test reveal cascading behavior
- Test first-click safety on random puzzles (mine relocation)
- Test timer start/pause/resume behavior
- Test deterministic seeding produces identical boards
- Test UTC timezone consistency (same Date produces same seed regardless of local timezone)
- Test keyboard selection movement and bounds

**Accessibility testing (required before release):**
- Verify all cells have correct accessibility labels
- Test full game flow with VoiceOver enabled (Cmd+F5)
- Confirm win/loss announcements are spoken
- Verify keyboard navigation works with VoiceOver focus

**Optional:**
- UI testing (focus on logic correctness first)

## Localization

The app is structured to support future localization. Follow these guidelines to keep it localization-ready.

### String Handling

**Never hard-code user-facing strings.** All text shown to users must go through the localization system:

```swift
// ❌ Bad - hard-coded string
Text("Reset")
Button("Quit") { ... }

// ✅ Good - uses String Catalog / Localizable.strings
Text("reset_button", tableName: "Localizable")
Button(String(localized: "quit_button")) { ... }
```

**Emojis are locale-independent** and don't need localization: 🚩 (share text), 🙂, 😮, 😎, 😵, 🎉

### Localizable.strings

All user-facing text is in `MenuMines/Resources/en.lproj/Localizable.strings`. This includes strings for buttons, menu items, accessibility labels, share text, and stats display.

When adding new user-facing strings:
1. Add the key-value pair to `Localizable.strings`
2. Use `String(localized:)` or `Text(_:tableName:)` in code
3. Use descriptive keys that indicate purpose, not content

### Date and Number Formatting

**Use locale-aware formatters** for user-facing dates and numbers:

```swift
// ❌ Bad - assumes specific locale format
let dateString = "\(month)/\(day)/\(year)"
let priceString = "$\(amount)"

// ✅ Good - respects user's locale
let dateString = date.formatted(date: .abbreviated, time: .omitted)
let priceString = amount.formatted(.currency(code: "USD"))
```

**Exception:** The game timer (`%02d:%02d`) is intentionally locale-independent since `MM:SS` is a universal stopwatch format, not a localized time display.

**Exception:** The daily seed calculation must always use UTC timezone to ensure all players worldwide get the same puzzle - this is not a localization concern but a game design requirement.

### Testing Localization

When adding localized strings:
- Test with different system languages to catch layout issues
- Verify strings don't get truncated in UI
- Check that emojis render correctly across locales
