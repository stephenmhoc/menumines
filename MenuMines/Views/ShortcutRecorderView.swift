import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Records the global shortcut: click, then press the keys. Escape cancels, and Delete on
/// its own clears the shortcut.
struct ShortcutRecorderView: View {
    @State private var shortcut = GlobalShortcut.load()
    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var problem: String?

    private var title: String {
        if isRecording {
            return String(localized: "settings_global_shortcut_recording")
        }
        return shortcut?.displayString ?? String(localized: "settings_global_shortcut_record")
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 4) {
                Button {
                    isRecording ? stopRecording() : startRecording()
                } label: {
                    Text(title)
                        .monospacedDigit()
                        .frame(minWidth: 100)
                }
                .accessibilityLabel(String(localized: "settings_global_shortcut"))
                .accessibilityValue(
                    isRecording
                        ? String(localized: "settings_global_shortcut_recording")
                        : shortcut?.spokenDescription ?? String(localized: "settings_global_shortcut_none")
                )
                .accessibilityHint(String(localized: "settings_global_shortcut_hint"))

                if shortcut != nil, !isRecording {
                    Button {
                        apply(nil)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help(String(localized: "settings_global_shortcut_clear"))
                    .accessibilityLabel(String(localized: "settings_global_shortcut_clear"))
                }
            }

            if let problem {
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onDisappear(perform: stopRecording)
    }

    private func startRecording() {
        guard !isRecording else { return }
        problem = nil
        isRecording = true
        GlobalHotKey.suspend()
        AccessibilityNotification.Announcement(String(localized: "settings_global_shortcut_recording")).post()

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated { record(event) }
            return nil
        }
    }

    private func record(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(GlobalShortcut.allowedModifiers)
        switch Int(event.keyCode) {
        case kVK_Escape where flags.isEmpty:
            stopRecording()
            return
        case kVK_Delete where flags.isEmpty, kVK_ForwardDelete where flags.isEmpty:
            stopRecording()
            apply(nil)
            return
        default:
            break
        }

        guard let newShortcut = GlobalShortcut(event: event) else {
            problem = String(localized: "settings_global_shortcut_needs_modifier")
            NSSound.beep()
            return
        }
        stopRecording()
        apply(newShortcut)
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        guard isRecording else { return }
        isRecording = false
        GlobalHotKey.resume()
    }

    private func apply(_ newShortcut: GlobalShortcut?) {
        if GlobalHotKey.set(newShortcut) {
            shortcut = newShortcut
            problem = nil
        } else {
            problem = String(localized: "settings_global_shortcut_unavailable")
            AccessibilityNotification.Announcement(String(localized: "settings_global_shortcut_unavailable")).post()
        }
    }
}
