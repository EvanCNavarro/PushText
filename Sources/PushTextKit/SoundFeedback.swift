import AppKit
import Foundation
import PushTextCore

/// Plays the start/stop cues (#172).
///
/// A protocol so `AppModel` never touches the audio system directly, matching every other system
/// capability in this target (ADR-0001).
public protocol DictationSoundPlaying: Sendable {
    func play(_ tone: DictationTone)
}

/// Renders `DictationTone` to PCM once and plays it with `NSSound`.
///
/// `NSSound` rather than `AVAudioEngine`: these are two fixed cues a couple of hundred milliseconds
/// long, and standing an audio engine up for that would add a graph to start, stop and keep alive
/// for no benefit. It also plays on the system's own output without touching the capture session -
/// which matters, because this app is recording from the microphone at the moment it plays one.
public final class SoundFeedback: DictationSoundPlaying, @unchecked Sendable {

    private let sampleRate: Double
    private let lock = NSLock()
    /// Built once per tone and reused. Re-rendering a WAV on every keypress would put avoidable
    /// work on the latency-sensitive path the whole app is built around.
    private var cache: [DictationTone: NSSound] = [:]

    public init(sampleRate: Double = 44_100) {
        self.sampleRate = sampleRate
    }

    public func play(_ tone: DictationTone) {
        guard let sound = sound(for: tone) else { return }
        // Rewind: NSSound will not restart a sound that is still playing, and double-pressing to
        // latch produces two cues in quick succession.
        sound.stop()
        sound.play()
    }

    private func sound(for tone: DictationTone) -> NSSound? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[tone] { return cached }
        guard let sound = NSSound(data: Self.wav(tone.samples(sampleRate: sampleRate),
                                                 sampleRate: sampleRate)) else { return nil }
        cache[tone] = sound
        return sound
    }

    /// A 16-bit mono WAV container. `NSSound` needs a file format, not bare samples.
    public static func wav(_ samples: [Int16], sampleRate: Double) -> Data {
        let bytesPerSample = 2
        let dataBytes = samples.count * bytesPerSample
        var data = Data()

        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }

        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + dataBytes))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        append(UInt32(16))                              // PCM header length
        append(UInt16(1))                               // PCM, uncompressed
        append(UInt16(1))                               // mono
        append(UInt32(sampleRate))
        append(UInt32(sampleRate) * UInt32(bytesPerSample))
        append(UInt16(bytesPerSample))
        append(UInt16(16))                              // bits per sample
        data.append(contentsOf: Array("data".utf8))
        append(UInt32(dataBytes))
        for sample in samples { append(sample) }
        return data
    }
}
