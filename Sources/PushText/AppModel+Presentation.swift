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

    /// `statusText`, except nil when there is nothing to report (#128).
    ///
    /// The menu used to carry a State row permanently, and permanently it said "Ready" - you cannot
    /// open the menu mid-dictation except in the latched mode, so the row was a constant wearing the
    /// clothes of a readout. Deleting it was the wrong fix: `MenuContent` is the ONLY surface in the
    /// app that shows a `DictationFailure`, so "Preparing model...", "Permission needed" and
    /// "Didn't catch that" would have had nowhere left to appear. Hiding it while idle keeps all six
    /// messages and removes the noise.
    var activityText: String? {
        machine.state == .idle ? nil : statusText
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

    /// Preparation, phrased for a human, or nil when there is nothing worth saying.
    ///
    /// Silent when ready or not yet started: every run after the first is already installed, and a
    /// permanent "preparing" row is noise that trains the user to ignore the section it sits in.
    ///
    /// The preparing message carries the PERCENTAGE deliberately. "Preparing..." with no number is
    /// indistinguishable from a hang, which is the complaint #36 fixed at the other end of the
    /// pipeline and would be a poor thing to reintroduce here.
    static func preparationMessage(for preparation: ModelPreparation) -> String? {
        switch preparation {
        case .notStarted, .ready:
            return nil
        case .preparing(let fraction):
            return String(format: "Downloading the speech model - %.0f%% complete. "
                          + "Dictation will work once this finishes.", fraction * 100)
        case .failed(let reason):
            // Waiting will not fix this, so it must not read like progress.
            return "The speech model could not be installed, so dictation cannot run: \(reason)"
        }
    }

}
