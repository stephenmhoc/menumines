import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Records the global shortcut: click, then press the keys. Escape cancels, and Delete on
/// its own clears the shortcut.
struct ShortcutRecorderView: View {
    @State private var recorder = ShortcutRecorder()

    private var title: String {
        if recorder.isRecording {
            return String(localized: "settings_global_shortcut_recording")
        }
        return recorder.shortcut?.displayString ?? String(localized: "settings_global_shortcut_record")
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 4) {
                Button {
                    // The button was just clicked, so its window is the key one.
                    recorder.isRecording ? recorder.stop() : recorder.start(in: NSApp.keyWindow)
                } label: {
                    Text(title)
                        .monospacedDigit()
                        .frame(minWidth: 100)
                }
                .accessibilityLabel(String(localized: "settings_global_shortcut"))
                .accessibilityValue(
                    recorder.isRecording
                        ? String(localized: "settings_global_shortcut_recording")
                        : recorder.shortcut?.spokenDescription ?? String(localized: "settings_global_shortcut_none")
                )
                .accessibilityHint(String(localized: "settings_global_shortcut_hint"))

                if recorder.shortcut != nil, !recorder.isRecording {
                    Button {
                        recorder.apply(nil)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help(String(localized: "settings_global_shortcut_clear"))
                    .accessibilityLabel(String(localized: "settings_global_shortcut_clear"))
                }
            }

            if let problem = recorder.problem {
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onDisappear(perform: recorder.stop)
    }
}

/// The recording itself, kept apart from the view because it has to end even when the view
/// isn't told it's going: SwiftUI doesn't call `onDisappear` when the Settings window closes.
///
/// While recording, every key press in the app comes here instead of going where it was
/// sent, and the global shortcut is off so that pressing it records it. Left running, that
/// would swallow the next key anywhere in the app, or record ⌘R from the game panel as the
/// shortcut. So recording ends as the window closes or stops being key, and a key pressed in
/// any other window ends it and goes on its way.
@MainActor
@Observable
final class ShortcutRecorder {
    private(set) var shortcut = GlobalShortcut.load()
    private(set) var isRecording = false
    private(set) var problem: String?

    init() {
        showProblemIfUnavailable()
    }

    /// A saved shortcut another app has taken doesn't work, so it isn't shown as if it did.
    private func showProblemIfUnavailable() {
        if GlobalHotKey.isSavedShortcutUnavailable {
            problem = String(localized: "settings_global_shortcut_unavailable")
        }
    }

    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private weak var window: NSWindow?

    /// Starts listening for the new shortcut.
    /// - Parameter window: The window the recorder is in. Keys pressed anywhere else end it.
    func start(in window: NSWindow?) {
        guard !isRecording else { return }
        problem = nil
        isRecording = true
        self.window = window
        GlobalHotKey.suspend()
        AccessibilityNotification.Announcement(String(localized: "settings_global_shortcut_recording")).post()

        if let window {
            // No queue, so recording has ended by the time the window has gone.
            observers = [NSWindow.willCloseNotification, NSWindow.didResignKeyNotification].map { name in
                NotificationCenter.default.addObserver(forName: name, object: window, queue: nil) { [weak self] _ in
                    MainActor.assumeIsolated { self?.stop() }
                }
            }
        }

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return event }
                return self.handle(event)
            }
        }
    }

    /// Ends recording without changing the shortcut, and listens for the saved one again.
    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        window = nil
        guard isRecording else { return }
        isRecording = false
        GlobalHotKey.resume()
        showProblemIfUnavailable()
    }

    /// Takes a key press while recording.
    /// - Returns: The event, to send on as usual, or nil if it was the recording's.
    func handle(_ event: NSEvent) -> NSEvent? {
        guard isRecording else { return event }
        if let window, event.window !== window {
            stop()
            return event
        }

        let flags = event.modifierFlags.intersection(GlobalShortcut.allowedModifiers)
        switch Int(event.keyCode) {
        case kVK_Escape where flags.isEmpty:
            stop()
            return nil
        case kVK_Delete where flags.isEmpty, kVK_ForwardDelete where flags.isEmpty:
            stop()
            apply(nil)
            return nil
        default:
            break
        }

        guard let newShortcut = GlobalShortcut(event: event) else {
            problem = String(localized: "settings_global_shortcut_needs_modifier")
            NSSound.beep()
            return nil
        }
        guard !newShortcut.isStandardShortcut else {
            let message = String(localized: "settings_global_shortcut_standard \(newShortcut.displayString)")
            problem = message
            AccessibilityNotification.Announcement(message).post()
            NSSound.beep()
            return nil
        }
        stop()
        apply(newShortcut)
        return nil
    }

    /// Saves a new shortcut, or clears it with nil.
    func apply(_ newShortcut: GlobalShortcut?) {
        if GlobalHotKey.set(newShortcut) {
            shortcut = newShortcut
            problem = nil
        } else {
            problem = String(localized: "settings_global_shortcut_unavailable")
            AccessibilityNotification.Announcement(String(localized: "settings_global_shortcut_unavailable")).post()
        }
    }
}
