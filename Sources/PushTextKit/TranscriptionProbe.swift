import Foundation
import AVFoundation
import PushTextCore

/// Headless proof that `AppleSpeechEngine` actually transcribes on this machine.
///
/// A green `AudioFormatConverter` suite proves the conversion arithmetic and nothing about whether
/// `SpeechAnalyzer` accepts the result. That depends on the on-device model being installed, on the
/// streaming entry point working on this OS build, and on the converted format being exactly what
/// the analyzer asked for - and the last one cannot be asserted from inside the process at all,
/// because a mismatch is a `SIGTRAP` rather than an error (#32, TRAP-20). Here it is observable:
/// a mismatch kills this probe and the exit code says so.
///
/// Activated by `PUSHTEXT_TRANSCRIBE_PROBE=1`.
/// - `PUSHTEXT_TRANSCRIBE_PROBE_FILE=<path>` transcribes a WAV instead of the microphone, which
///   makes the probe deterministic and runnable with nobody present.
/// - `PUSHTEXT_TRANSCRIBE_PROBE_SECONDS` bounds microphone capture (default 5).
/// - `PUSHTEXT_TRANSCRIBE_PROBE_REALTIME=1` paces file appends at wall-clock speed. Without it the
///   whole file is pushed at once, which is NOT what production does - live capture delivers a
///   buffer every 50 ms - so the paced run is the one that exercises the analyzer's real timing.
///
/// Exits non-zero when the engine could not produce a transcript, so it is usable as a gate.
public enum TranscriptionProbe {
    public static var isRequested: Bool {
        ProcessInfo.processInfo.environment["PUSHTEXT_TRANSCRIBE_PROBE"] == "1"
    }

    public static func runAndExit() -> Never {
        guard #available(macOS 26, *) else {
            print("TRANSCRIBE_PROBE engine=skipped reason=requires-macos-26")
            fflush(stdout)
            exit(2)
        }

        let env = ProcessInfo.processInfo.environment
        let semaphore = DispatchSemaphore(value: 0)
        let code = Box<Int32>(1)

        Task {
            code.value = await run(env: env)
            semaphore.signal()
        }
        semaphore.wait()
        exit(code.value)
    }

    @available(macOS 26, *)
    private static func run(env: [String: String]) async -> Int32 {
        let engine = AppleSpeechEngine()

        let available = await engine.isAvailable
        print("TRANSCRIBE_PROBE isAvailable=\(available)")
        fflush(stdout)
        guard available else {
            print("TRANSCRIBE_PROBE engine=skipped reason=transcriber-unavailable")
            return 2
        }

        let buffers: [PushTextKit.AudioBuffer]
        let source: String
        do {
            (buffers, source) = try await acquireAudio(env: env)
        } catch {
            print("TRANSCRIBE_PROBE audio=failed error=\(error)")
            return 3
        }

        let frames = buffers.reduce(0) { $0 + $1.samples.count }
        let rate = buffers.first?.sampleRate ?? 0
        let paced = env["PUSHTEXT_TRANSCRIBE_PROBE_REALTIME"] == "1"
        print("TRANSCRIBE_PROBE source=\(source) buffers=\(buffers.count) frames=\(frames) "
              + "rate=\(rate) realtime=\(paced)")
        fflush(stdout)
        guard !buffers.isEmpty else {
            print("TRANSCRIBE_PROBE engine=failed reason=no-audio")
            return 3
        }

        return await transcribe(engine: engine,
                                buffers: buffers,
                                realtime: env["PUSHTEXT_TRANSCRIBE_PROBE_REALTIME"] == "1")
    }

    @available(macOS 26, *)
    private static func transcribe(
        engine: AppleSpeechEngine,
        buffers: [PushTextKit.AudioBuffer],
        realtime: Bool
    ) async -> Int32 {
        do {
            try await engine.beginUtterance()
            for buffer in buffers {
                try await engine.append(buffer)
                if realtime, buffer.sampleRate > 0 {
                    try await Task.sleep(for: .seconds(Double(buffer.samples.count) / buffer.sampleRate))
                }
            }
            let delivered = await engine.deliveredSeconds
            let transcript = try await engine.finishUtterance()

            print("TRANSCRIBE_PROBE delivered=\(String(format: "%.2f", delivered))s "
                  + "duration=\(String(format: "%.2f", transcript.duration))s")
            print("TRANSCRIBE_PROBE text=\"\(transcript.text)\"")
            fflush(stdout)

            guard !transcript.text.isEmpty else {
                // An empty transcript on real speech means the pipeline ran and produced nothing,
                // which is the failure a liveness check alone cannot see.
                print("TRANSCRIBE_PROBE engine=failed reason=empty-transcript")
                return 4
            }
            print("TRANSCRIBE_PROBE engine=ok")
            return 0
        } catch {
            print("TRANSCRIBE_PROBE engine=failed error=\(error)")
            return 5
        }
    }

    /// Returns capture-shaped buffers plus a label for the source they came from.
    private static func acquireAudio(
        env: [String: String]
    ) async throws -> ([PushTextKit.AudioBuffer], String) {
        if let path = env["PUSHTEXT_TRANSCRIBE_PROBE_FILE"] {
            return (try fileBuffers(path: path), "file:\(path)")
        }
        let seconds = Double(env["PUSHTEXT_TRANSCRIBE_PROBE_SECONDS"] ?? "") ?? 5
        return (try await microphoneBuffers(seconds: seconds), "microphone")
    }

    /// Reads a WAV into the same shape `AVAudioEngineCapture` emits: mono Float32 at the file's
    /// rate, with contiguous start times from a running frame count.
    private static func fileBuffers(
        path: String,
        framesPerBuffer: Int = 2_400
    ) throws -> [PushTextKit.AudioBuffer] {
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
        let format = file.processingFormat
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(file.length)),
              let channel = buffer.floatChannelData else {
            throw NSError(domain: "TranscriptionProbe", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "cannot read \(path) as float PCM"
            ])
        }
        try file.read(into: buffer)

        let all = Array(UnsafeBufferPointer(start: channel[0], count: Int(buffer.frameLength)))
        var result: [PushTextKit.AudioBuffer] = []
        var offset = 0
        while offset < all.count {
            let end = min(offset + framesPerBuffer, all.count)
            result.append(PushTextKit.AudioBuffer(
                samples: Array(all[offset..<end]),
                sampleRate: format.sampleRate,
                startTime: Double(offset) / format.sampleRate))
            offset = end
        }
        return result
    }

    private static func microphoneBuffers(seconds: Double) async throws -> [PushTextKit.AudioBuffer] {
        guard AVAudioEngineCaptureAuthorization.isAuthorized else {
            throw NSError(domain: "TranscriptionProbe", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "microphone not authorized"
            ])
        }
        let capture = AVAudioEngineCapture()
        let collected = LockedBuffers()

        print("TRANSCRIBE_PROBE speak now for \(String(format: "%.0f", seconds))s ...")
        fflush(stdout)

        try capture.start { buffer in collected.append(buffer) }
        try await Task.sleep(for: .seconds(seconds))
        capture.stop()

        return collected.snapshot()
    }
}

/// Minimal mutable box so a `Task` can hand a value back across the semaphore wait.
private final class Box<Value>: @unchecked Sendable {
    var value: Value
    init(_ value: Value) { self.value = value }
}

/// Accumulates capture buffers off the drain queue. The lock is taken only inside these
/// synchronous methods - `NSLock.lock()` is unavailable directly from an async context.
private final class LockedBuffers: @unchecked Sendable {
    private let lock = NSLock()
    private var buffers: [PushTextKit.AudioBuffer] = []

    func append(_ buffer: PushTextKit.AudioBuffer) {
        lock.lock()
        buffers.append(buffer)
        lock.unlock()
    }

    func snapshot() -> [PushTextKit.AudioBuffer] {
        lock.lock()
        defer { lock.unlock() }
        return buffers
    }
}
