import AppKit
import Testing
@testable import MenuMines

/// How the panel goes when it closes. Part of the game panel suite, so these run in turn with
/// the other tests that own the panel.
extension GamePanelTests {
    @Test("Closing from a key takes the panel away at once, so the next key isn't lost")
    func keyCloseSkipsFade() async throws {
        let cleanup = setupCleanPersistenceState(continuousPlay: true)
        defer { cleanup() }

        let controller = try await openPanel(for: todaysDaily())
        defer { controller.close() }

        func keyDown(_ key: (code: UInt16, characters: String), _ modifiers: NSEvent.ModifierFlags) throws -> NSEvent {
            try #require(NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: modifiers,
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: controller.panel.windowNumber,
                context: nil,
                characters: key.characters,
                charactersIgnoringModifiers: key.characters,
                isARepeat: false,
                keyCode: key.code
            ))
        }

        // Checked straight after each key, well inside the fade's time.
        try await takeKeyboard(for: controller)
        controller.panel.sendEvent(try keyDown(Key.escape, []))
        #expect(!controller.isOpen)
        #expect(!controller.panel.isVisible, "Escape")
        #expect(!controller.panel.isKeyWindow)

        try await takeKeyboard(for: controller)
        NSApp.sendEvent(try keyDown(Key.commandW, .command))
        #expect(!controller.isOpen)
        #expect(!controller.panel.isVisible, "Command-W")

        // The global shortcut is a key too.
        try await takeKeyboard(for: controller)
        controller.toggle()
        #expect(!controller.isOpen)
        #expect(!controller.panel.isVisible, "The shortcut")
    }
}
