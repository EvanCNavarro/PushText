import Foundation
import PushTextCore

/// A `TranscriptionEngine` that returns canned text on a timer.
///
/// Not a test double — this is the Phase 0 production engine. The real one cannot be compiled on
/// this machine (Xcode 16.2 ships the macOS 15.2 SDK; `SpeechAnalyzer` does not exist in it), so
/// the entire pipeline — hotkey, capture, HUD, cleanup guard, injection, packaging — is built and
/// exercised end-to-end against this, and the Apple engine is swapped in at Phase 2.
///
/// It counts appended buffers so the audio path is genuinely proven rather than merely present:
/// a capture bug that delivers nothing would otherwise look identical to a working one.
public actor MockTranscriptionEngine: TranscriptionEngine {
    public struct Configuration: Sendable {
        /// Text to return. Cycled, so consecutive utterances differ and a stuck result is visible.
        public var phrases: [String]
        /// Simulated time between `finishUtterance()` and the result.
        public var latency: Duration
        /// If true, `finishUtterance()` throws — for exercising the failure path.
        public var shouldFail: Bool

        public init(
            phrases: [String] = Configuration.defaultPhrases,
            latency: Duration = .milliseconds(400),
            shouldFail: Bool = false
        ) {
            self.phrases = phrases
            self.latency = latency
            self.shouldFail = shouldFail
        }

        /// Deliberately messy: filler words, a dictated question, and a run-on. These are the
        /// three cases the cleanup guard has to survive — especially the question, which is what
        /// makes a model answer "Paris" instead of cleaning the sentence.
        public static let defaultPhrases: [String] = [
            "um so I think we should probably ship the thing on Friday you know",
            "what is the capital of France",
            "the quick brown fox jumps over the lazy dog and then it keeps going and going"
        ]
    }

    public enum MockError: Error, Equatable {
        case simulatedFailure
        case notStarted
    }

    private var configuration: Configuration
    private var utteranceIndex = 0
    private var startedAt: ContinuousClock.Instant?
    private var bufferCount = 0
    private var sampleCount = 0

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    public var isAvailable: Bool { true }

    /// How many buffers the last utterance received. Lets a test assert the audio path is live.
    public var lastBufferCount: Int { bufferCount }
    public var lastSampleCount: Int { sampleCount }

    public func configure(_ configuration: Configuration) {
        self.configuration = configuration
    }

    public func beginUtterance() async throws {
        startedAt = ContinuousClock.now
        bufferCount = 0
        sampleCount = 0
    }

    public func append(_ buffer: AudioBuffer) async throws {
        guard startedAt != nil else { throw MockError.notStarted }
        bufferCount += 1
        sampleCount += buffer.samples.count
    }

    public func finishUtterance() async throws -> Transcript {
        guard let startedAt else { throw MockError.notStarted }
        try await Task.sleep(for: configuration.latency)
        self.startedAt = nil

        if configuration.shouldFail { throw MockError.simulatedFailure }
        guard !configuration.phrases.isEmpty else {
            return Transcript(text: "", duration: 0)
        }

        let phrase = configuration.phrases[utteranceIndex % configuration.phrases.count]
        utteranceIndex += 1
        let elapsed = ContinuousClock.now - startedAt
        return Transcript(text: phrase, duration: elapsed.seconds)
    }
}

extension Duration {
    /// `Duration` to seconds, without going through `TimeInterval(describing:)`.
    var seconds: TimeInterval {
        let (secs, attos) = components
        return TimeInterval(secs) + TimeInterval(attos) / 1e18
    }
}
