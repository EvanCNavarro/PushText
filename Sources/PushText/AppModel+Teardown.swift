import Foundation
import PushTextCore

/// Closing the microphone and abandoning an utterance.
///
/// Extracted when `AppModel` crossed swiftlint's 400-line file limit while #188 landed. `internal`
/// rather than `private` for the reason `AppModel+Watchdog` records: a same-module extension cannot
/// see `private`.
extension AppModel {

    /// Runs on every failure path. The microphone staying open is the worst outcome this app has -
    /// worse than losing the utterance - so it is closed unconditionally.
    /// Synchronous on purpose. A microphone left open is the worst outcome this app has - worse
    /// than losing the utterance - so it closes in the same turn as the decision to stop, not
    /// whenever a Task happens to be scheduled. Idempotent, so the async teardown may call it again.
    func closeMicrophone() {
        capture?.stop()
    }

    func teardown() async {
        closeMicrophone()
        if let token = utterance {
            utterance = nil
            await feed.cancel(token)
        }
        pendingText = nil
    }
}
