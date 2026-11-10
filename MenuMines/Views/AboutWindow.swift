import AppKit

/// About MenuMines, as the standard About panel.
///
/// AppKit fills in the icon, the name this build goes by, the version and build (selectable),
/// and the copyright from `NSHumanReadableCopyright`. The credits add what's ours: a line on
/// what the app is, the support address, and which channel this copy came from.
///
/// The panel is AppKit's, so there's no controller of ours to hold. It's treated like the
/// app's own windows all the same: the game panel gets out of its way, it comes forward over
/// whatever the player was using, it joins the active Space, and when it closes,
/// `AppWindows.windowWillClose` (which hears every window close) hands focus back.
@MainActor
enum AboutWindow {
    /// The panel on screen, if it's up. AppKit reuses it while it's open and builds a new
    /// one after it's closed, so a closed one is never brought back.
    private(set) static weak var panel: NSWindow?

    static func show() {
        AppWindows.onWillShowWindow?()

        let onScreen = Set(NSApp.windows.filter(\.isVisible).map(ObjectIdentifier.init))
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: Bundle.main.appName,
            .credits: credits
        ])

        if let shown = NSApp.windows.first(where: {
            $0 is NSPanel && $0.isVisible && !onScreen.contains(ObjectIdentifier($0))
        }) {
            panel = shown
        }
        guard let panel, panel.isVisible else { return }

        // As for the app's own windows: an agent app has no Dock icon to bring a minimised
        // window back from, and one opened from the menu bar joins whatever is on screen.
        panel.styleMask.remove(.miniaturizable)
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    /// What the app is, where to get help, and which build this is.
    static var credits: NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.paragraphSpacing = 6

        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let body: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph
        ]

        let credits = NSMutableAttributedString(string: String(localized: "about_description") + "\n", attributes: body)

        let address = String(localized: "about_support_email")
        var link = body
        if let url = URL(string: "mailto:\(address)") {
            link[.link] = url
        }
        credits.append(NSAttributedString(string: address + "\n", attributes: link))

        let channel = BuildChannel.current
        var channelAttributes = body
        if channel.isPreRelease {
            channelAttributes[.foregroundColor] = NSColor.systemOrange
            channelAttributes[.font] = NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize)
        }
        credits.append(NSAttributedString(string: channel.displayName, attributes: channelAttributes))
        return credits
    }
}
