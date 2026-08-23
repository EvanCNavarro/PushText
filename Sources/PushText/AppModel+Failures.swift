import Foundation
import PushTextKit
import PushTextCore

/// Maps OS-level errors onto the domain failures the user is shown.
///
/// Separate from `AppModel` because it is a translation table, not lifecycle logic: it changes when
/// a new error case appears in an adapter, never when the dictation flow changes.
@MainActor
extension AppModel {

    static func classify(_ error: Error) -> DictationFailure {
        if let captureError = error as? AVAudioEngineCapture.CaptureError,
           captureError == .microphoneNotAuthorized {
            return .permissionDenied
        }
        // "Transcription failed" would send the user looking for a fault that does not exist; this
        // one resolves itself once the download `prepare()` started has finished (#36).
        if let engineError = error as? AppleSpeechEngine.EngineError, engineError == .modelNotReady {
            return .modelNotReady
        }
        return .transcriptionFailed
    }
}
