import Foundation
import PushTextCore
import PushTextKit

/// Turns a raw transcript into the text the user actually receives, and records it (#94).
///
/// Its own type for two reasons. The ORDER of these three steps is the entire content of the
/// `.cleaning` stage, and it deserves a place where that order is the subject rather than four
/// lines inside a state machine. And `AppModel` was at swiftlint's file-length limit - the same
/// pressure that produced `HUDDriver`, `CaptureWatchdog`, `ModelPreparer` and `PermissionAdvisor`.
@MainActor
struct TranscriptFinisher {

    let cleanup: (any CleanupProvider)?
    let dictionary: (any DictionaryStore)?
    let history: (any HistoryStore)?

    /// The order is load-bearing, and a naive wiring breaks both invariants it protects:
    ///
    /// 1. **The user's dictionary beats the model.** Cleanup is a guess; the dictionary is
    ///    configuration the user wrote by name. Running cleanup last lets it quietly undo
    ///    "PushText" back into "push text" - proved by planting exactly that, which fails
    ///    `dictionaryIsAppliedAfterCleanup`.
    /// 2. **History equals what was injected.** History was previously written in
    ///    `closeUtterance`, before any cleanup stage existed, which would have left it recording
    ///    pre-cleanup text while the user pasted post-cleanup text.
    func finish(_ transcript: Transcript) async -> String {
        // `clean` returns the raw transcript on EVERY failure path by contract, so there is no
        // error branch to write - a model that is missing, rate-limited or refused simply means no
        // polish. `isAvailable` first only to skip building a session that cannot answer.
        var text = transcript.text
        if let cleanup, await cleanup.isAvailable {
            text = (try? await cleanup.clean(transcript)) ?? text
        }

        // The user's own vocabulary (#82). #13 measured that the engine cannot be biased at all,
        // so this post-pass is the only mechanism there is for proper nouns.
        text = dictionary.map { CustomDictionary(entries: $0.load()).apply(to: text) } ?? text

        // Recorded before injection: the dictation happened whether or not the paste lands, and
        // losing the transcript to an injection failure is the one case where a user most wants to
        // go back and find it.
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            history?.append(HistoryRecord(text: text,
                                          recordedAt: Date(),
                                          durationSeconds: transcript.duration))
        }
        return text
    }
}
