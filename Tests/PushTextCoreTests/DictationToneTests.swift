import Testing
import Foundation
@testable import PushTextCore

/// The start/stop cues (#172).
///
/// Rendered rather than shipped as files. Wispr Flow's own `dictation-start.wav` and
/// `dictation-stop.wav` are its proprietary assets and PushText is a public repository, so they are
/// MEASURED and matched, never copied.
@Suite("Dictation tones")
struct DictationToneTests {

    private let rate = 44_100.0

    @Test("A tone is as long as it says it is")
    func durationIsHonoured() {
        let samples = DictationTone.start.samples(sampleRate: rate)
        let expected = Int(DictationTone.start.duration * rate)
        #expect(samples.count == expected)
    }

    /// Measured off Wispr Flow: start peaks near 448 Hz, stop near 300 Hz. The DIRECTION is the part
    /// that carries meaning - up for "listening", down for "done" - and it is the one thing a user
    /// would notice immediately if it were reversed.
    @Test("Start is pitched above stop")
    func startIsHigherThanStop() {
        #expect(DictationTone.start.frequency > DictationTone.stop.frequency)
    }

    /// Both cues are short. A dictation utility that plays a jingle every time you speak is one you
    /// turn off within a day - and the measured originals are 180 ms and 219 ms.
    @Test("Both cues are brief")
    func cuesAreShort() {
        for tone in [DictationTone.start, DictationTone.stop] {
            #expect(tone.duration <= 0.30, "a cue longer than the pause before speaking")
            #expect(tone.duration >= 0.05, "too short to be heard as a tone")
        }
    }

    /// A cue that starts or ends abruptly CLICKS, and it is the single most audible way to get a
    /// short sound wrong.
    ///
    /// The assertion is on the SLOPE, not the first sample, and that distinction was found by
    /// planting. A sine at phase zero begins at value zero whether or not it is faded in, so a test
    /// checking `samples.first == 0` passes with the fade-in deleted - it was green against the
    /// exact defect it was written for. What a bare sine onset actually has is MAXIMUM slope at
    /// t=0, and the step between consecutive samples is what the speaker reproduces as a click.
    @Test("A tone starts and ends at silence, so it cannot click")
    func noClickAtEitherEnd() {
        for tone in [DictationTone.start, DictationTone.stop] {
            let samples = tone.samples(sampleRate: rate)
            #expect(abs(samples.first ?? 1) <= 2, "non-zero first sample clicks on play")

            let onset = samples.prefix(32)
            let steepest = zip(onset, onset.dropFirst())
                .map { abs(Int($1) - Int($0)) }
                .max() ?? Int.max
            #expect(steepest < 200, "the onset steps by \(steepest) - that is an audible click")

            let tail = samples.suffix(64).map { abs($0) }.max() ?? 1
            #expect(tail <= Int16.max / 100, "the tail is still loud - it will click on stop")
        }
    }

    @Test("The tone actually reaches an audible level")
    func toneIsAudible() {
        let peak = DictationTone.start.samples(sampleRate: rate).map { abs($0) }.max() ?? 0
        #expect(peak > Int16.max / 10, "so quiet it may as well be silence")
        #expect(peak <= Int16.max, "clipped")
    }

    /// Energy front-loaded, like the originals: their envelopes peak in the first fifth and decay
    /// away, which is what makes them read as a soft blip rather than a beep.
    @Test("The cue decays instead of holding")
    func decaysRatherThanHolds() {
        let samples = DictationTone.start.samples(sampleRate: rate)
        let third = samples.count / 3
        let early = samples.prefix(third).map { abs(Int($0)) }.reduce(0, +) / max(1, third)
        let late = samples.suffix(third).map { abs(Int($0)) }.reduce(0, +) / max(1, third)
        #expect(early > late * 3, "a cue that does not decay is a beep")
    }
}
