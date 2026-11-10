import AppKit
import Carbon.HIToolbox
import Testing
@testable import MenuMines

/// Recording the global shortcut in Settings. Part of the game panel suite, because recording
/// watches every key in the app, and a recording left running takes the panel's keys.
extension GamePanelTests {
    /// Sets a shortcut for the test, and puts back whatever was saved before.
    func withTestShortcut(_ body: (GlobalShortcut) async throws -> Void) async throws {
        let key = Constants.SettingsKeys.globalShortcut
        let saved = UserDefaults.standard.object(forKey: key)
        let shortcut = GlobalShortcut(
            keyCode: UInt16(kVK_F19),
            modifierFlags: [.command, .option, .control, .shift],
            key: "F19"
        )
        defer {
            GlobalHotKey.set(nil)
            if let saved {
                UserDefaults.standard.set(saved, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        try #require(GlobalHotKey.set(shortcut))
        try await body(shortcut)
    }

    @Test("Closing Settings while a shortcut is being recorded ends the recording")
    func closingSettingsEndsRecording() async throws {
        let cleanup = setupCleanPersistenceState(continuousPlay: true)
        defer { cleanup() }

        try await withTestShortcut { shortcut in
            let settings = try await openWindow(AppWindows.showSettings, titled: AppWindows.settingsTitle)
            let recorder = ShortcutRecorder()
            recorder.start(in: settings)
            #expect(recorder.isRecording)
            #expect(!GlobalHotKey.isRegistered, "The shortcut is off while it's recorded")

            settings.close()
            // Checked before anything else gets a turn: the recording ends as the window goes.
            #expect(!recorder.isRecording)
            #expect(GlobalHotKey.isRegistered)
            #expect(GlobalShortcut.load() == shortcut)
            try await settle()

            // And the panel's keys go to the board, not into a shortcut.
            let state = todaysDaily()
            let controller = try await openPanel(for: state)
            defer { controller.close() }
            let start = state.selectedCol
            try await pressThroughApp(Key.right, in: controller)
            #expect(state.selectedCol == start + 1)
            #expect(GlobalShortcut.load() == shortcut)
        }
    }

    @Test("A key pressed in another window ends the recording and goes on its way")
    func keyElsewhereEndsRecording() async throws {
        let cleanup = setupCleanPersistenceState(continuousPlay: true)
        defer { cleanup() }

        try await withTestShortcut { shortcut in
            let settings = try await openWindow(AppWindows.showSettings, titled: AppWindows.settingsTitle)
            defer { settings.close() }
            let controller = try await openPanel(for: todaysDaily())
            defer { controller.close() }

            let recorder = ShortcutRecorder()
            recorder.start(in: settings)
            let commandR = try #require(NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: .command,
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: controller.panel.windowNumber,
                context: nil,
                characters: "r",
                charactersIgnoringModifiers: "r",
                isARepeat: false,
                keyCode: Key.commandR.code
            ))
            #expect(recorder.handle(commandR) === commandR, "The panel still gets it")
            #expect(!recorder.isRecording)
            #expect(GlobalHotKey.isRegistered)
            #expect(GlobalShortcut.load() == shortcut, "⌘R from the panel isn't the new shortcut")
        }
    }
}
