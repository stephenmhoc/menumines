import Foundation
import Sentry

/// The only file that talks to Sentry.
///
/// Reports crashes, hangs and failures from released builds, and nothing that describes the
/// player. Everything that records URLs, files or screens is off, and a handled error sends
/// its domain and code rather than the error itself, whose description can hold a file path.
/// Whether a player sends reports at all is their choice, in Settings.
enum Telemetry {
    private static var dsn: String? {
        guard let dsn = Bundle.main.object(forInfoDictionaryKey: "SENTRY_DSN") as? String else {
            return nil
        }
        let trimmed = dsn.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Local builds and tests have no DSN, so they can't report.
    static var isAvailable: Bool {
        dsn != nil
    }

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: Constants.SettingsKeys.sendCrashReports) as? Bool ?? true
    }

    static func start() {
        guard isEnabled, !SentrySDK.isEnabled, let dsn else { return }

        SentrySDK.start { options in
            options.dsn = dsn
            options.sendDefaultPii = false

            options.enableCrashHandler = true
            options.enableAppHangTracking = true
            // AppKit swallows exceptions raised in the run loop unless this is on.
            options.enableUncaughtNSExceptionReporting = true
            options.enableAutoSessionTracking = true

            options.enableNetworkTracking = false
            options.enableNetworkBreadcrumbs = false
            options.enableCaptureFailedRequests = false
            options.enableFileIOTracing = false
            options.enableAutoBreadcrumbTracking = false
            options.enableAutoPerformanceTracing = false
            options.tracePropagationTargets = []
            options.tracesSampleRate = 0

            options.beforeSend = { event in
                isModalWaitReportedAsHang(event) ? nil : event
            }
        }
    }

    /// Applies the player's choice straight away.
    static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Constants.SettingsKeys.sendCrashReports)
        if enabled {
            start()
        } else {
            SentrySDK.close()
        }
    }

    /// Reports a handled failure.
    /// - Parameters:
    ///   - area: A stable name for the feature, for grouping.
    ///   - step: A stable name for what was being attempted.
    static func report(_ error: Error, area: String, step: String) {
        guard SentrySDK.isEnabled else { return }

        let nsError = error as NSError
        let sanitized = NSError(domain: nsError.domain, code: nsError.code)
        SentrySDK.capture(error: sanitized) { scope in
            scope.setTag(value: area, key: "area")
            scope.setTag(value: step, key: "step")
        }
    }

    /// Reports something that shouldn't happen but didn't fail outright.
    /// - Parameter message: A fixed string. Never interpolate anything into it.
    static func warn(_ message: StaticString, area: String) {
        guard SentrySDK.isEnabled else { return }

        SentrySDK.capture(message: "\(message)") { scope in
            scope.setLevel(.warning)
            scope.setTag(value: area, key: "area")
        }
    }
}

/// Whether an app-hang report is really a modal dialog waiting on the user.
///
/// `NSAlert.runModal()` blocks the main thread in a nested run loop until someone clicks a
/// button, which the hang detector cannot distinguish from a genuine stall. Sparkle's update
/// prompts arrive this way and would otherwise bury real hangs in noise, so they are dropped
/// here rather than by turning hang tracking off entirely.
func isModalWaitReportedAsHang(_ event: Event) -> Bool {
    guard let exception = event.exceptions?.first else { return false }

    let frameFunctions = (exception.stacktrace?.frames ?? []).compactMap(\.function)
    return isModalWaitStack(
        exceptionType: exception.type,
        mechanismType: exception.mechanism?.type,
        frameFunctions: frameFunctions
    )
}

/// Pure form of ``isModalWaitReportedAsHang(_:)``, split out so it can be tested without
/// building a Sentry event.
func isModalWaitStack(
    exceptionType: String?,
    mechanismType: String?,
    frameFunctions: [String]
) -> Bool {
    let isHangReport = mechanismType?.caseInsensitiveCompare("AppHang") == .orderedSame
        || exceptionType?.localizedCaseInsensitiveContains("hang") == true
    guard isHangReport else { return false }

    // -[NSAlert runModal], -[NSApplication runModalForWindow:], _NSTryRunModal,
    // -[NSApplication _doModalLoop:peek:]
    let modalMarkers = ["runmodal", "_domodalloop"]
    return frameFunctions.contains { function in
        let lowercased = function.lowercased()
        return modalMarkers.contains { lowercased.contains($0) }
    }
}
