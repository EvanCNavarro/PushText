import Testing
import Foundation
@testable import PushTextCore

/// Drives the HUD's waveform from REAL captured audio (#46).
///
/// The alternative - animating a decorative waveform - would show movement while a dead capture
/// path delivers nothing, which is exactly the failure `AudioProbe` exists to catch and exactly the
/// failure that cost hours today. If the meter reads zero, the user should see stillness, because
/// stillness is the truth.
@Suite("AudioLevelMeter")
struct AudioLevelMeterTests {

    private static func sine(amplitude: Float, count: Int = 4_800) -> [Float] {
        (0..<count).map { amplitude * sinf(2 * .pi * 440 * Float($0) / 48_000) }
    }

    @Test("Silence reads zero")
    func silenceIsZero() {
        var meter = AudioLevelMeter(smoothing: 0)
        #expect(meter.level(for: Array(repeating: 0, count: 1_024)) == 0)
    }

    @Test("An empty buffer reads zero rather than crashing or holding the last value")
    func emptyIsZero() {
        var meter = AudioLevelMeter(smoothing: 0)
        _ = meter.level(for: Self.sine(amplitude: 1.0))
        #expect(meter.level(for: []) == 0)
    }

    @Test("A full-scale signal reads at or near the top")
    func fullScaleIsHigh() {
        var meter = AudioLevelMeter(smoothing: 0)
        let level = meter.level(for: Self.sine(amplitude: 1.0))
        #expect(level > 0.85, "full scale read \(String(format: "%.3f", level))")
        #expect(level <= 1.0)
    }

    /// The property that makes the display meaningful rather than decorative: it has to MOVE with
    /// the audio. A meter that returns a constant would pass "silence is zero" if the constant were
    /// zero, and "full scale is high" if it were one, but never both.
    @Test("Louder audio reads higher than quieter audio")
    func monotonicInAmplitude() {
        var meter = AudioLevelMeter(smoothing: 0)
        let quiet = meter.level(for: Self.sine(amplitude: 0.05))
        let mid = meter.level(for: Self.sine(amplitude: 0.3))
        let loud = meter.level(for: Self.sine(amplitude: 1.0))

        #expect(quiet < mid, "quiet \(String(format: "%.3f", quiet)) !< mid \(String(format: "%.3f", mid))")
        #expect(mid < loud, "mid \(String(format: "%.3f", mid)) !< loud \(String(format: "%.3f", loud))")
    }

    @Test("Levels stay within 0...1 for any input, including clipping")
    func clampedRange() {
        var meter = AudioLevelMeter(smoothing: 0)
        for amplitude in [Float(0), 0.001, 0.5, 1.0, 4.0] {
            let level = meter.level(for: Self.sine(amplitude: amplitude))
            #expect(level >= 0 && level <= 1, "amplitude \(amplitude) produced \(level)")
        }
    }

    /// Without smoothing the waveform strobes: speech is full of short gaps between syllables, and
    /// an unsmoothed meter drops to zero in each one.
    @Test("Smoothing damps an abrupt drop instead of snapping to zero")
    func smoothingDampsDrops() {
        var meter = AudioLevelMeter(smoothing: 0.5)
        _ = meter.level(for: Self.sine(amplitude: 1.0))

        let afterSilence = meter.level(for: Array(repeating: 0, count: 1_024))

        #expect(afterSilence > 0, "a smoothed meter must not snap straight to zero")
        #expect(afterSilence < 0.85, "and it must still fall")
    }

    /// Smoothing must not become a memory leak: sustained silence has to reach zero eventually, or
    /// the HUD shows a permanent twitch after the user stops speaking.
    @Test("Sustained silence decays to zero")
    func silenceEventuallyReachesZero() {
        var meter = AudioLevelMeter(smoothing: 0.5)
        _ = meter.level(for: Self.sine(amplitude: 1.0))

        var level = 1.0
        for _ in 0..<200 {
            level = meter.level(for: Array(repeating: 0, count: 512))
        }

        #expect(level < 0.01, "still \(String(format: "%.4f", level)) after 200 silent buffers")
    }
}
