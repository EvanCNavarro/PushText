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
    /// - Returns: whether the tap is now armed. Reported rather than only logged so a caller can
    ///   retry after the user grants Accessibility and know whether it actually worked (#152).
    @discardableResult
    func start() -> Bool {
        do {
            try monitor.start(onEvent: onEdge)
            dictationLog.info("hotkey tap armed for \(self.monitor.bindingName, privacy: .public)")
            return true
        } catch {
            dictationLog.error("hotkey tap FAILED: \(String(describing: error), privacy: .public)")
            onFailure(error)
            return false
        }
    }

    /// Silence the tap while the settings recorder is capturing (#128), then re-arm it.
    ///
    /// `stop()` fully tears the tap down - it invalidates the mach port - and `start()` rebuilds
    /// from the binding the monitor still holds, so this is a genuine restart rather than a flag
    /// the callback consults. A flag would have been cheaper and wrong: the callback runs on the
    /// tap thread, and the edge it would have to drop is the very keypress being recorded.
    func suspend() {
        monitor.stop()
        dictationLog.info("hotkey tap suspended for recording")
    }

    func resume() {
        start()
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
