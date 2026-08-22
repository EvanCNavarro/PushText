import Foundation
import AVFoundation
import PushTextCore

/// Converts captured audio into the exact format the transcription engine asked for.
///
/// **Why this type exists at all, rather than a line inside the engine.** `SpeechAnalyzer` does not
/// reject a wrong format - it traps. Feeding `AnalyzerInput` buffers whose format differs from the
/// analyzer's chosen format kills the process with `SIGTRAP` inside
/// `Speech.SpeechRecognizerWorker.preRunRecognition()`; there is nothing to `catch`, so the app
/// dies mid-dictation. Measured by planting exactly that during the #11 spike
/// (docs/verification/task11-streaming-spike.md, TRAP-20, #32). A crash cannot be asserted on from
/// inside the process, so the invariant has to be enforced and tested HERE, on the buffer, before
/// it ever reaches Speech.
///
/// **The gap is wider than a resample.** `AVAudioEngineCapture` emits mono **Float32 at the
/// hardware rate** (48 kHz on this machine) and deliberately does no conversion of its own - its
/// header says resampling "belongs downstream and is not smuggled in here", because
/// `AVAudioSinkNode` cannot convert. `SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith:)`
/// returned 16 kHz mono **Int16** (`commonFormat` 3, per `AVAudioFormat.h`). Both the rate and the
/// sample format differ, so a rate-only fix would still trap.
///
/// Not an actor: it is cheap, synchronous, and owned by the engine actor that calls it.
public final class AudioFormatConverter {

    public enum ConversionError: Error, Equatable {
        case emptyBuffer
        case invalidSourceFormat(sampleRate: Double)
        case converterUnavailable
        case allocationFailed
        case conversionFailed(String)
    }

    private let target: AVAudioFormat

    /// One converter per source format, reused across calls. Reuse is not only an allocation
    /// saving: `AVAudioConverter` carries resampler filter state, and rebuilding it per buffer
    /// would discard that state at every chunk boundary of a continuous utterance.
    private var converter: AVAudioConverter?
    private var converterSourceRate: Double = 0

    public init(target: AVAudioFormat) {
        self.target = target
    }

    /// The format every returned buffer is in. Callers assert against this rather than assuming.
    public var targetFormat: AVAudioFormat { target }

    public func convert(_ buffer: PushTextKit.AudioBuffer) throws -> AVAudioPCMBuffer {
        guard !buffer.samples.isEmpty else { throw ConversionError.emptyBuffer }
        guard buffer.sampleRate > 0, buffer.sampleRate.isFinite else {
            throw ConversionError.invalidSourceFormat(sampleRate: buffer.sampleRate)
        }

        guard let source = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: buffer.sampleRate,
                                         channels: 1,
                                         interleaved: false) else {
            throw ConversionError.invalidSourceFormat(sampleRate: buffer.sampleRate)
        }

        let converter = try converter(for: source)
        let input = try inputBuffer(from: buffer, format: source)

        // Ceil, plus a frame of slack: a resampler's output length for a given input is not exactly
        // frames * ratio, and an undersized buffer silently truncates audio.
        let ratio = target.sampleRate / source.sampleRate
        let capacity = AVAudioFrameCount((Double(input.frameLength) * ratio).rounded(.up)) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else {
            throw ConversionError.allocationFailed
        }

        var supplied = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            if supplied {
                // NOT .endOfStream: this converter is reused across the chunks of one continuous
                // utterance, and ending the stream would discard its filter state at every chunk.
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return input
        }

        if let conversionError {
            throw ConversionError.conversionFailed(conversionError.localizedDescription)
        }
        // .inputRanDry is the expected terminal status here - it means the converter consumed
        // everything we supplied. Only .error is a failure.
        if status == .error {
            throw ConversionError.conversionFailed("converter returned .error")
        }

        return output
    }

    private func converter(for source: AVAudioFormat) throws -> AVAudioConverter {
        if let converter, converterSourceRate == source.sampleRate {
            return converter
        }
        guard let fresh = AVAudioConverter(from: source, to: target) else {
            throw ConversionError.converterUnavailable
        }
        converter = fresh
        converterSourceRate = source.sampleRate
        return fresh
    }

    private func inputBuffer(
        from buffer: PushTextKit.AudioBuffer,
        format: AVAudioFormat
    ) throws -> AVAudioPCMBuffer {
        guard let input = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(buffer.samples.count)
        ), let channel = input.floatChannelData else {
            throw ConversionError.allocationFailed
        }
        input.frameLength = AVAudioFrameCount(buffer.samples.count)
        buffer.samples.withUnsafeBufferPointer { source in
            guard let base = source.baseAddress else { return }
            channel[0].update(from: base, count: buffer.samples.count)
        }
        return input
    }
}
