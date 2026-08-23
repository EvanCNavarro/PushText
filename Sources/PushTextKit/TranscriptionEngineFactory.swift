import Foundation
import PushTextCore

/// Chooses the transcription engine for a real run.
public enum TranscriptionEngineFactory {

    /// There is exactly one engine, and no gate in front of it (#16).
    ///
    /// This used to be two nested checks - `canImport(FoundationModels)` for "built against the 26
    /// SDK" and `#available(macOS 26, *)` for "running on 26" - with an `UnsupportedTranscriptionEngine`
    /// behind both. The package floor is now macOS 26 and `LSMinimumSystemVersion` matches it, so
    /// neither branch is reachable: an older SDK cannot compile the package, and the OS will not
    /// launch the app below the floor.
    ///
    /// The concern that fallback carried has not been dropped, it has moved to where it can
    /// actually be detected. Unsupported HARDWARE - macOS 26 on a Mac whose Neural Engine cannot
    /// run the model - is not a version question and was never caught here; `AppleSpeechEngine`
    /// throws `EngineError.unavailable` for it off `SpeechTranscriber.isAvailable`, and that
    /// surfaces through the same failure path. Keeping an unreachable second guard would have
    /// implied a check that was not happening.
    public static func makeDefault() -> any TranscriptionEngine {
        AppleSpeechEngine()
    }
}
