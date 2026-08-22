import Foundation
import PushTextCore

/// Carries captured audio across the synchronous-to-asynchronous boundary without reordering it.
///
/// **The problem it solves.** `AudioCapture.start(onBuffer:)` delivers buffers from a serial drain
/// queue - a synchronous, non-async context - while `TranscriptionEngine.append` is `async` on an
/// actor. The obvious bridge, a `Task` per buffer, does NOT preserve order: measured here at 200
/// buffers, it delivered `[0, 2, 1, 3, ...]` with further swaps throughout. That matters because
/// `AnalyzerInput.bufferStartTime` must be monotonic, and non-monotonic timestamps are one of the
/// three suspected causes of FB22149971 - the streaming bug the whole engine choice rests on.
///
/// **How.** One `AsyncStream` fed by `yield` (synchronous, ordered, safe to call from the audio
/// drain queue) and drained by exactly ONE task that awaits `append` sequentially. Order is then a
/// property of the single consumer, not of the scheduler.
///
/// Buffering is `.unbounded` deliberately. A bounded policy would silently DROP buffers under
/// backpressure, and dropped buffers in dictation are dropped words - a transcript that is merely
/// short reads as bad recognition rather than as a broken pipeline.
public final class AudioFeed: @unchecked Sendable {

    private let engine: any TranscriptionEngine

    /// Guards `continuation` only. Held for the duration of a `yield`, which does not block.
    private let lock = NSLock()
    private var continuation: AsyncStream<PushTextKit.AudioBuffer>.Continuation?

    private var pump: Task<Error?, Never>?

    public init(engine: any TranscriptionEngine) {
        self.engine = engine
    }

    // The lock is taken ONLY inside these synchronous helpers - `NSLock.lock()` is unavailable
    // directly from an async context, and keeping all three uses here means one place to reason
    // about the invariant rather than three.
    private func setContinuation(_ value: AsyncStream<PushTextKit.AudioBuffer>.Continuation) {
        lock.lock()
        continuation = value
        lock.unlock()
    }

    private func currentContinuation() -> AsyncStream<PushTextKit.AudioBuffer>.Continuation? {
        lock.lock()
        defer { lock.unlock() }
        return continuation
    }

    private func takeContinuation() -> AsyncStream<PushTextKit.AudioBuffer>.Continuation? {
        lock.lock()
        defer { lock.unlock() }
        let value = continuation
        continuation = nil
        return value
    }

    /// Opens an utterance. Safe to call again after `finish()`.
    public func begin() async throws {
        try await engine.beginUtterance()

        let (stream, continuation) = AsyncStream<PushTextKit.AudioBuffer>.makeStream(
            bufferingPolicy: .unbounded)

        setContinuation(continuation)

        let engine = self.engine
        pump = Task {
            // Returns the FIRST append error rather than throwing, and keeps draining. Stopping
            // early would leave the producer yielding into a stream nobody reads, and the caller
            // learns about the failure from `finish()` either way.
            var firstError: Error?
            for await buffer in stream {
                guard firstError == nil else { continue }
                do {
                    try await engine.append(buffer)
                } catch {
                    firstError = error
                }
            }
            return firstError
        }
    }

    /// Hands over one buffer. Synchronous and non-blocking, so it is safe to call from the audio
    /// drain queue. Buffers submitted outside an utterance are ignored rather than queued - mixing
    /// them into the NEXT utterance would corrupt that transcript.
    public func submit(_ buffer: PushTextKit.AudioBuffer) {
        currentContinuation()?.yield(buffer)
    }

    /// Closes the utterance and returns the transcript.
    ///
    /// Waits for every submitted buffer to reach the engine before finalising - without that the
    /// engine would be asked for a transcript of audio it had not yet been given.
    public func finish() async throws -> Transcript {
        takeContinuation()?.finish()

        if let pump {
            let appendError = await pump.value
            self.pump = nil
            if let appendError { throw appendError }
        }

        return try await engine.finishUtterance()
    }

    /// Abandons the utterance without asking for a transcript. For the watchdog and cancel paths.
    public func cancel() async {
        takeContinuation()?.finish()
        _ = await pump?.value
        pump = nil
    }
}
