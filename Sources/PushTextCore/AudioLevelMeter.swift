import Foundation

/// Turns captured samples into a 0...1 level for the HUD's waveform (#46).
///
/// **Why the waveform is metered rather than animated.** A decorative animation would show movement
/// while a dead capture path delivers nothing - the exact failure `AudioProbe` exists to catch, and
/// the exact failure that made "is it even recording?" unanswerable. If the meter reads zero the
/// user sees stillness, because stillness is then the truth.
///
/// Pure, and in Core, so the mapping is testable without a microphone or a screen.
public struct AudioLevelMeter: Sendable {

    /// How much of the previous reading carries into the next, 0...0.99.
    ///
    /// Speech is full of short gaps between syllables, and an unsmoothed meter drops to zero in
    /// every one of them, which strobes. Smoothing damps that without hiding real silence: the
    /// carry-over is exponential, so sustained silence still decays to zero rather than leaving a
    /// permanent twitch after the user stops speaking.
    public let smoothing: Double

    /// Quietest level shown as movement. Below this the meter reads zero.
    ///
    /// -60 dBFS rather than the -96 dB floor of 16-bit audio: room tone sits near the bottom of
    /// that range, and a meter that renders it would never be still in a real room.
    private let floorDecibels: Double = -60

    private var previous: Double = 0

    public init(smoothing: Double = 0.3) {
        self.smoothing = min(max(smoothing, 0), 0.99)
    }

    /// The level for one buffer, 0...1.
    public mutating func level(for samples: [Float]) -> Double {
        guard !samples.isEmpty else {
            // No audio at all is not "quiet", it is nothing - reset rather than decay, so a stalled
            // capture path reads as still immediately instead of fading out like real silence.
            previous = 0
            return 0
        }

        var sumOfSquares = 0.0
        for sample in samples {
            let value = Double(sample)
            sumOfSquares += value * value
        }
        let rms = (sumOfSquares / Double(samples.count)).squareRoot()

        let raw: Double
        if rms <= 0 {
            raw = 0
        } else {
            // dBFS, then mapped onto the visible range. log10(0) is -inf, hence the guard above.
            let decibels = 20 * log10(rms)
            raw = clamped((decibels - floorDecibels) / -floorDecibels)
        }

        previous = smoothing * previous + (1 - smoothing) * raw
        return clamped(previous)
    }

    private func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
