import Foundation
import Speech
import PushTextCore

/// Chooses the transcription engine for a real run.
///
/// **Why this is not `MockTranscriptionEngine` when the real engine is unavailable.** The mock
/// returns canned phrases - "um so I think we should probably ship the thing on Friday you know" -
/// and this app's entire output path is "type the transcript into whatever window has focus". A
/// silent fallback to canned text would paste fiction into a user's document and look like a
/// working dictation app while doing it. An engine that refuses is strictly safer than an engine
/// that invents, so unsupported systems get `UnsupportedTranscriptionEngine`, whose throw surfaces
/// through the existing failure path as a message.
public enum TranscriptionEngineFactory {

    /// The engine for a shipping run.
    public static func makeDefault() -> any TranscriptionEngine {
        if #available(macOS 26, *) {
            return AppleSpeechEngine()
        }
        return UnsupportedTranscriptionEngine(reason: .requiresMacOS26)
    }
}

/// A `TranscriptionEngine` that always fails, with a reason a human can act on.
///
/// Exists so "this machine cannot transcribe" is a visible, typed failure rather than either a
/// crash or - worse - plausible-looking invented text.
public actor UnsupportedTranscriptionEngine: TranscriptionEngine {

    public enum Reason: Error, Equatable, CustomStringConvertible {
        case requiresMacOS26
        case hardwareUnsupported

        public var description: String {
            switch self {
            case .requiresMacOS26:
                return "On-device dictation requires macOS 26 or later."
            case .hardwareUnsupported:
                return "This Mac's hardware does not support on-device speech recognition."
            }
        }
    }

    private let reason: Reason

    public init(reason: Reason) {
        self.reason = reason
    }

    public var isAvailable: Bool { false }

    public func beginUtterance() async throws { throw reason }

    public func append(_ buffer: PushTextKit.AudioBuffer) async throws { throw reason }

    public func finishUtterance() async throws -> Transcript { throw reason }
}
