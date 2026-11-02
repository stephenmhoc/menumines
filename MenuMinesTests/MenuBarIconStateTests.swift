import AppKit
import Foundation
import Testing
@testable import MenuMines

@Suite("Build Channel Tests")
struct BuildChannelTests {

    @Test("A Sparkle build is the direct download regardless of anything else")
    func testSparkleBuildIsDirect() {
        #expect(resolveBuildChannel(isSparkleBuild: true, hasStoreReceipt: false, isTestFlightSigned: false) == .direct)
        #expect(resolveBuildChannel(isSparkleBuild: true, hasStoreReceipt: true, isTestFlightSigned: true) == .direct)
    }

    @Test("A receipt plus the TestFlight certificate is a TestFlight build")
    func testTestFlightBuild() {
        #expect(resolveBuildChannel(isSparkleBuild: false, hasStoreReceipt: true, isTestFlightSigned: true) == .testFlight)
    }

    @Test("A receipt without the TestFlight certificate is the App Store build")
    func testAppStoreBuild() {
        #expect(resolveBuildChannel(isSparkleBuild: false, hasStoreReceipt: true, isTestFlightSigned: false) == .appStore)
    }

    @Test("No receipt means no store delivered it, so it is not claimed as App Store")
    func testNoReceiptIsNotAppStore() {
        let channel = resolveBuildChannel(isSparkleBuild: false, hasStoreReceipt: false, isTestFlightSigned: false)
        #expect(channel == .development)
        #expect(channel != .appStore, "Mislabelling a local build as the shipped one is the failure that matters")
    }

    @Test("Pre-release channels are the ones flagged to the user")
    func testPreReleaseFlagging() {
        #expect(BuildChannel.testFlight.isPreRelease)
        #expect(BuildChannel.development.isPreRelease)
        #expect(!BuildChannel.appStore.isPreRelease)
        #expect(!BuildChannel.direct.isPreRelease)
    }

    @Test("Every channel has a non-empty name")
    func testChannelsAreNamed() {
        for channel in [BuildChannel.development, .direct, .testFlight, .appStore] {
            #expect(!channel.displayName.isEmpty)
        }
    }
}

@Suite("Modal Hang Filter Tests")
struct ModalHangFilterTests {

    /// The frames Sparkle's update prompt produced in MENUMINES-4, innermost last.
    private let sparkleAlertFrames = [
        "_dispatch_main_queue_drain",
        "-[NSAlert runModal]",
        "_NSTryRunModal",
        "-[NSApplication runModalForWindow:]",
        "-[NSApplication _doModalLoop:peek:]",
        "-[NSApplication(NSEventRouting) nextEventMatchingMask:untilDate:inMode:dequeue:]",
        "mach_msg2_trap"
    ]

    @Test("A hang that is really a modal dialog is dropped")
    func testModalHangIsDropped() {
        #expect(isModalWaitStack(
            exceptionType: "App Hanging",
            mechanismType: "AppHang",
            frameFunctions: sparkleAlertFrames
        ))
    }

    @Test("A genuine main thread stall is kept")
    func testGenuineHangIsKept() {
        #expect(!isModalWaitStack(
            exceptionType: "App Hanging",
            mechanismType: "AppHang",
            frameFunctions: [
                "_dispatch_main_queue_drain",
                "MenuMines.GameState.reveal(row:col:)",
                "MenuMines.Board.reveal(row:col:)"
            ]
        ))
    }

    @Test("Non-hang events are never dropped, even from a modal stack")
    func testNonHangEventsAreKept() {
        #expect(!isModalWaitStack(
            exceptionType: "NSInvalidArgumentException",
            mechanismType: "NSException",
            frameFunctions: sparkleAlertFrames
        ))
    }

    @Test("The hang is recognised from either the mechanism or the exception type")
    func testHangRecognisedFromEitherField() {
        #expect(isModalWaitStack(
            exceptionType: nil,
            mechanismType: "AppHang",
            frameFunctions: sparkleAlertFrames
        ))
        #expect(isModalWaitStack(
            exceptionType: "App Hanging",
            mechanismType: nil,
            frameFunctions: sparkleAlertFrames
        ))
    }

    @Test("An empty stack is kept rather than guessed at")
    func testEmptyStackIsKept() {
        #expect(!isModalWaitStack(exceptionType: "App Hanging", mechanismType: "AppHang", frameFunctions: []))
    }
}

@Suite("MenuBarIconState Tests")
struct MenuBarIconStateTests {

    // MARK: - Icon State Derivation Tests

    @Test("Complete icon when daily complete and game not started")
    func testCompleteIconWhenDailyCompleteAndNotStarted() {
        let state = menuBarIconState(
            gameStatus: .notStarted,
            isPaused: false,
            isDailyComplete: true
        )
        #expect(state == .complete)
    }

    @Test("Incomplete icon when daily not complete and game not started")
    func testIncompleteIconWhenDailyNotComplete() {
        let state = menuBarIconState(
            gameStatus: .notStarted,
            isPaused: false,
            isDailyComplete: false
        )
        #expect(state == .incomplete)
    }

    @Test("Paused icon when game is playing and paused")
    func testPausedIconWhenPlayingAndPaused() {
        let state = menuBarIconState(
            gameStatus: .playing,
            isPaused: true,
            isDailyComplete: false
        )
        #expect(state == .paused)
    }

    @Test("Playing icon when game is playing and not paused")
    func testPlayingIconWhenPlayingAndNotPaused() {
        let state = menuBarIconState(
            gameStatus: .playing,
            isPaused: false,
            isDailyComplete: false
        )
        #expect(state == .playing)
    }

    @Test("Lost icon when game is lost")
    func testLostIconWhenGameLost() {
        let state = menuBarIconState(
            gameStatus: .lost,
            isPaused: false,
            isDailyComplete: false
        )
        #expect(state == .lost)
    }

    @Test("Lost icon takes priority over paused")
    func testLostIconTakesPriorityOverPaused() {
        let state = menuBarIconState(
            gameStatus: .lost,
            isPaused: true,
            isDailyComplete: false
        )
        #expect(state == .lost)
    }

    @Test("Complete icon when game is won")
    func testCompleteIconWhenGameWon() {
        let state = menuBarIconState(
            gameStatus: .won,
            isPaused: false,
            isDailyComplete: false
        )
        #expect(state == .complete)
    }

    @Test("Complete icon when game is won even if paused flag is true")
    func testCompleteIconWhenWonIgnoresPausedFlag() {
        let state = menuBarIconState(
            gameStatus: .won,
            isPaused: true,
            isDailyComplete: true
        )
        #expect(state == .complete)
    }

    // MARK: - System Image Name Tests

    @Test("Normal state returns correct system image")
    func testNormalSystemImage() {
        #expect(MenuBarIconState.normal.systemImageName == "circle.grid.3x3.fill")
    }

    @Test("Incomplete state returns correct system image")
    func testIncompleteSystemImage() {
        #expect(MenuBarIconState.incomplete.systemImageName == "circle.grid.3x3.fill.badge.ellipsis")
    }

    @Test("Playing state returns correct system image")
    func testPlayingSystemImage() {
        #expect(MenuBarIconState.playing.systemImageName == "timer")
    }

    @Test("Paused state returns correct system image")
    func testPausedSystemImage() {
        #expect(MenuBarIconState.paused.systemImageName == "pause.circle.fill")
    }

    @Test("Complete state returns correct system image")
    func testCompleteSystemImage() {
        #expect(MenuBarIconState.complete.systemImageName == "checkmark.circle.fill")
    }

    @Test("Lost state returns correct system image")
    func testLostSystemImage() {
        #expect(MenuBarIconState.lost.systemImageName == "xmark.circle.fill")
    }

    // MARK: - Overlay Symbol Tests

    @Test("Base icon is grid symbol")
    func testBaseIconIsGrid() {
        #expect(menuBarBaseIcon == "circle.grid.3x3.fill")
    }

    @Test("Normal state has no overlay")
    func testNormalStateNoOverlay() {
        #expect(MenuBarIconState.normal.overlaySymbol == nil)
    }

    @Test("Incomplete state has dot overlay")
    func testIncompleteOverlaySymbol() {
        #expect(MenuBarIconState.incomplete.overlaySymbol == "circle.fill")
    }

    @Test("Playing state has timer overlay")
    func testPlayingOverlaySymbol() {
        #expect(MenuBarIconState.playing.overlaySymbol == "timer")
    }

    @Test("Paused state has pause overlay")
    func testPausedOverlaySymbol() {
        #expect(MenuBarIconState.paused.overlaySymbol == "pause.fill")
    }

    @Test("Complete state has check overlay")
    func testCompleteOverlaySymbol() {
        #expect(MenuBarIconState.complete.overlaySymbol == "checkmark.circle.fill")
    }

    @Test("Lost state has X overlay")
    func testLostOverlaySymbol() {
        #expect(MenuBarIconState.lost.overlaySymbol == "xmark.circle.fill")
    }
}
