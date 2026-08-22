import Testing
import Foundation
import AVFoundation
@testable import PushTextKit
import PushTextCore

/// The conversion boundary that #32 exists for.
///
/// `AVAudioEngineCapture` emits mono Float32 at the hardware rate (48 kHz here); `SpeechAnalyzer`
/// asked for 16 kHz mono **Int16**. Handing it anything else is not an error - it is a SIGTRAP
/// inside `Speech.SpeechRecognizerWorker.preRunRecognition()`, which no `catch` can intercept
/// (TRAP-20, docs/verification/task11-streaming-spike.md). So the correctness of this type cannot
/// be asserted by "the analyzer did not crash" from inside the process; it has to be asserted here,
/// on the buffer, before it ever reaches Speech.
@Suite("AudioFormatConverter")
struct AudioFormatConverterTests {

    private static func target(
        sampleRate: Double = 16_000,
        format: AVAudioCommonFormat = .pcmFormatInt16
    ) -> AVAudioFormat {
        AVAudioFormat(commonFormat: format, sampleRate: sampleRate, channels: 1, interleaved: false)!
    }

    /// A 440 Hz tone, so the output can be checked for CONTENT and not merely for shape.
    private static func tone(
        sampleRate: Double,
        seconds: Double,
        amplitude: Float = 0.5
    ) -> PushTextKit.AudioBuffer {
        let count = Int(sampleRate * seconds)
        let samples = (0..<count).map { index in
            amplitude * sinf(2 * .pi * 440 * Float(index) / Float(sampleRate))
        }
        return PushTextKit.AudioBuffer(samples: samples, sampleRate: sampleRate, startTime: 0)
    }

    @Test("Converts 48 kHz Float32 capture into the analyzer's 16 kHz Int16 format")
    func convertsRateAndSampleFormat() throws {
        let converter = AudioFormatConverter(target: Self.target())
        let input = Self.tone(sampleRate: 48_000, seconds: 0.5)

        let output = try converter.convert(input)

        #expect(output.format.sampleRate == 16_000)
        #expect(output.format.commonFormat == AVAudioCommonFormat.pcmFormatInt16)
        #expect(output.format.channelCount == 1)
    }

    /// Without this, every assertion above still holds on a converter that emits SILENCE - the
    /// format would be right and the audio gone, which is indistinguishable from a working
    /// converter until a user dictates into it and gets an empty transcript.
    @Test("Carries the signal across, so a silent converter is distinguishable from a working one")
    func preservesSignal() throws {
        let converter = AudioFormatConverter(target: Self.target())
        let input = Self.tone(sampleRate: 48_000, seconds: 0.5, amplitude: 0.5)

        let output = try converter.convert(input)

        guard let channel = output.int16ChannelData else {
            Issue.record("expected Int16 channel data")
            return
        }
        var peak: Int16 = 0
        for index in 0..<Int(output.frameLength) {
            peak = max(peak, abs(channel[0][index]))
        }
        // 0.5 full-scale is ~16384 in Int16. Generous bounds: this asserts "the audio survived",
        // not "the resampler is bit-exact".
        #expect(peak > 8_000, "peak was \(String(peak)) - a silent or near-silent conversion")
        #expect(peak <= Int16.max)
    }

    @Test("Frame count follows the sample-rate ratio")
    func frameCountFollowsRatio() throws {
        let converter = AudioFormatConverter(target: Self.target())
        let input = Self.tone(sampleRate: 48_000, seconds: 0.5)

        let output = try converter.convert(input)

        // 24,000 input frames at 48k -> ~8,000 at 16k. Resamplers carry a few frames of filter
        // delay, so this is a tolerance, not an equality.
        #expect(abs(Int(output.frameLength) - 8_000) < 200,
                "expected ~8000 frames, got \(String(output.frameLength))")
    }

    /// The dangerous case is not a rate MISMATCH, it is a rate MATCH with a format mismatch: it
    /// looks like nothing needs doing, and Float32 into an Int16 analyzer traps just the same.
    @Test("A same-rate buffer is still converted to the target sample format")
    func sameRateStillConvertsSampleFormat() throws {
        let converter = AudioFormatConverter(target: Self.target())
        let input = Self.tone(sampleRate: 16_000, seconds: 0.25)

        let output = try converter.convert(input)

        #expect(output.format.sampleRate == 16_000)
        #expect(output.format.commonFormat == AVAudioCommonFormat.pcmFormatInt16)
        #expect(output.frameLength > 0)
    }

    @Test("Repeated calls reuse one converter and keep producing the target format")
    func repeatedCallsStayCorrect() throws {
        let converter = AudioFormatConverter(target: Self.target())

        for _ in 0..<5 {
            let output = try converter.convert(Self.tone(sampleRate: 48_000, seconds: 0.1))
            #expect(output.format.commonFormat == AVAudioCommonFormat.pcmFormatInt16)
            #expect(output.frameLength > 0)
        }
    }

    @Test("An empty buffer throws rather than producing a zero-frame buffer for the analyzer")
    func emptyBufferThrows() {
        let converter = AudioFormatConverter(target: Self.target())
        let empty = PushTextKit.AudioBuffer(samples: [], sampleRate: 48_000, startTime: 0)

        #expect(throws: AudioFormatConverter.ConversionError.emptyBuffer) {
            _ = try converter.convert(empty)
        }
    }

    @Test("A nonsensical source sample rate throws instead of building an invalid format")
    func invalidSourceRateThrows() {
        let converter = AudioFormatConverter(target: Self.target())
        let bad = PushTextKit.AudioBuffer(samples: [0.1, 0.2], sampleRate: 0, startTime: 0)

        #expect(throws: AudioFormatConverter.ConversionError.self) {
            _ = try converter.convert(bad)
        }
    }
}
