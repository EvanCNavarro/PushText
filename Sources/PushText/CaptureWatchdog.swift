import Foundation

/// Force-closes a capture that has run too long.
///
/// Its own type because it is the ONLY defence against the measured stuck-capture case and has
/// nothing to do with the rest of the dictation flow: a stalled `.defaultTap` can drop a modifier
/// key-up so thoroughly that macOS's own `flagsState` stays latched, leaving the event stream and
/// the live flag state both wrong. Every state-based recovery is blind to that; elapsed time is the
/// one signal that cannot be corrupted the same way.
///
/// Extracted from `AppModel` on the third time that class crossed the type-body limit - which is a
/// signal about responsibilities rather than about line counts.
@MainActor
final class CaptureWatchdog {

    /// Generous on purpose: it exists to stop a stuck microphone, not to cut off a long sentence.
    var maximumDuration: TimeInterval = 120

    private var timer: Timer?

    var isArmed: Bool { timer != nil }

    /// Arms the watchdog, replacing any previous one. A duration of zero disables it entirely,
    /// which is what the tests use to prove the timer is what fires rather than something else.
    func arm(onExpiry: @escaping @MainActor () -> Void) {
        disarm()
        guard maximumDuration > 0 else { return }
        let timer = Timer(timeInterval: maximumDuration, repeats: false) { _ in
            Task { @MainActor in onExpiry() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func disarm() {
        timer?.invalidate()
        timer = nil
    }
}
