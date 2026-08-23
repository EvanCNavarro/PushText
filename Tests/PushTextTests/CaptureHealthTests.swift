import Testing
import Foundation
@testable import PushText
import PushTextKit
import PushTextCore

/// Whether the user is told that an utterance lost audio (#71).
///
/// `AVAudioEngineCapture` has counted `restartCount`, `restartFailures` and `droppedFrames` since
/// #70, and NOTHING read any of them - including `droppedFrames`, whose own comment says it is
/// "surfaced rather than swallowed". A counter nobody reads is the same silence it was added to
/// break: the user gets a short transcript and reads it as bad recognition.
@Suite("Capture health")
@MainActor
struct CaptureHealthTests {

    private final class LossyCapture: AudioCapture, @unchecked Sendable {
        private let lock = NSLock()
        private var handler: (@Sendable (PushTextKit.AudioBuffer) -> Void)?
        private let reported: CaptureHealth

        init(health: CaptureHealth) { reported = health }

        var health: CaptureHealth { reported }

        func start(onBuffer: @escaping @Sendable (PushTextKit.AudioBuffer) -> Void) throws {
            lock.lock(); handler = onBuffer; lock.unlock()
        }
        func stop() { lock.lock(); handler = nil; lock.unlock() }
        func deliver() {
            lock.lock(); let h = handler; lock.unlock()
            h?(PushTextKit.AudioBuffer(samples: [0.1], sampleRate: 48_000, startTime: 0))
        }
    }

    private func settle(_ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(2)
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    @Test("A clean capture is clean, and any loss is not")
    func cleanIsClean() {
        #expect(CaptureHealth().isClean)
        #expect(!CaptureHealth(restarts: 1).isClean)
        #expect(!CaptureHealth(restartFailures: 1).isClean)
        #expect(!CaptureHealth(droppedFrames: 1).isClean)
    }

    /// An engine that never loses anything must produce NO warning. A notice on every dictation is
    /// one the user stops reading, which costs the real ones their meaning.
    @Test("A clean utterance produces no warning")
    func cleanUtteranceIsSilent() async {
        let engine = MockTranscriptionEngine(configuration: .init(phrases: ["hello"],
                                                                  latency: .milliseconds(1)))
        let capture = LossyCapture(health: CaptureHealth())
        let model = AppModel(engine: engine, capture: capture, injector: nil)

        model.handle(.pressed, at: 0)
        _ = await settle { model.machine.state == .recording }
        capture.deliver()
        model.handle(.released, at: 0.2)

        _ = await settle { model.machine.state == .idle }
        #expect(model.lastCaptureWarning == nil)
    }

    /// The point of #71: a device change is no longer silent.
    @Test("A device restart during the utterance is reported to the user")
    func restartIsReported() async {
        let engine = MockTranscriptionEngine(configuration: .init(phrases: ["hello"],
                                                                  latency: .milliseconds(1)))
        let capture = LossyCapture(health: CaptureHealth(restarts: 1))
        let model = AppModel(engine: engine, capture: capture, injector: nil)

        model.handle(.pressed, at: 0)
        _ = await settle { model.machine.state == .recording }
        capture.deliver()
        model.handle(.released, at: 0.2)

        _ = await settle { model.lastCaptureWarning != nil }
        let warning = model.lastCaptureWarning ?? ""
        #expect(warning.lowercased().contains("device"),
                "a restart must name the CAUSE the user can act on, got: \(warning)")
    }

    /// Dropped frames are a DIFFERENT cause with a different remedy, so they must not share copy
    /// with a device change - telling someone their input device changed when it did not sends
    /// them looking for a cable.
    @Test("Dropped frames read differently from a device change")
    func droppedFramesAreTheirOwnMessage() {
        let restart = AppModel.captureWarning(for: CaptureHealth(restarts: 1))
        let dropped = AppModel.captureWarning(for: CaptureHealth(droppedFrames: 4_800))

        #expect(restart != nil && dropped != nil)
        #expect(restart != dropped)
        #expect(dropped?.lowercased().contains("device") != true)
    }

    /// A restart that FAILED lost the rest of the utterance, not a fraction of it. Saying the same
    /// thing for both understates a total loss.
    @Test("A failed restart is stated more strongly than a successful one")
    func failedRestartIsDistinct() {
        let recovered = AppModel.captureWarning(for: CaptureHealth(restarts: 1))
        let failed = AppModel.captureWarning(for: CaptureHealth(restarts: 1, restartFailures: 1))

        #expect(recovered != failed)
    }
}
