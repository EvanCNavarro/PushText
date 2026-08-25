import Foundation

/// The start and stop cues, as generated audio rather than shipped files (#172).
///
/// **Why generated.** Wispr Flow's `dictation-start.wav` and `dictation-stop.wav` are its
/// proprietary assets, and PushText is a public repository - copying them in would be redistributing
/// another company's audio. They were MEASURED instead, and matched:
///
/// | | Wispr Flow | here |
/// |---|---|---|
/// | start | 180 ms, dominant ~448 Hz decaying toward ~300 Hz | 175 ms at 440 Hz |
/// | stop | 219 ms, dominant ~323 Hz | 210 ms at 300 Hz |
/// | envelope | peaks in the first fifth, then decays away | exponential decay, same shape |
///
/// The direction is the part that carries meaning - up for "listening", down for "done" - and it is
/// what a user would notice instantly if it were reversed.
///
/// Pure, and in Core, because sample generation is arithmetic and belongs where it can be tested
/// without an audio device (ADR-0001).
public struct DictationTone: Hashable, Sendable {

    public let frequency: Double
    public let duration: TimeInterval
    /// Higher decays faster. Tuned so the tail is inaudible well before the end, which is what stops
    /// the cue clicking when playback finishes.
    public let decay: Double
    /// Peak level, well below full scale: this plays over whatever the user is listening to, and a
    /// cue that ducks their music is a cue they disable.
    public let amplitude: Double

    public init(frequency: Double, duration: TimeInterval, decay: Double, amplitude: Double) {
        self.frequency = frequency
        self.duration = duration
        self.decay = decay
        self.amplitude = amplitude
    }

    /// Rising cue: dictation is listening.
    public static let start = DictationTone(frequency: 440, duration: 0.175,
                                            decay: 26, amplitude: 0.28)

    /// Lower cue: dictation is done. A fifth or so below `start`, which is enough to be heard as
    /// "down" without sounding like a different instrument.
    public static let stop = DictationTone(frequency: 300, duration: 0.210,
                                           decay: 22, amplitude: 0.28)

    /// 16-bit mono PCM.
    ///
    /// The window matters as much as the tone. A raw decaying sine still begins at a non-zero
    /// gradient, and a waveform that starts or ends on a step produces a CLICK - the single most
    /// audible way to get a short cue wrong, and one no length assertion can see. A short raised
    /// cosine fade-in, plus a decay steep enough that the tail is silent, removes both ends.
    public func samples(sampleRate: Double) -> [Int16] {
        let count = Int(duration * sampleRate)
        guard count > 0 else { return [] }
        let fadeIn = max(1, Int(0.004 * sampleRate))
        return (0..<count).map { index in
            let time = Double(index) / sampleRate
            let envelope = exp(-decay * time)
            // Raised cosine, so the first sample is exactly zero and the slope is too.
            let attack = index < fadeIn
                ? 0.5 * (1 - cos(.pi * Double(index) / Double(fadeIn)))
                : 1
            let value = sin(2 * .pi * frequency * time) * envelope * attack * amplitude
            return Int16(max(-1, min(1, value)) * Double(Int16.max))
        }
    }
}
