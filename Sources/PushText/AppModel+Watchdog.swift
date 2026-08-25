import Foundation
import PushTextCore

/// Arming and disarming the capture-duration watchdog.
///
/// Extracted when `AppModel` crossed swiftlint's 400-line file limit (#172). `internal` rather than
/// `private` because a same-module extension cannot see `private`, which is the normal Swift
/// trade-off for this split and the one `AppModel+Permissions` already makes.
extension AppModel {

    func startCaptureWatchdog() {
        watchdog.arm { [weak self] in
            // Recorded BEFORE the event, so `closeUtterance` can explain the truncation (#197).
            self?.endedByWatchdog = true
            self?.apply(.watchdogExpired)
        }
    }

    func stopCaptureWatchdog() { watchdog.disarm() }

    /// What the transcript card says when the ceiling, rather than the user, ended the capture
    /// (#197).
    ///
    /// It WINS over a capture-health warning: being cut off at the limit explains a transcript that
    /// stops mid-sentence, and a dropped-frame count does not. Bobby described the old silent
    /// version as the app having "just died out" - the words are kept now, and saying why they stop
    /// is the other half of not leaving him guessing.
    var watchdogTruncationWarning: String {
        "Stopped at the \(Int(maximumCaptureDuration / 60))-minute limit. "
            + "Everything up to that point was kept."
    }
}
