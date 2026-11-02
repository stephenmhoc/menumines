import Foundation

/// The parts of `NSUbiquitousKeyValueStore` that syncing uses, so the rules can be tested.
protocol CloudKeyValueStoring: AnyObject {
    func data(forKey key: String) -> Data?
    func set(_ data: Data?, forKey key: String)
    func double(forKey key: String) -> Double
    func set(_ value: Double, forKey key: String)
    func removeObject(forKey key: String)
    var allKeys: [String] { get }
    @discardableResult func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: CloudKeyValueStoring {
    var allKeys: [String] { Array(dictionaryRepresentation.keys) }
}

/// Reconciles this Mac's daily results with the copy in a player's iCloud.
///
/// Results are stored one key per month. A whole-history value would let a Mac that hadn't
/// finished downloading replace everything with the one day it knew about, and it would pass
/// the store's 64KB-per-value ceiling in under two years. One key per day would run into the
/// store's limit of 1024 keys in under three. At worst a month's key is overwritten by a Mac
/// that knows less, and any Mac that knows more repairs it the next time it syncs.
///
/// Every operation merges first and writes only what differs, so syncing is idempotent and
/// Macs converge whatever order they run in.
@MainActor
struct DailyResultsCloud {
    /// Written by versions before results moved to monthly keys. Read so that history comes
    /// across, and never written, because that's the key an older copy would overwrite.
    static let legacyKey = "dailyResults"
    static let monthKeyPrefix = "results."
    static let resetKey = "statsResetAt"

    let cloud: CloudKeyValueStoring
    let stats: StatsStore

    static func monthKey(forSeed seed: Int64) -> String {
        "\(monthKeyPrefix)\(seed / 100)"
    }

    /// Merges the cloud into this Mac, then publishes whatever the cloud is missing.
    /// - Returns: Whether anything on this Mac changed.
    @discardableResult
    func sync() -> Bool {
        let changed = pull()
        publish()
        return changed
    }

    /// Merges the cloud into this Mac without writing anything back.
    /// - Returns: Whether anything on this Mac changed.
    @discardableResult
    func pull() -> Bool {
        var changed = false

        let resetAt = cloud.double(forKey: Self.resetKey)
        if resetAt > 0 {
            changed = stats.applyReset(at: Date(timeIntervalSinceReferenceDate: resetAt))
        }

        let remote = (cloud.allKeys.filter { $0.hasPrefix(Self.monthKeyPrefix) } + [Self.legacyKey])
            .compactMap { cloud.data(forKey: $0) }
            .flatMap(decode)

        return stats.merge(dailyResults: remote) || changed
    }

    /// Erases the cloud's history, and leaves a marker telling other Macs to do the same.
    func publishReset(at date: Date) {
        for key in cloud.allKeys where key.hasPrefix(Self.monthKeyPrefix) {
            cloud.removeObject(forKey: key)
        }
        cloud.removeObject(forKey: Self.legacyKey)
        cloud.set(date.timeIntervalSinceReferenceDate, forKey: Self.resetKey)
        cloud.synchronize()
    }

    private func publish() {
        let months = Dictionary(grouping: stats.dailyResults) { Self.monthKey(forSeed: $0.dailySeed) }
        var didWrite = false

        for (key, results) in months {
            guard let data = encode(results), data != cloud.data(forKey: key) else { continue }
            cloud.set(data, forKey: key)
            didWrite = true
        }

        if didWrite {
            cloud.synchronize()
        }
    }

    private func encode(_ results: [GameResult]) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        do {
            return try encoder.encode(results.sorted { $0.dailySeed < $1.dailySeed })
        } catch {
            Telemetry.report(error, area: "stats_sync", step: "encode")
            return nil
        }
    }

    private func decode(_ data: Data) -> [GameResult] {
        do {
            return try JSONDecoder().decode([GameResult].self, from: data)
        } catch {
            Telemetry.report(error, area: "stats_sync", step: "decode")
            return []
        }
    }
}

/// Keeps daily results in step across a player's Macs.
///
/// Streaks are the reason this exists: they are the thing that makes the daily worth coming
/// back to, and losing them to a new machine or a reinstall is the worst possible time to
/// lose them. Backed by `NSUbiquitousKeyValueStore`, which needs no CloudKit container.
///
/// Connected only in the App Store build. Key-value storage requires an entitlement the
/// direct-distribution build cannot carry without an embedded provisioning profile, and
/// Apple restricts the store to App Store distribution regardless.
@MainActor
enum StatsSync {
    /// Called when another Mac's results change something here.
    static var onResultsChanged: (() -> Void)?

    #if ICLOUD_SYNC_ENABLED
    private static var cloud: DailyResultsCloud? {
        DailyResultsCloud(cloud: NSUbiquitousKeyValueStore.default, stats: .shared)
    }
    private static var observer: NSObjectProtocol?

    /// Begins syncing, merging whatever the cloud already knows about.
    static func start() {
        guard observer == nil else { return }

        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default,
            queue: .main
        ) { notification in
            let reason = notification.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
            MainActor.assumeIsolated { handleExternalChange(reason: reason) }
        }

        NSUbiquitousKeyValueStore.default.synchronize()
        sync()
    }

    private static func handleExternalChange(reason: Int?) {
        switch reason {
        case NSUbiquitousKeyValueStoreQuotaViolationChange:
            Telemetry.warn("iCloud key-value quota exceeded", area: "stats_sync")
        case NSUbiquitousKeyValueStoreAccountChange:
            // These results belong to the previous account, so read the new one without
            // copying them into it.
            if cloud?.pull() == true {
                onResultsChanged?()
            }
        default:
            sync()
        }
    }
    #else
    private static var cloud: DailyResultsCloud? { nil }
    static func start() {}
    #endif

    /// Exchanges results with the cloud.
    static func sync() {
        if cloud?.sync() == true {
            onResultsChanged?()
        }
    }

    /// Erases every Mac's history along with this one's.
    static func publishReset(at date: Date) {
        cloud?.publishReset(at: date)
    }
}
