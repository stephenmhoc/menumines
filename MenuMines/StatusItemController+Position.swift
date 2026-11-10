import AppKit

/// Where the panel goes: always directly under the icon.
extension StatusItemController {
    /// Where the icon is, if it's on a screen: the anchor every way of opening the panel
    /// uses, read afresh each time. Nil only when the button has no window, its window isn't
    /// up, or the window lies off every screen, which is how a hidden icon (behind the camera
    /// housing, or turned off in the menu bar settings) is left.
    var iconAnchor: (frame: NSRect, screen: NSRect)? {
        guard statusItem.isVisible, let window = statusItem.button?.window, window.isVisible else { return nil }
        let frame = window.frame
        let screen = window.screen ?? NSScreen.screens.first { $0.frame.intersects(frame) }
        guard let screen, screen.frame.intersects(frame) else { return nil }
        return (frame, screen.visibleFrame)
    }

    var isIconOnScreen: Bool { iconAnchor != nil }

    func panelOrigin(for size: NSSize) -> NSPoint {
        Self.panelOrigin(
            for: size,
            under: iconAnchor,
            fallbackScreen: (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
        )
    }

    /// Directly under the icon, centred on it, kept clear of the edges of the icon's screen.
    /// With no icon on screen, at the top middle of the fallback screen under the menu bar.
    static func panelOrigin(
        for size: NSSize,
        under icon: (frame: NSRect, screen: NSRect)?,
        fallbackScreen: NSRect?
    ) -> NSPoint {
        if let icon {
            let visible = icon.screen
            let centered = icon.frame.midX - size.width / 2
            let left = min(max(centered, visible.minX + margin), visible.maxX - size.width - margin)
            // The bottom of the menu bar, should the icon's window not have its full height yet.
            let top = min(icon.frame.minY, visible.maxY)
            return NSPoint(x: left, y: top - size.height - margin)
        }

        guard let visible = fallbackScreen else { return .zero }
        return NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - margin)
    }

    /// Resizes the open panel to new content, keeping its top edge under the icon so it
    /// grows downwards.
    func resize(to size: NSSize) {
        guard isOpen else { return }
        let frameSize = panel.frameRect(forContentRect: NSRect(origin: .zero, size: size)).size
        panel.setFrame(NSRect(origin: panelOrigin(for: frameSize), size: frameSize), display: true)
        panel.invalidateShadow()
    }
}
