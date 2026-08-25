import Foundation
import PushTextCore
import PushTextKit

/// Recovering after the user fixes a permission (#152).
///
/// Its own file because `AppModel.swift` sits six lines under swiftlint's 400-line limit, and
/// because this changes when OS grant handling changes rather than when the dictation flow does -
/// the reasoning that already produced `PermissionAdvisor`, `HUDDriver` and `TranscriptFinisher`.
@MainActor
extension AppModel {

    /// Called when the menu opens: retry anything the user has since fixed, then recompute the rows.
    func refreshPermissionAdvice() {
        guard let onRetryPermission else {
            advisor.refresh()
            return
        }
        retryPermissionFailures(onRetryPermission)
    }

    /// Retries whatever failed, once the user has actually fixed it.
    ///
    /// #136 made a runtime failure outrank the probe. That is right while the failure is CURRENT and
    /// wrong once the user has granted the permission - and nothing ever cleared it, so Bobby
    /// granted Accessibility and the menu kept showing three NEEDS ATTENTION rows while the app's
    /// own probe reported `microphone=granted accessibility=granted postEvent=granted`.
    ///
    /// Clearing on "the probe says granted" ALONE would be worse than the bug. The event tap stays
    /// dead until something re-arms it, so the menu would report health the app does not have -
    /// the same shape as a green check that verified nothing. So this retries, and clears only what
    /// comes back working.
    ///
    /// - Parameter retry: performs the real thing for one permission - re-arming the tap, for
    ///   instance - and reports whether it now works.
    func retryPermissionFailures(_ retry: (Permission) -> Bool) {
        for permission in advisor.runtimeFailures where probeSaysGranted(permission) {
            if retry(permission) {
                advisor.runtimeFailures.remove(permission)
            }
        }
        advisor.refresh()
    }

    /// No retry while the permission is genuinely still missing: re-arming a tap that cannot work
    /// just fails noisily on every menu open.
    private func probeSaysGranted(_ permission: Permission) -> Bool {
        advisor.probe?.status(of: permission) == .granted
    }
}
