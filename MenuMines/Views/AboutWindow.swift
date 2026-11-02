import AppKit
import SwiftUI

@MainActor
enum AboutWindow {
    static func show() {
        AppWindows.show(id: "about", title: String(localized: "about_menu_item")) {
            AboutView()
        }
    }
}

private struct AboutView: View {
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    private var channel: BuildChannel {
        BuildChannel.current
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)
                .accessibilityHidden(true)

            VStack(spacing: 4) {
                Text(String(localized: "about_title"))
                    .font(.title)
                    .fontWeight(.semibold)

                Text(String(format: String(localized: "build_info_version"), appVersion, buildNumber))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(channel.displayName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(channel.isPreRelease ? Color.orange : Color.secondary)
            }

            Text(String(localized: "about_description"))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let supportURL = URL(string: "mailto:support@merimerimeri.com") {
                Link(String(localized: "about_support_email"), destination: supportURL)
                    .font(.caption)
            }

            Text(String(localized: "about_copyright"))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(width: 300)
    }
}

#Preview {
    AboutView()
}
