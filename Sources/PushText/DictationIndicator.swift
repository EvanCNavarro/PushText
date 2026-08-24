import Foundation
import PushTextCore

/// What the app needs from a recording indicator, so `AppModel` can be tested without creating a
/// window - and so a test can assert that the HUD was actually shown and hidden.
@MainActor
protocol DictationIndicator: AnyObject {
    func show(phase: HUDPhase, onCancel: @escaping () -> Void, onConfirm: @escaping () -> Void)
    func update(phase: HUDPhase, level: Double)
    /// Tell the user their press was REFUSED, as distinct from the app merely being busy (#99).
    ///
    /// The HUD already shows a working state, so "something is happening" is visible. What is not
    /// visible is that the key they just pressed did nothing - and the speech they are about to
    /// give it will not be captured.
    func acknowledgeRefusal()
    func hide()
}

extension DictationHUDController: DictationIndicator {}

/// Carries audio levels from the capture drain queue to the main thread.
///
/// Deliberately NOT a main-actor hop per buffer: capture delivers every 50 ms and the display only
/// needs the latest value, so the meter runs where the audio arrives and the UI samples it. The lock
/// is held only inside these synchronous methods - `NSLock.lock()` is unavailable from an async
/// context.
final class LevelSink: @unchecked Sendable {
    private let lock = NSLock()
    private var meter = AudioLevelMeter(smoothing: 0.35)
    private var latest: Double = 0

    func record(_ samples: [Float]) {
        lock.lock()
        latest = meter.level(for: samples)
        lock.unlock()
    }

    var current: Double {
        lock.lock()
        defer { lock.unlock() }
        return latest
    }

    func reset() {
        lock.lock()
        meter = AudioLevelMeter(smoothing: 0.35)
        latest = 0
        lock.unlock()
    }
}
