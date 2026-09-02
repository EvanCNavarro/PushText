import Sparkle
import PushTextCore
import MacFaceKit

/// Records what a Sparkle check found, so the menu can show a mark (#138).
///
/// Separate from `AppActions` because it must be an `NSObject` conforming to `SPUUpdaterDelegate`,
/// and because it has one job: translate Sparkle's callbacks into `UpdateAvailability`.
@MainActor
final class UpdateWatcher: NSObject, SPUUpdaterDelegate {
    var onChange: ((UpdateAvailability) -> Void)?

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        dictationLog.info("update check: found \(version ?? "?", privacy: .public)")
        Task { @MainActor in self.onChange?(.available(version: version)) }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        dictationLog.info("update check: none found")
        Task { @MainActor in self.onChange?(.unavailable) }
    }

    /// Whether an error that ENDED an update cycle means the CHECK failed.
    ///
    /// Sparkle delivers "no update found" through `didFinishUpdateCycleFor` as an `NSError` in
    /// `SUSparkleErrorDomain` with code `SUNoUpdateError`, whose `localizedDescription` is the
    /// user-facing string "You're up to date!". So the outcome that means SUCCESS arrives on the
    /// error path, and treating every error as a failure recorded every clean check as broken
    /// (#241) - the log carried `update check: none found` and `update check FAILED: You're up to
    /// date!` 42 ms apart, and the second one was the one that set state.
    ///
    /// A user declining the install is not a failed check either: the check ran, found an update,
    /// and did its job.
    ///
    /// The codes are MEASURED, not read off the header - 1001 and 4007 printed by a binary linked
    /// against the vendored framework - and referenced through Sparkle's own symbols so this cannot
    /// drift from the framework it describes.
    ///
    /// Pure over `(domain, code)` because that is the seam whose absence let this ship:
    /// `UpdateIndicatorTests` covered how each `UpdateAvailability` RENDERS, and nothing covered the
    /// mapping onto one. What is still NOT covered is the delegate wiring itself - reaching that
    /// needs a live `SPUUpdater` - so this function being right is necessary and not sufficient.
    /// `nonisolated` because the delegate callbacks that need it are, and it touches nothing
    /// but its two arguments.
    nonisolated static func isCheckFailure(domain: String, code: Int) -> Bool {
        guard domain == SUSparkleErrorDomain else { return true }
        return code != SUError.noUpdateError.rawValue
            && code != SUError.installationCanceledError.rawValue
    }

    /// A failed check is NOT "up to date". Reporting it as unavailable would tell the user they are
    /// current when the app has no idea - which is the same shape as a CI summary where zero checks
    /// and all-green render identically.
    ///
    /// The overcorrection is the bug this now guards: that reasoning is right, and the code took it
    /// to mean every error is a failure, which made "up to date" render as "broken" instead (#241).
    nonisolated func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
                             error: (any Error)?) {
        // LOGGED, always. A passive probe that fails silently is indistinguishable from one that
        // ran and found nothing - and both render as no dot, which is how "the indicator is broken"
        // and "you are up to date" became the same picture (#170).
        guard let error else {
            dictationLog.info("update check: cycle finished cleanly")
            return
        }
        let failure = error as NSError
        guard Self.isCheckFailure(domain: failure.domain, code: failure.code) else {
            // NO state change: `updaterDidNotFindUpdate` owns the up-to-date answer and has already
            // set it. Setting it again here would be harmless today and would quietly become the
            // authority if that callback ever stopped firing, which is the kind of duplicate
            // ownership that makes a wrong indicator hard to trace.
            dictationLog.info("""
                update check finished: \(error.localizedDescription, privacy: .public) \
                (not a failure)
                """)
            return
        }
        dictationLog.error("update check FAILED: \(error.localizedDescription, privacy: .public)")
        Task { @MainActor in self.onChange?(.failed) }
    }
}
