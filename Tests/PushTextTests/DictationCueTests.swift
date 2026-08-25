import Testing
import Foundation
@testable import PushText
import PushTextKit
import PushTextCore

/// The start and stop cues, at the point they are triggered (#172).
///
/// `DictationToneTests` covers what the tone SOUNDS like. This covers when it plays, which is the
/// half a user notices: a cue on a dictation that never started, or a cue that keeps playing after
/// they switched it off.
@Suite("Dictation cues")
@MainActor
struct DictationCueTests {

    /// Records what was asked for, so the assertions are about calls rather than about audio.
    private final class SpySounds: DictationSoundPlaying, @unchecked Sendable {
        private let lock = NSLock()
        private var played: [DictationTone] = []

        func play(_ tone: DictationTone) {
            lock.lock(); played.append(tone); lock.unlock()
        }

        var tones: [DictationTone] {
            lock.lock(); defer { lock.unlock() }
            return played
        }
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

    private func model(sounds: SpySounds, enabled: Bool) -> (AppModel, FakeCapture) {
        let capture = FakeCapture()
        let model = AppModel(engine: MockTranscriptionEngine(), capture: capture,
                             injector: nil, sounds: sounds)
        model.preferences.soundEnabled = enabled
        return (model, capture)
    }

    @Test("A dictation plays start then stop, in that order")
    func playsBothCuesInOrder() async {
        let spy = SpySounds()
        let (model, capture) = model(sounds: spy, enabled: true)

        model.handle(.pressed, at: 0)
        _ = await settle { model.machine.state == .recording }
        capture.deliver()
        model.handle(.released, at: 1)
        _ = await settle { model.machine.state == .idle }

        #expect(spy.tones == [.start, .stop],
                "expected start then stop, got \(spy.tones.map(\.frequency))")
    }

    /// The toggle is the entire point of the request. A setting that does not silence it is worse
    /// than no setting, because the user has been told they turned it off.
    @Test("Nothing plays when the cues are switched off")
    func silentWhenDisabled() async {
        let spy = SpySounds()
        let (model, capture) = model(sounds: spy, enabled: false)

        model.handle(.pressed, at: 0)
        _ = await settle { model.machine.state == .recording }
        capture.deliver()
        model.handle(.released, at: 1)
        _ = await settle { model.machine.state == .idle }

        #expect(spy.tones.isEmpty, "played \(spy.tones.count) cues while switched off")
    }

    /// The preference is read per transition, so switching it on mid-session takes effect on the
    /// next dictation rather than the next launch.
    @Test("Switching it on takes effect without a relaunch")
    func takesEffectImmediately() async {
        let spy = SpySounds()
        let (model, capture) = model(sounds: spy, enabled: false)

        model.handle(.pressed, at: 0)
        _ = await settle { model.machine.state == .recording }
        model.handle(.released, at: 1)
        _ = await settle { model.machine.state == .idle }
        #expect(spy.tones.isEmpty)

        model.preferences.soundEnabled = true
        model.handle(.pressed, at: 2)
        _ = await settle { model.machine.state == .recording }
        capture.deliver()
        model.handle(.released, at: 3)
        _ = await settle { model.machine.state == .idle }

        #expect(spy.tones.contains(.start), "the toggle needed a relaunch to take effect")
    }
}
