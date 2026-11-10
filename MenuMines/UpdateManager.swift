import Foundation
import Security

#if SPARKLE_ENABLED
import AppKit
import Combine
import Sparkle
#endif

/// Which distribution channel this copy of the app came from.
///
/// Worth surfacing because the builds are otherwise indistinguishable: a TestFlight build and
/// a released App Store build carry the same name, icon and version, but only one of them is
/// what customers are running.
enum BuildChannel {
    case development
    case direct
    case testFlight
    case appStore

    var displayName: String {
        switch self {
        case .development:
            return String(localized: "build_channel_development")
        case .direct:
            return String(localized: "build_channel_direct")
        case .testFlight:
            return String(localized: "build_channel_testflight")
        case .appStore:
            return String(localized: "build_channel_app_store")
        }
    }

    /// Whether this build is a pre-release one that should be called out prominently.
    var isPreRelease: Bool {
        self == .development || self == .testFlight
    }

    static var current: BuildChannel {
        resolveBuildChannel(
            isSparkleBuild: UpdateManager.isUpdateSupported,
            hasStoreReceipt: Bundle.main.hasMacAppStoreReceipt,
            isTestFlightSigned: Bundle.main.isTestFlightSigned
        )
    }
}

/// Resolves the build channel from the facts that distinguish the builds.
///
/// Only a store-delivered copy carries a receipt, which separates the two store channels
/// from everything else; the signing certificate then separates TestFlight from the App
/// Store. Anything with no receipt was not installed from a store at all.
func resolveBuildChannel(isSparkleBuild: Bool, hasStoreReceipt: Bool, isTestFlightSigned: Bool) -> BuildChannel {
    if isSparkleBuild { return .direct }
    guard hasStoreReceipt else { return .development }
    return isTestFlightSigned ? .testFlight : .appStore
}

extension Bundle {
    /// Whether a Mac App Store receipt is present, meaning a store delivered this copy.
    var hasMacAppStoreReceipt: Bool {
        let receipt = bundleURL.appending(path: "Contents/_MASReceipt/receipt")
        return FileManager.default.fileExists(atPath: receipt.path)
    }

    /// Whether Apple re-signed this copy for TestFlight.
    ///
    /// The iOS trick of looking for a receipt named `sandboxReceipt` does not work here: on
    /// macOS the receipt is called the same thing in every environment. TestFlight builds are
    /// instead distinguished by a marker OID that only Apple's TestFlight distribution
    /// certificate carries.
    var isTestFlightSigned: Bool {
        let testFlightMarkerOID = "1.2.840.113635.100.6.1.25.1"
        return satisfiesCodeRequirement(
            "anchor apple generic and certificate leaf[field.\(testFlightMarkerOID)]"
        )
    }

    private func satisfiesCodeRequirement(_ requirementString: String) -> Bool {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundleURL as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode else {
            return false
        }

        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(requirementString as CFString, [], &requirement) == errSecSuccess,
              let requirement else {
            return false
        }

        return SecStaticCodeCheckValidity(staticCode, [], requirement) == errSecSuccess
    }
}

/// Manages application updates for direct distribution builds.
/// Other builds update through the App Store, so there `start()` does nothing and the rest
/// isn't compiled: every other caller is inside `#if SPARKLE_ENABLED`.
///
/// MenuMines lives in the menu bar, so an update found on the schedule never puts a window
/// in front of whatever the player is doing. It's marked on the menu bar icon and in the
/// menus instead (`isUpdatePending`), and Sparkle's window comes up when they ask for it.
@MainActor
enum UpdateManager {
    #if SPARKLE_ENABLED
    private static let reminder = UpdateReminder()

    private static let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: reminder
    )

    /// Mirrors Sparkle's state so SwiftUI and the menu bar icon redraw when it changes.
    @MainActor
    @Observable
    final class Availability {
        var canCheck = false
        var automaticallyChecks = false
        var automaticallyDownloads = false
        var lastCheckDate: Date?
        /// A scheduled check found an update the player hasn't looked at yet.
        var isUpdatePending = false
        @ObservationIgnored private var subscriptions: [AnyCancellable] = []

        func observe(_ updater: SPUUpdater) {
            subscriptions = [
                updater.publisher(for: \.canCheckForUpdates)
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self, weak updater] canCheck in
                        MainActor.assumeIsolated {
                            self?.canCheck = canCheck
                            // A check has started or finished, either of which can move this.
                            self?.lastCheckDate = updater?.lastUpdateCheckDate
                        }
                    },
                updater.publisher(for: \.automaticallyChecksForUpdates)
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] value in MainActor.assumeIsolated { self?.automaticallyChecks = value } },
                updater.publisher(for: \.automaticallyDownloadsUpdates)
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] value in MainActor.assumeIsolated { self?.automaticallyDownloads = value } }
            ]
        }
    }

    private static let availability = Availability()

    /// Starts Sparkle's schedule. The controller is lazy, so without this a player who never
    /// opened the popover would never get an update check.
    static func start() {
        availability.observe(updater)
    }

    private static var updater: SPUUpdater {
        updaterController.updater
    }

    /// Whether the updater is currently able to check for updates.
    static var canCheckForUpdates: Bool {
        availability.canCheck
    }

    /// Checks for updates now, or brings forward an update that's already been found.
    ///
    /// The player asked, so Sparkle's window comes up in front of their app, the way the
    /// app's own windows do, and the game panel gets out of its way.
    static func checkForUpdates() {
        AppWindows.onWillShowWindow?()
        NSApp.activate(ignoringOtherApps: true)
        updaterController.checkForUpdates(nil)
    }

    /// Whether to automatically check for updates periodically.
    static var automaticallyChecksForUpdates: Bool {
        get { availability.automaticallyChecks }
        set { updater.automaticallyChecksForUpdates = newValue }
    }

    /// Whether updates are downloaded and installed without asking. Only matters while
    /// automatic checks are on.
    static var automaticallyDownloadsUpdates: Bool {
        get { availability.automaticallyDownloads }
        set { updater.automaticallyDownloadsUpdates = newValue }
    }

    /// Whether this build lets updates install on their own (`SUAllowsAutomaticUpdates`).
    static var allowsAutomaticUpdates: Bool {
        updater.allowsAutomaticUpdates
    }

    /// When the last check for updates was made, if ever.
    static var lastUpdateCheckDate: Date? {
        availability.lastCheckDate
    }

    static var isUpdatePending: Bool {
        availability.isUpdatePending
    }

    fileprivate static func setUpdatePending(_ isPending: Bool) {
        availability.isUpdatePending = isPending
    }
    #else
    static func start() {}

    /// Updates come from the App Store, which marks them itself.
    static var isUpdatePending: Bool { false }
    #endif

    /// Returns true if this build supports updates (direct distribution only).
    nonisolated static var isUpdateSupported: Bool {
        #if SPARKLE_ENABLED
        return true
        #else
        return false
        #endif
    }
}

#if SPARKLE_ENABLED
/// Sparkle's gentle reminders, for an app with no Dock icon and no main window.
///
/// Sparkle's own window would come up over the player's app as soon as a scheduled check
/// found an update. Instead the update waits, marked on the icon and in the menus, until
/// the player chooses Update Available, which shows it. A check they start themselves is
/// always shown by Sparkle at once.
private final class UpdateReminder: NSObject, SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        false
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        guard !state.userInitiated else { return }
        MainActor.assumeIsolated { UpdateManager.setUpdatePending(true) }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        MainActor.assumeIsolated { UpdateManager.setUpdatePending(false) }
    }

    func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated { UpdateManager.setUpdatePending(false) }
    }
}
#endif
