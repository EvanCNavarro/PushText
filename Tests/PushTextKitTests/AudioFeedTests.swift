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
        let token = try await feed.begin()

        let count = 200
        for index in 0..<count {
            feed.submit(Self.buffer(index))   // synchronous, as the drain queue calls it
        }
        _ = try await feed.finish(token)

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
        let token = try await feed.begin()

        // Submit as fast as a tight loop allows, with no awaits, so the consumer cannot keep up.
        for index in 0..<1_000 {
            feed.submit(Self.buffer(index))
        }
        _ = try await feed.finish(token)

        #expect(await engine.received.count == 1_000)
    }

    @Test("Submitting before begin does not silently discard audio")
    func submitBeforeBeginIsRefused() async throws {
        let engine = RecordingEngine()
        let feed = AudioFeed(engine: engine)

        feed.submit(Self.buffer(0))

        let token = try await feed.begin()
        _ = try await feed.finish(token)
        // The pre-begin buffer must not appear: it belongs to no utterance. What matters is that it
        // is not silently mixed into the NEXT one, which would corrupt that transcript.
        #expect(await engine.received.isEmpty)
    }

    @Test("finish returns the engine's transcript")
    func finishReturnsTranscript() async throws {
        let engine = RecordingEngine()
        let feed = AudioFeed(engine: engine)
        let token = try await feed.begin()
        feed.submit(Self.buffer(0))
        feed.submit(Self.buffer(1))

        let transcript = try await feed.finish(token)

        #expect(transcript.text == "recorded 2")
    }

    /// An append failure must reach the caller. Swallowing it would produce a SHORT transcript that
    /// reads as a bad recognition rather than as a broken pipeline.
    @Test("An append failure surfaces from finish rather than being swallowed")
    func appendFailureSurfaces() async throws {
        let engine = RecordingEngine()
        await engine.failNextAppend()
        let feed = AudioFeed(engine: engine)
        let token = try await feed.begin()
        feed.submit(Self.buffer(0))

        await #expect(throws: RecordingEngine.Failure.appendRefused) {
            _ = try await feed.finish(token)
        }
    }

    /// #55: two `openUtterance` tasks can be in flight at once, because a quick tap goes
    /// `arming -> idle` while its task still awaits `begin()` and a double press immediately arms
    /// the next. The abandoning task then called `cancel()` with no idea WHICH utterance it was
    /// abandoning, and tore down its successor. Measured symptom: stuck in `.transcribing`
    /// forever, 25 of 60 runs under CPU load.
    @Test("A stale cancel cannot abandon the utterance that replaced it")
    func staleCancelLeavesTheCurrentUtteranceAlone() async throws {
        let engine = RecordingEngine()
        let feed = AudioFeed(engine: engine)

        let abandoned = try await feed.begin()
        let live = try await feed.begin()

        await feed.cancel(abandoned)   // stale: must be a no-op

        feed.submit(Self.buffer(5))
        _ = try await feed.finish(live)

        // The buffer proves the live utterance's stream was still open. Asserting only that
        // `finish` returned would pass even if the stream had been torn down underneath it.
        #expect(await engine.received == [5.0])
    }

    /// The other half: a superseded utterance must not quietly collect the NEW one's transcript.
    /// Returning something plausible here would hand the user text from an utterance they had
    /// already abandoned.
    @Test("Finishing a superseded utterance throws rather than taking the newer transcript")
    func supersededFinishThrows() async throws {
        let feed = AudioFeed(engine: RecordingEngine())

        let abandoned = try await feed.begin()
        _ = try await feed.begin()

        await #expect(throws: AudioFeed.FeedError.superseded) {
            _ = try await feed.finish(abandoned)
        }
    }

    /// Superseding must FINISH the old stream, not orphan it. A pump left awaiting a producer
    /// that will never arrive is the deadlock #55 hit - `finish` awaited `pump.value` forever.
    ///
    /// Asserted on the live-pump COUNT, not on `cancel` returning: a stale `cancel` no-ops, so a
    /// test that merely called it would complete happily while the pump leaked. That version was
    /// written first and survived the planted regression, which is how it was caught.
    @Test("Superseding an utterance completes its pump instead of orphaning it")
    func supersedingCompletesTheOldPump() async throws {
        let feed = AudioFeed(engine: RecordingEngine())

        _ = try await feed.begin()
        let live = try await feed.begin()

        var remaining = feed.livePumps
        let deadline = ContinuousClock.now + .seconds(2)
        while remaining > 1, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
            remaining = feed.livePumps
        }
        #expect(remaining == 1, "superseded pump never finished; \(remaining) still live")

        _ = try await feed.finish(live)
    }

    func secondUtteranceStartsClean() async throws {
        let engine = RecordingEngine()
        let feed = AudioFeed(engine: engine)

        let token = try await feed.begin()
        feed.submit(Self.buffer(0))
        _ = try await feed.finish(token)

        let second = try await feed.begin()
        feed.submit(Self.buffer(7))
        _ = try await feed.finish(second)

        #expect(await engine.received == [7.0])
    }
}
