import AppKit
import ServiceManagement
import SwiftUI

/// The Settings window, grouped as System Settings groups its panes: each section has a
/// header, and each control a sentence-case label with a one-line description under it.
struct SettingsView: View {
    enum Layout {
        static let width: CGFloat = 420
        /// The smallest the window's content gets, whatever the form reports.
        static let minimumSize = NSSize(width: width, height: 360)
        /// Ceiling enforced by `SettingsViewLayoutTests`, not a fixed window size.
        ///
        /// The height is left to the content because the form is not the same size in every
        /// build: the direct-distribution build carries an extra Updates section. Pinning the
        /// window to one height meant whichever configuration was taller quietly scrolled.
        static let maxHeight: CGFloat = 820
    }

    /// Lays the form out at its full height, which is how tall the window wants to be.
    ///
    /// Measured apart from the window's own copy, because a grouped form scrolls and so has
    /// no height of its own to give: in the window it fills what it's given and scrolls when
    /// the screen is too short for all of it.
    @MainActor
    static var idealContentSize: NSSize {
        let measuring = NSHostingView(rootView: SettingsView(isMeasuring: true))
        return measuring.fittingSize
    }

    /// Whether this copy is only being laid out to find the form's height.
    var isMeasuring = false

    @AppStorage(Constants.SettingsKeys.showMenuBarIndicators) private var showMenuBarIndicators = true
    @AppStorage(Constants.SettingsKeys.showMenuBarResult) private var showMenuBarResult = true
    @AppStorage(Constants.SettingsKeys.confirmBeforeReset) private var confirmBeforeReset = false
    @AppStorage(Constants.SettingsKeys.continuousPlay) private var continuousPlay = true
    @AppStorage(Constants.SettingsKeys.showStreaks) private var showStreaks = true
    @AppStorage(Constants.SettingsKeys.sendCrashReports) private var sendsCrashReports = true

    private var sendCrashReports: Binding<Bool> {
        Binding(
            get: { sendsCrashReports },
            set: { enabled in
                sendsCrashReports = enabled
                Telemetry.setEnabled(enabled)
            }
        )
    }

    var body: some View {
        Form {
            Section {
                LaunchAtLoginRow()

                LabeledContent {
                    ShortcutRecorderView()
                } label: {
                    Text(String(localized: "settings_global_shortcut"))
                    Text(String(localized: "settings_global_shortcut_footer"))
                        .foregroundStyle(.secondary)
                }
            } header: {
                sectionHeader("settings_section_general")
            }

            Section {
                Toggle(isOn: $showMenuBarIndicators) {
                    Text(String(localized: "settings_show_menu_bar_indicators"))
                    Text(String(localized: "settings_show_menu_bar_indicators_footer"))
                        .foregroundStyle(.secondary)
                }

                Toggle(isOn: $showMenuBarResult) {
                    Text(String(localized: "settings_show_menu_bar_result"))
                    Text(String(localized: "settings_show_menu_bar_result_footer"))
                        .foregroundStyle(.secondary)
                }
                .disabled(!showMenuBarIndicators)
            } header: {
                sectionHeader("settings_section_menu_bar")
            }

            Section {
                Toggle(isOn: $continuousPlay) {
                    Text(String(localized: "settings_continuous_play"))
                    Text(String(localized: "settings_continuous_play_footer"))
                        .foregroundStyle(.secondary)
                }

                Toggle(isOn: $confirmBeforeReset) {
                    Text(String(localized: "settings_confirm_before_reset"))
                    Text(String(localized: "settings_confirm_before_reset_footer"))
                        .foregroundStyle(.secondary)
                }
            } header: {
                sectionHeader("settings_section_game")
            }

            Section {
                Toggle(isOn: $showStreaks) {
                    Text(String(localized: "settings_show_streaks"))
                    Text(String(localized: "settings_show_streaks_footer"))
                        .foregroundStyle(.secondary)
                }
            } header: {
                sectionHeader("settings_section_statistics")
            }

            if Telemetry.isAvailable {
                Section {
                    Toggle(isOn: sendCrashReports) {
                        Text(String(localized: "settings_send_crash_reports"))
                        Text(String(localized: "settings_send_crash_reports_footer"))
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    sectionHeader("settings_section_privacy")
                }
            }

            #if SPARKLE_ENABLED
            UpdatesSection()
            #endif

            // Only a build that isn't what customers run says what it is. A released copy's
            // version is in About.
            if channel.isPreRelease {
                Section {
                    LabeledContent(String(localized: "build_info_channel")) {
                        Text(channel.displayName)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.orange)
                    }
                } header: {
                    sectionHeader("build_info_section")
                } footer: {
                    Text(buildFooter)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: isMeasuring)
        .frame(width: Layout.width)
    }

    private func sectionHeader(_ key: String.LocalizationValue) -> some View {
        Text(String(localized: key))
            .accessibilityAddTraits(.isHeader)
    }

    private var channel: BuildChannel {
        BuildChannel.current
    }

    private var buildFooter: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        let versionDescription = String(format: String(localized: "build_info_version"), version, build)
        return versionDescription + "\n" + String(localized: "build_info_prerelease_note")
    }
}

#if SPARKLE_ENABLED
/// Sparkle's settings, read through `UpdateManager` so the toggles follow changes made
/// elsewhere, such as Sparkle's own "Automatically download" checkbox.
private struct UpdatesSection: View {
    var body: some View {
        Section {
            Toggle(
                String(localized: "settings_auto_check_updates"),
                isOn: Binding(
                    get: { UpdateManager.automaticallyChecksForUpdates },
                    set: { UpdateManager.automaticallyChecksForUpdates = $0 }
                )
            )

            if UpdateManager.allowsAutomaticUpdates {
                Toggle(
                    String(localized: "settings_auto_download_updates"),
                    isOn: Binding(
                        get: { UpdateManager.automaticallyDownloadsUpdates },
                        set: { UpdateManager.automaticallyDownloadsUpdates = $0 }
                    )
                )
                .disabled(!UpdateManager.automaticallyChecksForUpdates)
            }

            LabeledContent {
                Button(String(localized: "check_for_updates_menu_item")) {
                    UpdateManager.checkForUpdates()
                }
                .disabled(!UpdateManager.canCheckForUpdates)
            } label: {
                Text(status)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(String(localized: "settings_updates_section"))
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var status: String {
        if UpdateManager.isUpdatePending {
            return String(localized: "settings_update_available")
        }
        guard let date = UpdateManager.lastUpdateCheckDate else {
            return String(localized: "settings_updates_never_checked")
        }
        return String(
            format: String(localized: "settings_updates_last_checked"),
            date.formatted(date: .abbreviated, time: .shortened)
        )
    }
}
#endif

/// Launch at Login, read from the system rather than stored, since the player can change it
/// in System Settings too. It's read again whenever the app comes forward, so a change made
/// there shows up here.
///
/// A login item can be registered and still waiting for the player's approval in System
/// Settings. That reads as on, because turning it off still has something to undo, with a
/// line saying what's left to do and a button that goes there.
private struct LaunchAtLoginRow: View {
    @State private var status = SMAppService.mainApp.status

    private var isOn: Binding<Bool> {
        Binding(
            get: { status == .enabled || status == .requiresApproval },
            set: { newValue in
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    // The toggle snaps back when this fails, so without a report there is no
                    // trace of it anywhere.
                    Telemetry.report(error, area: "login_item", step: newValue ? "register" : "unregister")
                }
                status = SMAppService.mainApp.status
            }
        )
    }

    var body: some View {
        Toggle(isOn: isOn) {
            Text(String(localized: "settings_launch_at_login"))
            Text(String(localized: "settings_launch_at_login_footer"))
                .foregroundStyle(.secondary)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            status = SMAppService.mainApp.status
        }

        if status == .requiresApproval {
            LabeledContent {
                Button(String(localized: "settings_launch_at_login_open_settings")) {
                    SMAppService.openSystemSettingsLoginItems()
                }
            } label: {
                Label {
                    Text(String(localized: "settings_launch_at_login_needs_approval"))
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                }
                .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    SettingsView()
}
