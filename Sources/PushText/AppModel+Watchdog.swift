import Foundation
import PushTextCore

/// Arming and disarming the capture-duration watchdog.
///
/// Extracted when `AppModel` crossed swiftlint's 400-line file limit (#172). `internal` rather than
/// `private` because a same-module extension cannot see `private`, which is the normal Swift
/// trade-off for this split and the one `AppModel+Permissions` already makes.
extension AppModel {

    func startCaptureWatchdog() {
        watchdog.arm { [weak self] in self?.apply(.watchdogExpired) }
    }

    func stopCaptureWatchdog() { watchdog.disarm() }
}
