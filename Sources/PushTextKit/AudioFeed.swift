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

    /// Identifies WHICH utterance a caller is talking about (#55).
    ///
    /// Without this the feed had one continuation and one pump for the whole object, while
    /// `AppModel` can legitimately have two `openUtterance()` tasks in flight: a quick tap goes
    /// `arming -> idle` while its task is still awaiting `begin()`, and a double press immediately
    /// arms the next one. The abandoning task then called `cancel()` and tore down whichever
    /// utterance happened to be installed - the NEW one. Measured result: stuck in `.transcribing`
    /// forever, 25 of 60 runs under load.
    ///
    /// Opaque on purpose. A caller can hold it and hand it back; it cannot invent one.
    public struct Utterance: Sendable, Equatable {
        fileprivate let id: Int
    }

    public enum FeedError: Error, Equatable {
        /// `finish` was called for an utterance that a newer `begin` has already superseded.
        case superseded
    }

    private let engine: any TranscriptionEngine

    /// Guards `continuation`, `pump` and `generation` together - they are ONE piece of state, and
    /// the bug was reading them as if they were three. Held only across non-blocking work.
    private let lock = NSLock()
    private var continuation: AsyncStream<PushTextKit.AudioBuffer>.Continuation?
    private var pump: Task<Error?, Never>?
    private var generation = 0

    /// Pumps that have started and not yet finished.
    ///
    /// A superseded utterance's pump is awaited by nobody - `cancel` and `finish` both no-op on a
    /// stale token - so if `install` failed to finish the old stream, the leak would be completely
    /// invisible from the public API. Counting them is what lets a test see it; without this the
    /// "old stream is finished" invariant is a comment rather than a checked property.
    private var livePumpCount = 0

    public init(engine: any TranscriptionEngine) {
        self.engine = engine
    }

    // The lock is taken ONLY inside these synchronous helpers - `NSLock.lock()` is unavailable
    // directly from an async context, and keeping all three uses here means one place to reason
    // about the invariant rather than three.
    /// Installs a new utterance and hands back whatever the previous one left behind, so the
    /// caller can tear it down. Returns the new token.
    private func install(
        _ value: AsyncStream<PushTextKit.AudioBuffer>.Continuation
    ) -> (token: Utterance, stale: AsyncStream<PushTextKit.AudioBuffer>.Continuation?) {
        lock.lock()
        defer { lock.unlock() }
        let stale = continuation
        continuation = value
        generation += 1
        return (Utterance(id: generation), stale)
    }

    private func changeLivePumps(_ delta: Int) {
        lock.lock(); defer { lock.unlock() }
        livePumpCount += delta
    }

    /// Test seam for the leak above.
    var livePumps: Int {
        lock.lock(); defer { lock.unlock() }
        return livePumpCount
    }

    private func setPump(_ task: Task<Error?, Never>?, for token: Utterance) {
        lock.lock()
        defer { lock.unlock() }
        // A newer utterance may have started while `begin` was awaiting the engine. Dropping this
        // pump on the floor is correct - its stream has already been finished by `install`.
        guard generation == token.id else { return }
        pump = task
    }

    private func currentContinuation() -> AsyncStream<PushTextKit.AudioBuffer>.Continuation? {
        lock.lock()
        defer { lock.unlock() }
        return continuation
    }

    /// Detaches the utterance's state, but ONLY if the token still names the current one.
    private func take(
        _ token: Utterance
    ) -> (AsyncStream<PushTextKit.AudioBuffer>.Continuation?, Task<Error?, Never>?)? {
        lock.lock()
        defer { lock.unlock() }
        guard generation == token.id else { return nil }
        let taken = (continuation, pump)
        continuation = nil
        pump = nil
        return taken
    }

    /// Opens an utterance and returns the token that identifies it.
    ///
    /// Calling this while another utterance is installed SUPERSEDES it: that stream is finished so
    /// its pump can complete rather than being orphaned waiting on a producer that will never
    /// arrive, and its token stops matching. That is the state the old single-slot design leaked.
    @discardableResult
    public func begin() async throws -> Utterance {
        try await engine.beginUtterance()

        let (stream, continuation) = AsyncStream<PushTextKit.AudioBuffer>.makeStream(
            bufferingPolicy: .unbounded)

        let (token, stale) = install(continuation)
        stale?.finish()

        let engine = self.engine
        changeLivePumps(1)
        let pump = Task {
            defer { self.changeLivePumps(-1) }
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
        setPump(pump, for: token)
        return token
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
    /// Closes the utterance named by `token` and returns its transcript.
    ///
    /// Throws `.superseded` rather than transcribing someone else's audio if a newer utterance has
    /// taken over. Silently returning an empty transcript would look like "you said nothing".
    public func finish(_ token: Utterance) async throws -> Transcript {
        guard let (continuation, pump) = take(token) else { throw FeedError.superseded }
        continuation?.finish()

        if let pump, let appendError = await pump.value {
            throw appendError
        }

        return try await engine.finishUtterance()
    }

    /// Abandons the utterance without asking for a transcript. For the watchdog and cancel paths.
    ///
    /// A stale token is a NO-OP, which is the whole point: the task that abandons a superseded
    /// utterance must not tear down the one that replaced it.
    public func cancel(_ token: Utterance) async {
        guard let (continuation, pump) = take(token) else { return }
        continuation?.finish()
        _ = await pump?.value
    }
}
