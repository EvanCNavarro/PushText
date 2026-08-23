import Foundation
import AppKit
import PushTextCore

/// Drives the recording HUD from dictation state (#89).
///
/// Its own type for the reason `CaptureWatchdog`, `ModelPreparer` and `PermissionAdvisor` are:
/// it owns state with its own lifetime and changes for display reasons, never because the
/// dictation flow changed. `AppModel` had crossed swiftlint's type-body limit four times in one
/// session, once per feature - a count that stopped being about lines and started being about
/// responsibilities.
///
/// **`levels` is deliberately `nonisolated`.** The audio callback runs on `AVAudioEngineCapture`'s
/// drain queue, and routing it through a `@MainActor` method would add a hop per buffer to a path
/// that currently has none. `LevelSink` is `@unchecked Sendable` with its own lock, so the queue
/// can feed it directly exactly as before.
///
/// (#89 called this path "realtime-adjacent". Checked rather than inherited: `handler(...)` is
/// called from `flush()` on a serial `DispatchQueue`, not from the sink node's realtime block. The
/// hop would have been a waste, not a correctness bug - the issue overstated it.)
@MainActor
final class HUDDriver {

    nonisolated let levels = LevelSink()

    private let indicator: (any DictationIndicator)?
    private var levelTimer: Timer?

    init(indicator: (any DictationIndicator)?) {
        self.indicator = indicator
    }

    /// The HUD follows STATE, so it cannot disagree with the machine about whether we are
    /// recording - the failure that would make the indicator a lie rather than a readout.
    ///
    /// `isCapturing` is passed as a closure rather than read from a model reference, so this type
    /// never needs to know what an `AppModel` is.
    func update(for state: DictationState,
                isCapturing: @escaping @MainActor () -> Bool,
                onCancel: @escaping @MainActor () -> Void,
                onConfirm: @escaping @MainActor () -> Void) {
        guard let indicator else { return }
        switch state {
        case .arming, .recording:
            indicator.show(phase: .recording, onCancel: onCancel, onConfirm: onConfirm)
            startLevelTimer(isCapturing: isCapturing)
        case .transcribing, .cleaning, .injecting:
            stopLevelTimer()
            indicator.update(phase: .working, level: 0)
        case .idle, .failed:
            stopLevelTimer()
            indicator.hide()
        }
    }

    /// 20 Hz: fast enough that the bars track speech, slow enough that it is not a per-buffer hop.
    private func startLevelTimer(isCapturing: @escaping @MainActor () -> Bool) {
        guard levelTimer == nil else { return }
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, isCapturing() else { return }
                self.indicator?.update(phase: .recording, level: self.levels.current)
            }
        }
        levelTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopLevelTimer() {
        levelTimer?.invalidate()
        levelTimer = nil
    }
}
