import Foundation
import PushTextCore

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
        case .cancelled: "Cancelled"
        }
    }
}
