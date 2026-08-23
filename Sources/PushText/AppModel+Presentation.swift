import Foundation
import PushTextCore
import PushTextKit

/// What the user is told, derived from the state machine and nothing else.
///
/// Separate from `AppModel` because it is a different job: that type drives the utterance
/// lifecycle, this one turns a state into words. Keeping them apart also means a copy change
/// cannot touch the concurrency-sensitive code, and the state driver stops growing on every
/// wording tweak.
@MainActor
extension AppModel {

    var statusText: String {
        switch machine.state {
        case .idle: "Ready"
        case .arming: "Starting..."
        case .recording: "Listening"
        case .transcribing: "Transcribing"
        case .cleaning: "Polishing"
        case .injecting: "Inserting"
        case .failed(let reason): Self.describe(reason)
        }
    }

    static func describe(_ failure: DictationFailure) -> String {
        switch failure {
        case .permissionDenied: "Permission needed"
        case .noSpeechDetected: "Didn't catch that"
        case .transcriptionFailed: "Transcription failed"
        case .injectionFailed: "Couldn't insert text"
        case .modelNotReady: "Preparing model..."
        case .cancelled: "Cancelled"
        }
    }
    /// Turns a lossy capture into one sentence the user can act on, or nil when nothing was lost.
    ///
    /// The three causes get three messages because their remedies differ. Telling someone their
    /// input device changed when it did not sends them looking for a cable; saying "some audio was
    /// lost" about a restart that FAILED understates losing the rest of the utterance.
    ///
    /// Silent when clean, deliberately. A notice on every dictation is one the user stops reading,
    /// which costs the real ones their meaning.
    static func captureWarning(for health: CaptureHealth) -> String? {
        guard !health.isClean else { return nil }

        if health.restartFailures > 0 {
            return "The input device changed and could not be reopened - the rest of this "
                + "dictation was not recorded."
        }
        if health.restarts > 0 {
            return "The input device changed while recording. A moment of audio was lost while "
                + "the new one started."
        }
        // Frames the realtime thread discarded because the drain fell behind: a load problem, not
        // a hardware one, so it must not mention the device.
        let seconds = Double(health.droppedFrames) / 48_000
        return String(format: "The Mac could not keep up and about %.1fs of audio was dropped.",
                      seconds)
    }

}
