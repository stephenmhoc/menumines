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
    }
}
