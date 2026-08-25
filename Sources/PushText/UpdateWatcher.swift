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

    /// A failed check is NOT "up to date". Reporting it as unavailable would tell the user they are
    /// current when the app has no idea - which is the same shape as a CI summary where zero checks
    /// and all-green render identically.
    nonisolated func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
                             error: (any Error)?) {
        // LOGGED, always. A passive probe that fails silently is indistinguishable from one that
        // ran and found nothing - and both render as no dot, which is how "the indicator is broken"
        // and "you are up to date" became the same picture (#170).
        guard let error else {
            dictationLog.info("update check: cycle finished cleanly")
            return
        }
        dictationLog.error("update check FAILED: \(error.localizedDescription, privacy: .public)")
        Task { @MainActor in self.onChange?(.failed) }
    }
}
