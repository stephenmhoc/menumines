import Foundation
import Security

#if SPARKLE_ENABLED
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
/// On App Store builds, all methods are no-ops since updates go through the App Store.
enum UpdateManager {
    #if SPARKLE_ENABLED
    private static let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    /// Mirrors Sparkle's KVO state so SwiftUI redraws when a check begins and ends.
    @Observable
    final class Availability {
        var canCheck = false
        @ObservationIgnored private var subscription: AnyCancellable?

        func observe(_ updater: SPUUpdater) {
            subscription = updater.publisher(for: \.canCheckForUpdates)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] in self?.canCheck = $0 }
        }
    }

    private static let availability = Availability()

    /// Starts Sparkle's schedule. The controller is lazy, so without this a player who never
    /// opened the popover would never get an update check.
    static func start() {
        availability.observe(updater)
    }

    /// The underlying Sparkle updater instance.
    static var updater: SPUUpdater {
        updaterController.updater
    }

    /// Whether the updater is currently able to check for updates.
    static var canCheckForUpdates: Bool {
        availability.canCheck
    }

    /// Manually trigger an update check.
    static func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    /// Whether to automatically check for updates periodically.
    static var automaticallyChecksForUpdates: Bool {
        get { updater.automaticallyChecksForUpdates }
        set { updater.automaticallyChecksForUpdates = newValue }
    }

    /// Whether to automatically download updates when found.
    static var automaticallyDownloadsUpdates: Bool {
        get { updater.automaticallyDownloadsUpdates }
        set { updater.automaticallyDownloadsUpdates = newValue }
    }

    /// The date of the last update check, if any.
    static var lastUpdateCheckDate: Date? {
        updater.lastUpdateCheckDate
    }
    #else
    static func start() {}
    static var canCheckForUpdates: Bool { false }
    static func checkForUpdates() {}
    static var automaticallyChecksForUpdates: Bool {
        get { false }
        set { }
    }
    static var automaticallyDownloadsUpdates: Bool {
        get { false }
        set { }
    }
    static var lastUpdateCheckDate: Date? { nil }
    #endif

    /// Returns true if this build supports updates (direct distribution only).
    static var isUpdateSupported: Bool {
        #if SPARKLE_ENABLED
        return true
        #else
        return false
        #endif
    }
}
