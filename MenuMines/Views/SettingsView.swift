import ServiceManagement
import SwiftUI

struct SettingsView: View {
    enum Layout {
        static let width: CGFloat = 420
        /// Ceiling enforced by `SettingsViewLayoutTests`, not a fixed window size.
        ///
        /// The height is left to the content because the form is not the same size in every
        /// build: the direct-distribution build carries an extra Updates section. Pinning the
        /// window to one height meant whichever configuration was taller quietly scrolled.
        static let maxHeight: CGFloat = 640
    }

    @AppStorage(Constants.SettingsKeys.showMenuBarIndicators) private var showMenuBarIndicators = true
    @AppStorage(Constants.SettingsKeys.showMenuBarResult) private var showMenuBarResult = true
    @AppStorage(Constants.SettingsKeys.confirmBeforeReset) private var confirmBeforeReset = false
    @AppStorage(Constants.SettingsKeys.continuousPlay) private var continuousPlay = true
    @AppStorage(Constants.SettingsKeys.showStreaks) private var showStreaks = true
    @AppStorage(Constants.SettingsKeys.sendCrashReports) private var sendsCrashReports = true

    private var launchAtLogin: Binding<Bool> {
        Binding(
            get: { SMAppService.mainApp.status == .enabled },
            set: { newValue in
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    // The toggle silently snaps back when this fails, so without a report
                    // there is no trace of it anywhere.
                    Telemetry.report(error, area: "login_item", step: newValue ? "register" : "unregister")
                }
            }
        )
    }

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
                Toggle(isOn: launchAtLogin) {
                    Text(String(localized: "settings_launch_at_login"))
                    Text(String(localized: "settings_launch_at_login_footer"))
                        .foregroundStyle(.secondary)
                }

                LabeledContent {
                    ShortcutRecorderView()
                } label: {
                    Text(String(localized: "settings_global_shortcut"))
                    Text(String(localized: "settings_global_shortcut_footer"))
                        .foregroundStyle(.secondary)
                }
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
            }

            Section {
                Toggle(isOn: $showStreaks) {
                    Text(String(localized: "settings_show_streaks"))
                    Text(String(localized: "settings_show_streaks_footer"))
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Toggle(isOn: $confirmBeforeReset) {
                    Text(String(localized: "settings_confirm_before_reset"))
                    Text(String(localized: "settings_confirm_before_reset_footer"))
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Toggle(isOn: $continuousPlay) {
                    Text(String(localized: "settings_continuous_play"))
                    Text(String(localized: "settings_continuous_play_footer"))
                        .foregroundStyle(.secondary)
                }
            }

            if Telemetry.isAvailable {
                Section {
                    Toggle(isOn: sendCrashReports) {
                        Text(String(localized: "settings_send_crash_reports"))
                        Text(String(localized: "settings_send_crash_reports_footer"))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            #if SPARKLE_ENABLED
            Section {
                Toggle(
                    String(localized: "settings_auto_check_updates"),
                    isOn: Binding(
                        get: { UpdateManager.automaticallyChecksForUpdates },
                        set: { UpdateManager.automaticallyChecksForUpdates = $0 }
                    )
                )

                Button(String(localized: "check_for_updates_button")) {
                    UpdateManager.checkForUpdates()
                }
                .disabled(!UpdateManager.canCheckForUpdates)
            } header: {
                Text(String(localized: "settings_updates_section"))
            }
            #endif

            Section {
                LabeledContent(String(localized: "build_info_channel")) {
                    Text(channel.displayName)
                        .fontWeight(channel.isPreRelease ? .semibold : .regular)
                        .foregroundStyle(channel.isPreRelease ? Color.orange : Color.primary)
                }
            } header: {
                Text(String(localized: "build_info_section"))
            } footer: {
                Text(buildFooter)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        // A grouped form scrolls, so it has no height of its own to give the window.
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: Layout.width)
    }

    private var channel: BuildChannel {
        BuildChannel.current
    }

    private var buildFooter: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        let versionDescription = String(format: String(localized: "build_info_version"), version, build)

        guard channel.isPreRelease else { return versionDescription }
        return versionDescription + "\n" + String(localized: "build_info_prerelease_note")
    }
}

#Preview {
    SettingsView()
}
