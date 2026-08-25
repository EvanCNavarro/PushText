import Foundation
import PushTextKit

/// Turning launch-at-login on and off (#162).
///
/// The state is READ THROUGH to `SMAppService` every time rather than cached. The user can disable
/// PushText in System Settings > General > Login Items without telling the app, and a stored `Bool`
/// would keep drawing ON while the app never started - the same shape as the permission rows that
/// claimed a grant the app did not hold (#152).
///
/// `loginItemRevision` exists because there is nothing else to observe: the truth lives in the
/// system, so SwiftUI has to be told the answer may have moved.
extension AppActions {

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try loginItem.enable()
            } else {
                try loginItem.disable()
            }
        } catch {
            // Reported rather than thrown: registration can fail for reasons the user cannot act on
            // from a menu, and a dictation utility that throws a dialog at a toggle is worse than
            // one that logs and leaves the switch reflecting reality on the next read.
            dictationLog.error("launch at login failed: \(error.localizedDescription, privacy: .public)")
        }
        loginItemRevision += 1
    }
}
