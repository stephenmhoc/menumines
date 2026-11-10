import AppKit
import Testing
@testable import MenuMines

/// About is AppKit's standard panel. Part of the game panel suite, since it puts a window on
/// screen and moves focus like the app's own windows.
extension GamePanelTests {
    private func aboutTexts(in panel: NSWindow) -> [String] {
        var texts: [String] = []
        func walk(_ view: NSView) {
            if let field = view as? NSTextField {
                texts.append(field.stringValue)
            } else if let textView = view as? NSTextView {
                texts.append(textView.string)
            }
            view.subviews.forEach(walk)
        }
        if let content = panel.contentView {
            walk(content)
        }
        return texts
    }

    @Test("About shows this build's name, version and copyright, and the credits")
    func aboutPanelContent() async throws {
        AboutWindow.show()
        try await settle()
        let panel = try #require(AboutWindow.panel)

        let texts = aboutTexts(in: panel)
        let info = Bundle.main.infoDictionary
        let version = try #require(info?["CFBundleShortVersionString"] as? String)
        let copyright = try #require(info?["NSHumanReadableCopyright"] as? String)
        #expect(texts.contains(Bundle.main.appName))
        #expect(texts.contains { $0.contains(version) })
        #expect(texts.contains(copyright))
        #expect(texts.contains { $0.contains(String(localized: "about_support_email")) })
        #expect(texts.contains { $0.contains(BuildChannel.current.displayName) })
        #expect(!panel.styleMask.contains(.miniaturizable))
        panel.close()
        try await settle()
        try await handFocusBack()
    }

    @Test("About opens again after it's closed, as one panel")
    func aboutPanelReopens() async throws {
        for _ in 0..<2 {
            AboutWindow.show()
            try await settle()
            let shown = NSApp.windows.filter { $0.isVisible && $0 is NSPanel && !($0 is GamePanel) }
            #expect(shown.count == 1)
            #expect(shown.first === AboutWindow.panel)
            AboutWindow.panel?.close()
            try await settle()
        }
        #expect(AboutWindow.panel?.isVisible != true)
        try await handFocusBack()
    }

    @Test("A click in About, or any other window of the app's, closes the game panel")
    func clickInAboutClosesPanel() async throws {
        let cleanup = setupCleanPersistenceState(continuousPlay: true)
        defer { cleanup() }

        AboutWindow.show()
        try await settle()
        let about = try #require(AboutWindow.panel)
        defer { about.close() }
        #expect(!about.canBecomeMain, "The case the old check missed")

        let controller = StatusItemController(gameState: todaysDaily())
        defer { controller.close() }
        let panel = controller.panel
        let iconWindow = controller.statusItem.button?.window
        #expect(StatusItemController.closesPanel(clickIn: about, panel: panel, iconWindow: iconWindow))
        #expect(!StatusItemController.closesPanel(clickIn: panel, panel: panel, iconWindow: iconWindow))
        #expect(!StatusItemController.closesPanel(clickIn: iconWindow, panel: panel, iconWindow: iconWindow))
        #expect(!StatusItemController.closesPanel(clickIn: nil, panel: panel, iconWindow: iconWindow))

        // Something the panel opens over itself, as a popover is.
        let attached = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 40, height: 40),
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )
        controller.open()
        panel.addChildWindow(attached, ordered: .above)
        defer {
            panel.removeChildWindow(attached)
            attached.orderOut(nil)
        }
        #expect(!StatusItemController.closesPanel(clickIn: attached, panel: panel, iconWindow: iconWindow))

        // And a real click, through the event loop where the panel's monitor hears it.
        let center = NSPoint(x: about.frame.width / 2, y: about.frame.height / 2)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let click = try #require(NSEvent.mouseEvent(
                with: type,
                location: center,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: about.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: type == .leftMouseDown ? 1 : 0
            ))
            NSApp.postEvent(click, atStart: false)
        }
        try await settle()
        #expect(!controller.isOpen)
        try await handFocusBack()
    }
}
