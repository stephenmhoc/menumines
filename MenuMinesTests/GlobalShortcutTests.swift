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
}
