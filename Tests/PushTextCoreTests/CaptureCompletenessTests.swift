import Testing
import Foundation
@testable import PushTextCore

/// The only guard against SILENT truncation (#70, #124).
///
/// `monotonic`, `contiguous` and `dropped=0` all describe only the frames that DID arrive, so they
/// are blind to truncation by construction - every one of them passed on runs that lost 5 of 8
/// seconds to a device change. Wall time is the one signal a missing frame cannot forge, which is
/// exactly why the window it divides by has to be the one that really happened.
@Suite("Capture completeness")
struct CaptureCompletenessTests {

    @Test("A full window of audio scores 1")
    func fullWindow() {
        let ratio = CaptureCompleteness.ratio(frames: 144_000, sampleRate: 48_000, windowSeconds: 3)
        #expect(abs(ratio - 1.0) < 0.001)
        #expect(CaptureCompleteness.isComplete(ratio))
    }

    /// The failure this exists to catch: capture stopped early while every other signal stayed clean.
    @Test("Losing two thirds of the audio is incomplete")
    func truncated() {
        let ratio = CaptureCompleteness.ratio(frames: 48_000, sampleRate: 48_000, windowSeconds: 3)
        #expect(abs(ratio - 0.333) < 0.001)
        #expect(CaptureCompleteness.isComplete(ratio) == false)
    }

    /// THE #124 case. `RunLoop.main.run(until:)` is not bounded to its date: measured, a 6-second
    /// block on the main loop stretched a 3-second request to 6.219s and inflated the old ratio to
    /// 2.073. Dividing by the window that actually happened keeps it at 1.
    @Test("A stretched window does not inflate the ratio")
    func stretchedWindow() {
        // 6.2s of audio arrived because the window really was 6.2s long.
        let honest = CaptureCompleteness.ratio(frames: 297_600, sampleRate: 48_000,
                                               windowSeconds: 6.2)
        #expect(abs(honest - 1.0) < 0.01)

        // The same run measured against the REQUESTED 3s - what the probe used to do.
        let inflated = CaptureCompleteness.ratio(frames: 297_600, sampleRate: 48_000,
                                                 windowSeconds: 3)
        #expect(inflated > 2.0, "the old denominator is what made truncation hideable")
    }

    /// Truncation inside a stretched window is still caught. This is the case the old maths could
    /// swallow: half the audio lost, and the ratio still cleared 0.85 because the window was long.
    @Test("Truncation is caught even when the window ran long")
    func truncationInsideAStretchedWindow() {
        // 6.2s window, only 3.1s of audio - half of it lost.
        let ratio = CaptureCompleteness.ratio(frames: 148_800, sampleRate: 48_000,
                                              windowSeconds: 6.2)
        #expect(abs(ratio - 0.5) < 0.01)
        #expect(CaptureCompleteness.isComplete(ratio) == false)

        // Against the requested 3s it would have scored above 1 and passed.
        #expect(CaptureCompleteness.isComplete(
            CaptureCompleteness.ratio(frames: 148_800, sampleRate: 48_000, windowSeconds: 3)))
    }

    /// A zero or negative window is not a measurement. Scoring it 0 fails closed, which for a
    /// truncation guard is the only safe direction.
    @Test("An unmeasurable window fails closed")
    func unmeasurableWindow() {
        #expect(CaptureCompleteness.ratio(frames: 144_000, sampleRate: 48_000, windowSeconds: 0) == 0)
        #expect(CaptureCompleteness.ratio(frames: 144_000, sampleRate: 0, windowSeconds: 3) == 0)
        #expect(CaptureCompleteness.isComplete(0) == false)
    }

    /// 15% covers ordinary start-up latency and the final partial drain. The failure it has to
    /// separate lost 66%, so the threshold is nowhere near the signal.
    @Test("The threshold sits where the docs say it does")
    func threshold() {
        #expect(CaptureCompleteness.isComplete(0.85))
        #expect(CaptureCompleteness.isComplete(0.849) == false)
    }
}
