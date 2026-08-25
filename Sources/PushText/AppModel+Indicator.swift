import Foundation
import PushTextCore

/// Driving the HUD from the state machine.
///
/// Extracted when `AppModel` crossed swiftlint's 400-line file limit while #188 landed. `internal`
/// rather than `private` because a same-module extension cannot see `private`, which is the trade
/// `AppModel+Watchdog` already makes.
extension AppModel {

    func updateIndicator(for state: DictationState) {
        hud.update(for: state,
                   isCapturing: { [weak self] in self?.machine.isCapturing ?? false },
                   onCancel: { [weak self] in self?.apply(.cancelRequested) },
                   onConfirm: { [weak self] in self?.apply(.endRequested) })
    }
}
