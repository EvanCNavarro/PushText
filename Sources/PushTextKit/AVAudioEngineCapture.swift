import Foundation
import AVFoundation
import PushTextCore

/// Microphone capture built on `AVAudioSinkNode`.
///
/// **Why the sink node and not `installTapOnBus:`.** The tap's own SDK header says of its
/// `bufferSize` parameter: *"Supported range is [100, 400] ms."* That is a floor on delivery
/// granularity — the earliest a tap can hand over audio is 100 ms after it starts arriving, which is
/// pure added latency in a push-to-talk loop where the user is waiting to see text. The sink node
/// delivers whatever the hardware produces, typically far smaller.
///
/// **The realtime-thread contract.** `AVAudioSinkNode.h`: the receiver block *"will be called on the
/// realtime thread and it is the client's responsibility to handle it in a thread-safe manner and to
/// not make any blocking calls."* Allocation and locking are both blocking calls, so the block does
/// neither: it copies into a preallocated `AudioRingBuffer` and returns. A separate drain timer does
/// the allocating and hands finished buffers to the caller.
///
/// **No format conversion.** Same header: the sink node *"does not support format conversion"*, so
/// the connection format must be the input node's output format — the hardware rate. Whatever the
/// microphone runs at is what the transcriber gets; resampling, if it is ever needed, belongs
/// downstream and is not smuggled in here.
///
/// **The engine is not kept warm.** `AVAudioEngine.h` ties the microphone indicator to the engine
/// running, so a warm engine lights the orange dot permanently. For a dictation app that is a
/// privacy claim we would be making falsely, so the engine starts on key-down and stops on key-up.
public final class AVAudioEngineCapture: AudioCapture, @unchecked Sendable {

    public enum CaptureError: Error, Equatable {
        /// The user has denied microphone access, or it has never been requested.
        case microphoneNotAuthorized
        /// The input device reported a format we cannot use (no channels, or a zero sample rate).
        case unusableInputFormat(sampleRate: Double, channels: UInt32)
        case engineStartFailed(String)
    }

    private let engine = AVAudioEngine()
    private let ring: AudioRingBuffer
    private let drainQueue = DispatchQueue(label: "dev.ecn.apps.pushtext.audio-drain")
    private let emitInterval: TimeInterval

    private var sinkNode: AVAudioSinkNode?
    private var drainTimer: DispatchSourceTimer?
    private var handler: (@Sendable (AudioBuffer) -> Void)?
    private var sampleRate: Double = 0
    /// Frames emitted so far. The only source of `AudioBuffer.startTime`, which makes timestamps
    /// monotonic BY CONSTRUCTION rather than by hoping the host clock behaves — non-monotonic
    /// `bufferStartTime` is one of the three suspected causes of FB22149971 (docs/research/01).
    private var emittedFrames: Int = 0

    /// - Parameters:
    ///   - ringCapacityFrames: default holds ~2s at 48 kHz, so a stalled drain loses nothing.
    ///   - emitInterval: how often buffers are handed to the caller.
    public init(ringCapacityFrames: Int = 96_000, emitInterval: TimeInterval = 0.05) {
        ring = AudioRingBuffer(capacityFrames: ringCapacityFrames)
        self.emitInterval = emitInterval
    }

    /// Frames the audio thread had to discard because the drain fell behind. Non-zero means audio
    /// was lost, which for dictation means words were lost — surfaced rather than swallowed.
    public var droppedFrames: Int { ring.droppedFrames }

    /// Microphone authorisation, checked without prompting.
    public static var isMicrophoneAuthorized: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    /// Prompts for microphone access if it has never been asked. Shows a system dialog.
    public static func requestMicrophoneAccess() async -> Bool {
        if isMicrophoneAuthorized { return true }
        return await AVCaptureDevice.requestAccess(for: .audio)
    }

    public func start(onBuffer: @escaping @Sendable (AudioBuffer) -> Void) throws {
        guard Self.isMicrophoneAuthorized else { throw CaptureError.microphoneNotAuthorized }

        handler = onBuffer
        ring.reset()
        emittedFrames = 0

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw CaptureError.unusableInputFormat(sampleRate: format.sampleRate,
                                                   channels: format.channelCount)
        }
        sampleRate = format.sampleRate
        let channels = Int(format.channelCount)
        let ring = self.ring

        // REALTIME THREAD. No allocation, no locks, no Swift runtime calls that could take one.
        let sink = AVAudioSinkNode { _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(
                UnsafeMutablePointer(mutating: audioBufferList))
            guard let first = buffers.first,
                  let raw = first.mData else { return noErr }
            let samples = raw.assumingMemoryBound(to: Float.self)

            if channels == 1 || buffers.count > 1 {
                // Mono, or non-interleaved multi-channel: buffer 0 IS channel 0.
                let wanted = Int(frameCount)
                let accepted = ring.write(samples, count: wanted)
                // The audio thread cannot retry - whatever the ring refused is gone. Reporting it
                // here rather than inferring it inside the ring is the point: only this caller knows.
                ring.recordDropped(wanted - accepted)
            } else {
                // Interleaved stereo in a single buffer - take channel 0 only. Done sample by
                // sample deliberately: a stride-copy helper would allocate.
                var accepted = 0
                for frame in 0..<Int(frameCount) {
                    var value = samples[frame * channels]
                    accepted += ring.write(&value, count: 1)
                }
                ring.recordDropped(Int(frameCount) - accepted)
            }
            return noErr
        }

        engine.attach(sink)
        engine.connect(input, to: sink, format: format)
        sinkNode = sink

        engine.prepare()
        do {
            try engine.start()
        } catch {
            teardown()
            throw CaptureError.engineStartFailed(error.localizedDescription)
        }

        startDrain()
    }

    public func stop() {
        drainTimer?.cancel()
        drainTimer = nil
        if engine.isRunning { engine.stop() }
        drainQueue.sync { self.flush() }
        teardown()
        handler = nil
    }

    private func teardown() {
        if let sinkNode {
            engine.disconnectNodeInput(sinkNode)
            engine.detach(sinkNode)
        }
        sinkNode = nil
    }

    private func startDrain() {
        let timer = DispatchSource.makeTimerSource(queue: drainQueue)
        timer.schedule(deadline: .now() + emitInterval, repeating: emitInterval)
        timer.setEventHandler { [weak self] in self?.flush() }
        drainTimer = timer
        timer.resume()
    }

    /// Consumer side: allocates, so it never runs on the audio thread.
    private func flush() {
        let samples = ring.drain()
        guard !samples.isEmpty, let handler, sampleRate > 0 else { return }
        let startTime = Double(emittedFrames) / sampleRate
        emittedFrames += samples.count
        handler(AudioBuffer(samples: samples, sampleRate: sampleRate, startTime: startTime))
    }
}
