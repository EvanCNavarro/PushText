import Foundation
import PushTextKit
import PushTextCore

/// Installs the on-device model and remembers how it went (#76).
///
/// Its own type for the same reason as `CaptureWatchdog`: it owns a piece of state with its own
/// lifetime and changes for its own reasons - a download's progress has nothing to do with driving
/// an utterance. Extracted the fourth time `AppModel` crossed the type-body limit, which by then
/// was clearly a statement about responsibilities rather than line counts.
@MainActor
final class ModelPreparer {

    private(set) var state: ModelPreparation = .notStarted

    /// Runs `prepare()` and records the outcome, so a failure reaches the UI rather than only the
    /// log - which is the gap #76 was filed for.
    func prepare(engine: any TranscriptionEngine) async {
        state = .preparing(fraction: 0)
        do {
            try await engine.prepare { [weak self] fraction in
                Task { @MainActor in self?.state = .preparing(fraction: fraction) }
            }
            state = .ready
        } catch {
            let reason = String(describing: error)
            dictationLog.error("model prepare failed: \(reason, privacy: .public)")
            state = .failed(reason)
        }
    }
}
