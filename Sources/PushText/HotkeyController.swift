import Foundation
import PushTextCore
import PushTextKit

/// Owns the event tap and can re-point it at a different key while the app runs (#104).
///
/// A reference type because `PushTextApp` is a `struct App`: the rebind arrives on an escaping
/// closure from the settings, and a struct cannot mutate itself from one. The monitor's binding is
/// fixed at construction, so switching keys means tearing the tap down and building another - which
/// is exactly why this is a type and not two lines in the composition root.
@MainActor
final class HotkeyController {

    private var monitor: CGEventTapHotkeyMonitor
    private let onEdge: @Sendable (HotkeyEdge) -> Void
    private let onFailure: @MainActor (any Error) -> Void

    init(binding: HotkeyBinding,
         onEdge: @escaping @Sendable (HotkeyEdge) -> Void,
         onFailure: @escaping @MainActor (any Error) -> Void) {
        self.monitor = CGEventTapHotkeyMonitor(binding: binding)
        self.onEdge = onEdge
        self.onFailure = onFailure
    }

    /// One place that starts a tap, used by both the launch path and every rebind - so a failure is
    /// reported the same way whichever brought it about (FL-5).
    func start() {
        do {
            try monitor.start(onEvent: onEdge)
            dictationLog.info("hotkey tap armed for \(self.monitor.bindingName, privacy: .public)")
        } catch {
            dictationLog.error("hotkey tap FAILED: \(String(describing: error), privacy: .public)")
            onFailure(error)
        }
    }

    /// Stop the old tap BEFORE creating the new one. Two live taps on different modifiers would both
    /// deliver edges into the same state machine, and the second key would look like it was starting
    /// utterances the first one never finished.
    func rebind(to binding: HotkeyBinding) {
        monitor.stop()
        monitor = CGEventTapHotkeyMonitor(binding: binding)
        start()
    }
}
