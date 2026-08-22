import Testing
import Foundation
@testable import PushTextKit
import PushTextCore

/// Records exactly what the engine was handed, in the order it was handed over.
///
/// `MockTranscriptionEngine` counts buffers, which cannot distinguish "100 buffers in order" from
/// "100 buffers shuffled" - and shuffled is the failure this suite exists for.
actor RecordingEngine: TranscriptionEngine {
    private(set) var received: [Double] = []
    private(set) var began = false
    private(set) var finished = false
    private var appendError: Error?

    enum Failure: Error, Equatable { case appendRefused }

    func failNextAppend() { appendError = Failure.appendRefused }

    var isAvailable: Bool { true }

    func beginUtterance() async throws {
        began = true
        received = []
    }

    func append(_ buffer: PushTextKit.AudioBuffer) async throws {
        // Yield before recording. Ordering is a property that only exists DURING the operation -
        // without an actual suspension point here, even a Task-per-buffer implementation could
        // record in order by luck, and the test would prove nothing.
        await Task.yield()
        if let appendError {
            self.appendError = nil
            throw appendError
        }
        received.append(buffer.startTime)
    }

    func finishUtterance() async throws -> Transcript {
        finished = true
        return Transcript(text: "recorded \(received.count)", duration: 0)
    }
}

@Suite("AudioFeed")
struct AudioFeedTests {

    private static func buffer(_ index: Int) -> PushTextKit.AudioBuffer {
        PushTextKit.AudioBuffer(samples: [0.1, 0.2], sampleRate: 48_000, startTime: Double(index))
    }

    /// THE point of this type. `AudioCapture.start(onBuffer:)` delivers on a serial drain queue -
    /// a synchronous, non-async context - while `TranscriptionEngine.append` is async on an actor.
    /// Spawning a Task per buffer does not preserve order, and `AnalyzerInput.bufferStartTime` must
    /// be monotonic: non-monotonic timestamps are one of the three suspected causes of FB22149971.
    ///
    /// 200 buffers, not 3: a handful can arrive in order by luck even on a broken implementation.
    @Test("Preserves submission order across the sync-to-async boundary")
    func preservesOrderUnderLoad() async throws {
        let engine = RecordingEngine()
        let feed = AudioFeed(engine: engine)
        try await feed.begin()

        let count = 200
        for index in 0..<count {
            feed.submit(Self.buffer(index))   // synchronous, as the drain queue calls it
        }
        _ = try await feed.finish()

        let received = await engine.received
        #expect(received.count == count, "dropped buffers: got \(String(received.count))")
        #expect(received == (0..<count).map(Double.init), "buffers arrived out of order")
    }

    /// Order is only half of it. A bounded buffering policy would silently DROP buffers under
    /// backpressure, which for dictation means dropped words - and the transcript would still look
    /// plausible, just short.
    @Test("Drops nothing when the producer outruns the consumer")
    func dropsNothingUnderBackpressure() async throws {
        let engine = RecordingEngine()
        let feed = AudioFeed(engine: engine)
        try await feed.begin()

        // Submit as fast as a tight loop allows, with no awaits, so the consumer cannot keep up.
        for index in 0..<1_000 {
            feed.submit(Self.buffer(index))
        }
        _ = try await feed.finish()

        #expect(await engine.received.count == 1_000)
    }

    @Test("Submitting before begin does not silently discard audio")
    func submitBeforeBeginIsRefused() async throws {
        let engine = RecordingEngine()
        let feed = AudioFeed(engine: engine)

        feed.submit(Self.buffer(0))

        try await feed.begin()
        _ = try await feed.finish()
        // The pre-begin buffer must not appear: it belongs to no utterance. What matters is that it
        // is not silently mixed into the NEXT one, which would corrupt that transcript.
        #expect(await engine.received.isEmpty)
    }

    @Test("finish returns the engine's transcript")
    func finishReturnsTranscript() async throws {
        let engine = RecordingEngine()
        let feed = AudioFeed(engine: engine)
        try await feed.begin()
        feed.submit(Self.buffer(0))
        feed.submit(Self.buffer(1))

        let transcript = try await feed.finish()

        #expect(transcript.text == "recorded 2")
    }

    /// An append failure must reach the caller. Swallowing it would produce a SHORT transcript that
    /// reads as a bad recognition rather than as a broken pipeline.
    @Test("An append failure surfaces from finish rather than being swallowed")
    func appendFailureSurfaces() async throws {
        let engine = RecordingEngine()
        await engine.failNextAppend()
        let feed = AudioFeed(engine: engine)
        try await feed.begin()
        feed.submit(Self.buffer(0))

        await #expect(throws: RecordingEngine.Failure.appendRefused) {
            _ = try await feed.finish()
        }
    }

    @Test("A second utterance starts clean rather than inheriting the first")
    func secondUtteranceStartsClean() async throws {
        let engine = RecordingEngine()
        let feed = AudioFeed(engine: engine)

        try await feed.begin()
        feed.submit(Self.buffer(0))
        _ = try await feed.finish()

        try await feed.begin()
        feed.submit(Self.buffer(7))
        _ = try await feed.finish()

        #expect(await engine.received == [7.0])
    }
}
