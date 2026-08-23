import Foundation
import PushTextCore

/// Headless proof that microphone capture is real.
///
/// A green `AudioRingBuffer` suite proves the FIFO's arithmetic and nothing about whether macOS will
/// hand this process audio. That depends on a TCC grant, on the engine starting, on the sink node
/// being connected at a format the hardware accepts, and on the drain loop running.
///
/// Activated by `PUSHTEXT_AUDIO_PROBE=1`; `PUSHTEXT_AUDIO_PROBE_SECONDS` bounds it (default 4).
/// Exits non-zero when capture could not start, so it is usable as a gate.
public enum AudioProbe {
    public static var isRequested: Bool {
        ProcessInfo.processInfo.environment["PUSHTEXT_AUDIO_PROBE"] == "1"
    }

    public static func runAndExit() -> Never {
        let env = ProcessInfo.processInfo.environment
        let seconds = Double(env["PUSHTEXT_AUDIO_PROBE_SECONDS"] ?? "") ?? 4

        print("AUDIO_PROBE micAuthorized=\(AVAudioEngineCaptureAuthorization.isAuthorized)")
        fflush(stdout)

        if !AVAudioEngineCaptureAuthorization.isAuthorized {
            if env["PUSHTEXT_AUDIO_PROBE_PROMPT"] == "1" {
                print("AUDIO_PROBE requesting microphone access (system dialog)")
                fflush(stdout)
                let granted = AVAudioEngineCaptureAuthorization.requestBlocking(timeout: 60)
                print("AUDIO_PROBE micGranted=\(granted)")
                fflush(stdout)
            }
            if !AVAudioEngineCaptureAuthorization.isAuthorized {
                print("AUDIO_PROBE capture=skipped reason=not-authorized")
                fflush(stdout)
                exit(2)
            }
        }

        let capture = AVAudioEngineCapture()
        let stats = CaptureStats()

        do {
            try capture.start { buffer in stats.record(buffer) }
        } catch {
            print("AUDIO_PROBE capture=failed error=\(error)")
            fflush(stdout)
            exit(1)
        }
        print("AUDIO_PROBE capture=started seconds=\(seconds)")
        fflush(stdout)

        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
        capture.stop()

        let result = stats.snapshot()
        print("AUDIO_PROBE buffers=\(result.buffers) frames=\(result.frames) "
            + "sampleRate=\(result.sampleRate) dropped=\(capture.droppedFrames)")
        print("AUDIO_PROBE timestampsMonotonic=\(result.monotonic) contiguous=\(result.contiguous)")
        print("AUDIO_PROBE restarts=\(capture.restartCount) restartFailures=\(capture.restartFailures)")

        reportCompleteness(frames: result.frames, sampleRate: result.sampleRate, seconds: seconds)
        print(String(format: "AUDIO_PROBE peak=%.5f rms=%.5f silent=%@",
                     result.peak, result.rms, result.peak < 1e-6 ? "true" : "false"))
        print("AUDIO_PROBE finished")
        fflush(stdout)
        exit(0)
    }

    /// Exits non-zero if capture stopped early (#70).
    ///
    /// `monotonic`, `contiguous` and `dropped=0` all describe only the frames that DID arrive, so
    /// they are blind to truncation BY CONSTRUCTION - every one of them passed on runs that lost 5
    /// of 8 seconds to a device change. Elapsed wall time is the one signal here that a missing
    /// frame cannot forge.
    ///
    /// 15% covers ordinary start-up latency and the final partial drain. The failure this catches
    /// lost 66%, so the threshold is nowhere near the signal it has to separate.
    private static func reportCompleteness(frames: Int, sampleRate: Double, seconds: Double) {
        let expected = seconds * sampleRate
        let ratio = expected > 0 ? Double(frames) / expected : 0
        let complete = ratio >= 0.85
        print(String(format: "AUDIO_PROBE expectedFrames=%.0f completeness=%.3f complete=%@",
                     expected, ratio, complete ? "true" : "false"))
        fflush(stdout)
        guard complete else {
            print("AUDIO_PROBE capture=truncated - stopped early while reporting healthy frames")
            fflush(stdout)
            exit(4)
        }
    }
}

/// Non-prompting authorisation check, kept separate so the probe does not drag AVFoundation into
/// every call site.
public enum AVAudioEngineCaptureAuthorization {
    public static var isAuthorized: Bool { AVAudioEngineCapture.isMicrophoneAuthorized }

    /// Requests access and blocks the calling thread until the user answers or the timeout expires.
    public static func requestBlocking(timeout: TimeInterval) -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        let result = Mutexish()
        Task {
            let granted = await AVAudioEngineCapture.requestMicrophoneAccess()
            result.set(granted)
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + timeout)
        return result.get()
    }
}

/// Minimal thread-safe box; the probe has no other need for one.
private final class Mutexish: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set(_ newValue: Bool) { lock.lock(); value = newValue; lock.unlock() }
    func get() -> Bool { lock.lock(); defer { lock.unlock() }; return value }
}

/// Accumulates what a capture run actually produced.
private final class CaptureStats: @unchecked Sendable {
    struct Snapshot {
        var buffers = 0
        var frames = 0
        var sampleRate: Double = 0
        var peak: Float = 0
        var rms: Double = 0
        var monotonic = true
        var contiguous = true
    }

    private let lock = NSLock()
    private var stats = Snapshot()
    private var lastStart: TimeInterval = -1
    private var expectedNextStart: TimeInterval = 0
    private var sumSquares: Double = 0

    func record(_ buffer: AudioBuffer) {
        lock.lock(); defer { lock.unlock() }
        stats.buffers += 1
        stats.sampleRate = buffer.sampleRate

        // Strictly increasing start times. Non-monotonic bufferStartTime is one of the suspected
        // causes of FB22149971, so it is asserted at the source rather than discovered on Tahoe.
        if buffer.startTime <= lastStart { stats.monotonic = false }
        // And no gaps or overlaps: each buffer must begin exactly where the last one ended.
        if stats.buffers > 1, abs(buffer.startTime - expectedNextStart) > 1e-9 { stats.contiguous = false }
        lastStart = buffer.startTime
        expectedNextStart = buffer.startTime + Double(buffer.samples.count) / buffer.sampleRate

        stats.frames += buffer.samples.count
        for sample in buffer.samples {
            let magnitude = abs(sample)
            if magnitude > stats.peak { stats.peak = magnitude }
            sumSquares += Double(sample) * Double(sample)
        }
    }

    func snapshot() -> Snapshot {
        lock.lock(); defer { lock.unlock() }
        var out = stats
        out.rms = stats.frames > 0 ? (sumSquares / Double(stats.frames)).squareRoot() : 0
        return out
    }
}
