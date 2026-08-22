import Testing
import Foundation
import PushTextCore
import PushTextKit
@testable import PushText

/// The end-to-end loop the app exists for: hold the key, speak, release, see text appear.
///
/// Every component was independently proven before this suite existed and NONE of them was
/// connected to any other (#39) - `AppModel` held an engine it never called. These tests assert the
/// connections, not the components: that pressing the key opens an utterance, that captured audio
/// reaches the engine, and that the transcript reaches an injector. A component test cannot see any
/// of that, because each part passes in isolation while the product does nothing.
@Suite("Dictation pipeline")
@MainActor
struct DictationPipelineTests {

    /// Stands in for `AVAudioEngineCapture`. Lets a test push buffers as the drain queue would.
    final class SpyCapture: AudioCapture, @unchecked Sendable {
        private let lock = NSLock()
        private var handler: (@Sendable (PushTextKit.AudioBuffer) -> Void)?
        private(set) var startCount = 0
        private(set) var stopCount = 0
        var startError: Error?

        func start(onBuffer: @escaping @Sendable (PushTextKit.AudioBuffer) -> Void) throws {
            if let startError { throw startError }
            lock.lock(); handler = onBuffer; startCount += 1; lock.unlock()
        }

        func stop() {
            lock.lock(); handler = nil; stopCount += 1; lock.unlock()
        }

        /// Simulates the microphone delivering audio.
        func deliver(_ count: Int) {
            lock.lock(); let handler = self.handler; lock.unlock()
            for index in 0..<count {
                handler?(PushTextKit.AudioBuffer(samples: [0.1, 0.2],
                                                 sampleRate: 48_000,
                                                 startTime: Double(index)))
            }
        }

        var isRunning: Bool {
            lock.lock(); defer { lock.unlock() }
            return handler != nil
        }
    }

    /// Stands in for `PasteboardTextInjector`. What it received IS the product's output.
    final class SpyInjector: TextInjector, @unchecked Sendable {
        private let lock = NSLock()
        private var texts: [String] = []
        private let shouldFail: Bool

        init(shouldFail: Bool = false) { self.shouldFail = shouldFail }

        struct Refused: Error {}

        func inject(_ text: String) async throws {
            if shouldFail { throw Refused() }
            record(text)
        }

        // The lock lives in a synchronous method: NSLock.lock() is unavailable from an async context.
        private func record(_ text: String) {
            lock.lock(); texts.append(text); lock.unlock()
        }

        var injected: [String] {
            lock.lock(); defer { lock.unlock() }
            return texts
        }
    }

    /// Waits for a condition rather than sleeping a fixed time. Fails CLOSED: if the condition
    /// never holds, this returns false and the caller's assertion fails - it never reports success
    /// for having run out of patience.
    private func settle(
        timeout: Duration = .seconds(5),
        until condition: @MainActor () -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    private func makeModel(
        engine: any TranscriptionEngine,
        capture: SpyCapture = SpyCapture(),
        injector: SpyInjector = SpyInjector()
    ) -> AppModel {
        AppModel(engine: engine, capture: capture, injector: injector)
    }

    @Test("Holding the key opens an utterance and starts capture")
    func pressStartsCapture() async {
        let capture = SpyCapture()
        let model = makeModel(engine: MockTranscriptionEngine(configuration: .init(latency: .milliseconds(1))),
                              capture: capture)

        model.handle(.pressed)

        #expect(await settle { capture.startCount == 1 })
        #expect(await settle { model.machine.state == .recording })
    }

    @Test("Captured audio reaches the engine while recording")
    func audioReachesEngine() async {
        let engine = MockTranscriptionEngine(configuration: .init(latency: .milliseconds(1)))
        let capture = SpyCapture()
        let model = makeModel(engine: engine, capture: capture)

        model.handle(.pressed)
        #expect(await settle { model.machine.state == .recording })
        capture.deliver(5)
        model.handle(.released)

        #expect(await settle { model.machine.state == .idle })
        // The engine counts what it was fed - a capture path that delivers nothing would otherwise
        // be indistinguishable from a working one.
        #expect(await engine.lastBufferCount == 5)
    }

    @Test("Releasing the key injects the transcript into the frontmost app")
    func releaseInjectsTranscript() async {
        let engine = MockTranscriptionEngine(
            configuration: .init(phrases: ["hello from pushtext"], latency: .milliseconds(1)))
        let capture = SpyCapture()
        let injector = SpyInjector()
        let model = makeModel(engine: engine, capture: capture, injector: injector)

        model.handle(.pressed)
        #expect(await settle { model.machine.state == .recording })
        capture.deliver(2)
        model.handle(.released)

        #expect(await settle { injector.injected == ["hello from pushtext"] })
        #expect(await settle { model.machine.state == .idle })
        #expect(capture.isRunning == false, "the microphone must not stay open after release")
    }

    @Test("The microphone is closed even when transcription fails")
    func failureClosesTheMicrophone() async {
        let engine = MockTranscriptionEngine(
            configuration: .init(latency: .milliseconds(1), shouldFail: true))
        let capture = SpyCapture()
        let injector = SpyInjector()
        let model = makeModel(engine: engine, capture: capture, injector: injector)

        model.handle(.pressed)
        #expect(await settle { model.machine.state == .recording })
        capture.deliver(1)
        model.handle(.released)

        #expect(await settle { model.machine.state == .failed(.transcriptionFailed) })
        #expect(capture.isRunning == false, "a failed utterance must not leave the mic open")
        #expect(injector.injected.isEmpty, "nothing should be typed when transcription failed")
    }

    @Test("An empty transcript is not injected")
    func emptyTranscriptIsNotInjected() async {
        let engine = MockTranscriptionEngine(
            configuration: .init(phrases: ["   "], latency: .milliseconds(1)))
        let capture = SpyCapture()
        let injector = SpyInjector()
        let model = makeModel(engine: engine, capture: capture, injector: injector)

        model.handle(.pressed)
        #expect(await settle { model.machine.state == .recording })
        model.handle(.released)

        #expect(await settle { model.machine.state == .failed(.noSpeechDetected) })
        #expect(injector.injected.isEmpty)
    }

    @Test("A capture that cannot start fails the utterance instead of hanging in arming")
    func captureStartFailureIsSurfaced() async {
        let capture = SpyCapture()
        capture.startError = AVAudioEngineCapture.CaptureError.microphoneNotAuthorized
        let model = makeModel(engine: MockTranscriptionEngine(configuration: .init(latency: .milliseconds(1))),
                              capture: capture)

        model.handle(.pressed)

        #expect(await settle { model.machine.state == .failed(.permissionDenied) })
    }

    @Test("An injection failure is reported rather than silently losing the text")
    func injectionFailureIsSurfaced() async {
        let engine = MockTranscriptionEngine(
            configuration: .init(phrases: ["some words"], latency: .milliseconds(1)))
        let capture = SpyCapture()
        let injector = SpyInjector(shouldFail: true)
        let model = makeModel(engine: engine, capture: capture, injector: injector)

        model.handle(.pressed)
        #expect(await settle { model.machine.state == .recording })
        model.handle(.released)

        #expect(await settle { model.machine.state == .failed(.injectionFailed) })
    }

    @Test("Two utterances in a row both produce text")
    func consecutiveUtterances() async {
        let engine = MockTranscriptionEngine(
            configuration: .init(phrases: ["first", "second"], latency: .milliseconds(1)))
        let capture = SpyCapture()
        let injector = SpyInjector()
        let model = makeModel(engine: engine, capture: capture, injector: injector)

        for _ in 0..<2 {
            model.handle(.pressed)
            #expect(await settle { model.machine.state == .recording })
            capture.deliver(1)
            model.handle(.released)
            #expect(await settle { model.machine.state == .idle })
        }

        #expect(injector.injected == ["first", "second"])
    }
}
