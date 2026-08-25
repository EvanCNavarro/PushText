import Testing
import Foundation
@testable import PushText
import PushTextKit
import PushTextCore

/// Silencing the Mac while dictating, at the points it is driven from (#188).
///
/// `DictationMuterTests` covers the muter. This covers the WIRING, which is where the danger is: a
/// restore that only runs on the happy path leaves the Mac silent on exactly the paths that fire
/// when something has already gone wrong.
@Suite("Silence while dictating")
@MainActor
struct SilenceWhileDictatingTests {

    private final class FakeOutput: SystemAudioOutput, @unchecked Sendable {
        private let lock = NSLock()
        private var muted = false
        init() {}
        var isMuted: Bool { lock.lock(); defer { lock.unlock() }; return muted }
        func setMuted(_ value: Bool) { lock.lock(); muted = value; lock.unlock() }
    }

    private final class FakeCapture: AudioCapture, @unchecked Sendable {
        private let lock = NSLock()
        private var handler: (@Sendable (PushTextKit.AudioBuffer) -> Void)?
        var health: CaptureHealth { CaptureHealth() }
        func start(onBuffer: @escaping @Sendable (PushTextKit.AudioBuffer) -> Void) throws {
            lock.lock(); handler = onBuffer; lock.unlock()
        }
        func stop() { lock.lock(); handler = nil; lock.unlock() }
        func deliver() {
            lock.lock(); let handler = self.handler; lock.unlock()
            handler?(PushTextKit.AudioBuffer(samples: [0.1], sampleRate: 48_000, startTime: 0))
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

    private func make(enabled: Bool) -> (AppModel, FakeCapture, FakeOutput) {
        let output = FakeOutput()
        // Its own defaults suite, so a test never writes the developer's settings (#185).
        let defaults = UserDefaults(suiteName: "dev.ecn.apps.pushtext.test.silence.\(UUID().uuidString)")!
        let capture = FakeCapture()
        let model = AppModel(engine: MockTranscriptionEngine(), capture: capture, injector: nil,
                             muter: DictationMuter(output: output, defaults: defaults))
        model.preferences.silenceWhileDictating = enabled
        return (model, capture, output)
    }

    @Test("Dictating silences the Mac and finishing gives it back")
    func silencedWhileRecording() async {
        let (model, capture, output) = make(enabled: true)

        model.handle(.pressed, at: 0)
        _ = await settle { model.machine.state == .recording }
        #expect(output.isMuted, "the Mac was not silenced while recording")

        capture.deliver()
        model.handle(.released, at: 1)
        _ = await settle { model.machine.state == .idle }
        #expect(output.isMuted == false, "the sound was never given back")
    }

    /// THE path that matters. Cancel is what fires when something has already gone wrong, and it is
    /// the one an implementation forgets - leaving the Mac silent with no dictation to show for it.
    @Test("Cancelling gives the sound back")
    func cancelRestores() async {
        let (model, capture, output) = make(enabled: true)

        model.handle(.pressed, at: 0)
        _ = await settle { model.machine.state == .recording }
        #expect(output.isMuted)

        capture.deliver()
        model.apply(.cancelRequested)
        _ = await settle { model.machine.state == .idle }

        #expect(output.isMuted == false, "cancelled mid-dictation and the Mac stayed silent")
    }

    @Test("With the setting off, the Mac is never touched")
    func disabledNeverSilences() async {
        let (model, capture, output) = make(enabled: false)

        model.handle(.pressed, at: 0)
        _ = await settle { model.machine.state == .recording }
        #expect(output.isMuted == false, "silenced the Mac without being asked")

        capture.deliver()
        model.handle(.released, at: 1)
        _ = await settle { model.machine.state == .idle }
        #expect(output.isMuted == false)
    }
}
