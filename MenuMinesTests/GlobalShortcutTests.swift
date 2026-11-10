import AppKit
import Carbon.HIToolbox
import Testing
@testable import MenuMines

@Suite("Global shortcut", .serialized)
@MainActor
struct GlobalShortcutTests {
    func keyDown(_ code: Int, _ characters: String, _ modifiers: NSEvent.ModifierFlags) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: UInt16(code)
        ))
    }

    /// Clears the saved shortcut before and after, so nothing leaks into the next run.
    func withCleanShortcut(_ body: () throws -> Void) rethrows {
        let saved = UserDefaults.standard.object(forKey: Constants.SettingsKeys.globalShortcut)
        GlobalHotKey.set(nil)
        defer {
            GlobalHotKey.set(nil)
            UserDefaults.standard.set(saved, forKey: Constants.SettingsKeys.globalShortcut)
        }
        try body()
    }

    @Test("A shortcut needs Command, Option or Control, except on a function key")
    func needsModifier() throws {
        #expect(GlobalShortcut(event: try keyDown(kVK_ANSI_M, "m", [])) == nil)
        #expect(GlobalShortcut(event: try keyDown(kVK_ANSI_M, "m", .shift)) == nil)
        #expect(GlobalShortcut(event: try keyDown(kVK_ANSI_M, "m", [.control, .option])) != nil)
        #expect(GlobalShortcut(event: try keyDown(kVK_F5, "\u{F708}", [])) != nil)
    }

    @Test("A shortcut is written as menus write it and spoken in words")
    func describesItself() throws {
        let shortcut = try #require(GlobalShortcut(event: try keyDown(kVK_ANSI_M, "m", [.command, .option, .control])))
        #expect(shortcut.displayString == "⌃⌥⌘M")
        #expect(shortcut.spokenDescription.contains(String(localized: "shortcut_modifier_command")))
        #expect(shortcut.carbonModifiers == UInt32(cmdKey | optionKey | controlKey))
    }

    @Test("The shortcut is off until one is set, and setting one saves and registers it")
    func setsAndClears() throws {
        try withCleanShortcut {
            #expect(GlobalShortcut.load() == nil)
            #expect(!GlobalHotKey.isRegistered)

            let shortcut = GlobalShortcut(
                keyCode: UInt16(kVK_F19),
                modifierFlags: [.command, .option, .control, .shift],
                key: "F19"
            )
            #expect(GlobalHotKey.set(shortcut))
            #expect(GlobalShortcut.load() == shortcut)
            #expect(GlobalHotKey.isRegistered)

            GlobalHotKey.suspend()
            #expect(!GlobalHotKey.isRegistered)
            GlobalHotKey.resume()
            #expect(GlobalHotKey.isRegistered)

            GlobalHotKey.set(nil)
            #expect(GlobalShortcut.load() == nil)
            #expect(!GlobalHotKey.isRegistered)
        }
    }

    @Test("Shortcuts the system or every app already uses are turned down")
    func standardShortcutsRefused() throws {
        func shortcut(_ code: Int, _ characters: String, _ modifiers: NSEvent.ModifierFlags) throws -> GlobalShortcut {
            try #require(GlobalShortcut(event: try keyDown(code, characters, modifiers)))
        }
        let standard: [GlobalShortcut] = [
            try shortcut(kVK_ANSI_W, "w", .command), try shortcut(kVK_ANSI_Q, "q", .command),
            try shortcut(kVK_ANSI_C, "c", .command), try shortcut(kVK_ANSI_V, "v", .command),
            try shortcut(kVK_ANSI_X, "x", .command), try shortcut(kVK_ANSI_Z, "z", .command),
            try shortcut(kVK_ANSI_A, "a", .command), try shortcut(kVK_ANSI_H, "h", .command),
            try shortcut(kVK_ANSI_M, "m", .command), try shortcut(kVK_ANSI_Comma, ",", .command),
            try shortcut(kVK_ANSI_R, "r", .command), try shortcut(kVK_Space, " ", .command),
            try shortcut(kVK_Tab, "\t", .command), try shortcut(kVK_ANSI_Z, "z", [.command, .shift]),
            try shortcut(kVK_ANSI_4, "4", [.command, .shift]), try shortcut(kVK_ANSI_H, "h", [.command, .option]),
            try shortcut(kVK_ANSI_Q, "q", [.command, .control]), try shortcut(kVK_Space, " ", .control)
        ]
        for candidate in standard {
            #expect(candidate.isStandardShortcut, "\(candidate.displayString) should be turned down")
        }

        #expect(try !shortcut(kVK_ANSI_M, "m", [.control, .option]).isStandardShortcut)
        #expect(try !shortcut(kVK_ANSI_R, "r", [.command, .option, .control]).isStandardShortcut)
        #expect(try !shortcut(kVK_F5, "\u{F708}", []).isStandardShortcut)
        #expect(String(localized: "settings_global_shortcut_standard \("⌘Q")")
            == "⌘Q is a standard Mac shortcut. Choose another.")
    }

    @Test("A saved shortcut another app has taken shows as unavailable, not as set")
    func unavailableAtLaunch() throws {
        try withCleanShortcut {
            let shortcut = GlobalShortcut(
                keyCode: UInt16(kVK_F18),
                modifierFlags: [.command, .option, .control, .shift],
                key: "F18"
            )
            GlobalShortcut.save(shortcut)

            // Someone else holding the same keys, as another app would.
            var other: EventHotKeyRef?
            let status = RegisterEventHotKey(
                UInt32(shortcut.keyCode),
                shortcut.carbonModifiers,
                EventHotKeyID(signature: 0x5445_5354, id: 9), // "TEST"
                GetApplicationEventTarget(),
                0,
                &other
            )
            try #require(status == noErr)
            defer {
                if let other {
                    UnregisterEventHotKey(other)
                }
            }

            GlobalHotKey.start()
            #expect(!GlobalHotKey.isRegistered)
            #expect(GlobalHotKey.isSavedShortcutUnavailable)
            #expect(GlobalShortcut.load() == shortcut, "It stays saved")
            #expect(ShortcutRecorder().problem == String(localized: "settings_global_shortcut_unavailable"))

            GlobalHotKey.set(nil)
            #expect(!GlobalHotKey.isSavedShortcutUnavailable)
            #expect(ShortcutRecorder().problem == nil)
        }
    }
}
