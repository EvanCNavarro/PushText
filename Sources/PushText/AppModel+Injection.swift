import Foundation
import PushTextCore
import PushTextKit

/// Putting the finished text into whatever app is frontmost.
///
/// Separate from `AppModel` for the same reason `AppModel+Failures` is: this changes when the
/// injection mechanism or its logging changes, never when the dictation flow does. It is also the
/// one stage that talks to another application rather than to this one.
@MainActor
extension AppModel {

    func injectText(_ text: String) async {
        guard let injector else {
            apply(.injectionFinished)
            return
        }
        do {
            try await injector.inject(text)
            // This spans mic teardown, finalize, injection AND the injector's post-paste settle
            // wait, so it is strictly larger than the engine's own finalize time - the probe
            // measures that part alone (docs/verification/task15-latency.md).
            if let releasedAt {
                let elapsed = ContinuousClock.now - releasedAt
                let millis = Double(elapsed.components.seconds) * 1000
                    + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000
                // `privacy: .public` or os_log redacts this to <private> - which is exactly what
                // the first real dictation after #15 shipped logged. This line exists to be read.
                let ms = String(format: "%.0f", millis)
                dictationLog.info("injected chars=\(text.count) releaseToText=\(ms, privacy: .public)ms")
            } else {
                dictationLog.info("injected chars=\(text.count)")
            }
            releasedAt = nil
            pendingText = nil
            apply(.injectionFinished)
        } catch {
            dictationLog.error("inject FAILED: \(String(describing: error), privacy: .public)")
            apply(.failure(.injectionFailed))
        }
    }
}
