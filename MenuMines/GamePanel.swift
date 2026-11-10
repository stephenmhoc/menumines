import AppKit
import SwiftUI

/// A floating panel that takes the keyboard without activating the app.
final class GamePanel: NSPanel {
    var onCancel: (() -> Void)?

    /// Set while the panel fades out. It looks closed by then, so it takes no more input.
    var isClosing = false

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        // Opens at once, like a menu. Closing fades, which `StatusItemController` runs.
        animationBehavior = .none
        // The app is never active while the panel is up, and tooltips are off otherwise.
        allowsToolTipsWhenApplicationIsInactive = true
    }

    // A borderless window refuses key by default, and without it nothing reaches the board.
    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    /// Command-W closes the panel as Escape does. A borderless window has no close button,
    /// so the standard Close would only beep.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if flags == .command, event.charactersIgnoringModifiers == "w" {
            onCancel?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func sendEvent(_ event: NSEvent) {
        if isClosing {
            switch event.type {
            case .keyDown, .keyUp, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel:
                return
            default:
                break
            }
        }
        super.sendEvent(event)
    }
}

/// Puts the panel's content on the system's material, as menus and the menu bar's own
/// panels are: Liquid Glass on macOS 26, and the popover material before it.
@MainActor
final class PanelBackdropController: NSViewController {
    /// Matches the panels the menu bar opens on each system.
    static var cornerRadius: CGFloat {
        if #available(macOS 26, *) {
            return 16
        }
        return 10
    }

    private let content: NSViewController

    /// The size the content asks for.
    private(set) var contentSize: NSSize

    /// Called when the content asks for a different size while it's up.
    var onContentSizeChange: ((NSSize) -> Void)?

    init(content: NSViewController) {
        self.content = content
        self.contentSize = content.view.fittingSize
        super.init(nibName: nil, bundle: nil)
        addChild(content)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let frame = NSRect(origin: .zero, size: contentSize)
        let contentView = content.view
        contentView.frame = frame
        contentView.autoresizingMask = [.width, .height]

        if #available(macOS 26, *) {
            let glass = NSGlassEffectView(frame: frame)
            glass.cornerRadius = Self.cornerRadius
            glass.contentView = contentView
            view = glass
            return
        }

        let effect = NSVisualEffectView(frame: frame)
        effect.material = .popover
        effect.blendingMode = .behindWindow
        // The app is never active while the panel is up, and the material would go flat.
        effect.state = .active
        effect.maskImage = Self.roundedMask(radius: Self.cornerRadius)
        effect.addSubview(contentView)

        let outline = PanelOutlineView(frame: frame)
        outline.autoresizingMask = [.width, .height]
        effect.addSubview(outline)
        view = effect
    }

    override func preferredContentSizeDidChange(for viewController: NSViewController) {
        super.preferredContentSizeDidChange(for: viewController)
        let size = viewController.preferredContentSize
        guard size.width > 0, size.height > 0, size != contentSize else { return }
        contentSize = size
        onContentSizeChange?(size)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        // The shadow follows what's drawn, which only settles once the content is laid out.
        view.window?.invalidateShadow()
    }

    static func continuousPath(radius: CGFloat, in rect: NSRect) -> NSBezierPath {
        NSBezierPath(cgPath: RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect).cgPath)
    }

    /// A stretchable mask with continuous corners, which is how a behind-window material
    /// gets its shape.
    static func roundedMask(radius: CGFloat) -> NSImage {
        // Continuous corners start their curve further in than the radius.
        let cap = ceil(radius * 1.6)
        let edge = cap * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            Self.continuousPath(radius: radius, in: rect).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: cap, left: cap, bottom: cap, right: cap)
        image.resizingMode = .stretch
        return image
    }
}

/// The hairline round the panel before macOS 26, which sets it off from a window of the
/// same colour behind it.
private final class PanelOutlineView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let scale = window?.backingScaleFactor ?? 2
        let lineWidth = 1 / scale
        let rect = bounds.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
        let radius = PanelBackdropController.cornerRadius - lineWidth / 2
        let path = PanelBackdropController.continuousPath(radius: radius, in: rect)
        path.lineWidth = lineWidth
        NSColor.separatorColor.setStroke()
        path.stroke()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsDisplay = true
    }
}
