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


    /// Records what the HUD was told, so "the indicator appeared" is assertable without a window.
    @MainActor
    final class SpyIndicator: DictationIndicator {
        private(set) var shown = 0
        private(set) var hidden = 0
        private(set) var phases: [HUDPhase] = []
        private(set) var levels: [Double] = []
        var onCancel: () -> Void = {}
        var onConfirm: () -> Void = {}

        var isVisible: Bool { shown > hidden }

        func show(phase: HUDPhase, onCancel: @escaping () -> Void, onConfirm: @escaping () -> Void) {
            shown += 1
            phases.append(phase)
            self.onCancel = onCancel
            self.onConfirm = onConfirm
        }

        func update(phase: HUDPhase, level: Double) {
            phases.append(phase)
            levels.append(level)
        }

        func hide() { hidden += 1 }
    }

    /// Waits for a condition rather than sleeping a fixed time. Fails CLOSED: if the condition
    /// never holds, this returns false and the caller's assertion fails - it never reports success
    /// for having run out of patience.
    private func settle(
        timeout: Duration = .seconds(5),
        line: Int = #line,
        describe: @MainActor () -> String = { "" },
        until condition: @MainActor () -> Bool
    ) async -> Bool {
        let started = ContinuousClock.now
        let deadline = started + timeout
        var satisfied = false
        while ContinuousClock.now < deadline {
            if condition() { satisfied = true; break }
            try? await Task.sleep(for: .milliseconds(5))
        }
        if !satisfied { satisfied = condition() }
        // On a timeout the condition tells you only that it is false, which is the one thing you
        // already knew. #55 stayed unexplained for exactly this reason.
        if !satisfied {
            print("SETTLE_TIMEOUT line=\(line) \(describe())")
            fflush(stdout)
        }
        Self.recordSettle(from: started, line: line, satisfied: satisfied)
        return satisfied
    }

    /// Reports a settle that took unusually long even though it eventually passed (#55).
    ///
    /// #55 is a settle that hit the 5 s ceiling once and has been reproduced exactly twice in ~198
    /// runs, so waiting for the full failure is not a strategy. The reason it stays a mystery is
    /// that a settle taking 4.9 s and one taking 5 ms are INDISTINGUISHABLE in a green run - the
    /// suite only ever reports the total. If there is a slow tail, it is already happening on
    /// passing runs and nothing looks at it.
    ///
    /// That distinction is the whole diagnosis. Occasional 200 ms settles mean scheduler starvation
    /// and the 5 s outlier is its far tail; settles that are always under a few ms mean the failure
    /// was a HANG, which is a different bug with a different fix. Printing rather than failing:
    /// this is an observation, and a threshold guessed today should not turn a green suite red.
    private static let settleWarnThreshold = Duration.milliseconds(100)

    private static func recordSettle(from started: ContinuousClock.Instant,
                                     line: Int,
                                     satisfied: Bool) {
        let elapsed = ContinuousClock.now - started
        guard elapsed > settleWarnThreshold else { return }
        let millis = Double(elapsed.components.seconds) * 1000
            + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000
        print("SETTLE_SLOW line=\(line) elapsed=\(String(format: "%.1f", millis))ms satisfied=\(satisfied)")
        fflush(stdout)
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

        model.handle(.pressed, at: 0)

        #expect(await settle { capture.startCount == 1 })
        #expect(await settle { model.machine.state == .recording })
    }

    @Test("Captured audio reaches the engine while recording")
    func audioReachesEngine() async {
        let engine = MockTranscriptionEngine(configuration: .init(latency: .milliseconds(1)))
        let capture = SpyCapture()
        let model = makeModel(engine: engine, capture: capture)

        model.handle(.pressed, at: 0)
        #expect(await settle { model.machine.state == .recording })
        capture.deliver(5)
        model.handle(.released, at: 1)

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

        model.handle(.pressed, at: 0)
        #expect(await settle { model.machine.state == .recording })
        capture.deliver(2)
        model.handle(.released, at: 1)

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

        model.handle(.pressed, at: 0)
        #expect(await settle { model.machine.state == .recording })
        capture.deliver(1)
        model.handle(.released, at: 1)

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

        model.handle(.pressed, at: 0)
        #expect(await settle { model.machine.state == .recording })
        model.handle(.released, at: 1)

        #expect(await settle { model.machine.state == .failed(.noSpeechDetected) })
        #expect(injector.injected.isEmpty)
    }

    @Test("A capture that cannot start fails the utterance instead of hanging in arming")
    func captureStartFailureIsSurfaced() async {
        let capture = SpyCapture()
        capture.startError = AVAudioEngineCapture.CaptureError.microphoneNotAuthorized
        let model = makeModel(engine: MockTranscriptionEngine(configuration: .init(latency: .milliseconds(1))),
                              capture: capture)

        model.handle(.pressed, at: 0)

        #expect(await settle { model.machine.state == .failed(.permissionDenied) })
    }

    @Test("An injection failure is reported rather than silently losing the text")
    func injectionFailureIsSurfaced() async {
        let engine = MockTranscriptionEngine(
            configuration: .init(phrases: ["some words"], latency: .milliseconds(1)))
        let capture = SpyCapture()
        let injector = SpyInjector(shouldFail: true)
        let model = makeModel(engine: engine, capture: capture, injector: injector)

        model.handle(.pressed, at: 0)
        #expect(await settle { model.machine.state == .recording })
        model.handle(.released, at: 1)

        #expect(await settle { model.machine.state == .failed(.injectionFailed) })
    }

    @Test("Two utterances in a row both produce text")
    func consecutiveUtterances() async {
        let engine = MockTranscriptionEngine(
            configuration: .init(phrases: ["first", "second"], latency: .milliseconds(1)))
        let capture = SpyCapture()
        let injector = SpyInjector()
        let model = makeModel(engine: engine, capture: capture, injector: injector)

        // Explicit timestamps, ten seconds apart. With a wall clock these two utterances land
        // inside the 0.4 s double-press window, so the second press LATCHES and the release no
        // longer ends it - correct behaviour, and a reminder that a test racing a real clock is
        // testing the clock.
        for index in 0..<2 {
            let base = Double(index) * 10
            model.handle(.pressed, at: base)
            #expect(await settle { model.machine.state == .recording })
            capture.deliver(1)
            model.handle(.released, at: base + 1)
            #expect(await settle { model.machine.state == .idle })
        }

        #expect(injector.injected == ["first", "second"])
    }

    // MARK: - Latching and cancel (#46)

    @Test("A double press latches: the utterance survives the key release")
    func doublePressLatches() async {
        let engine = MockTranscriptionEngine(
            configuration: .init(phrases: ["latched words"], latency: .milliseconds(1)))
        let capture = SpyCapture()
        let injector = SpyInjector()
        let model = AppModel(engine: engine, capture: capture, injector: injector)

        model.handle(.pressed, at: 0)      // first tap
        model.handle(.released, at: 0.05)
        model.handle(.pressed, at: 0.20)   // second tap, inside the window -> latch
        #expect(await settle { model.machine.state == .recording })

        model.handle(.released, at: 0.25)
        capture.deliver(3)
        // THE point: still recording with the key up.
        #expect(model.machine.state == .recording)
        #expect(injector.injected.isEmpty)

        model.handle(.pressed, at: 1.0)    // press again to end
        #expect(await settle(describe: {
            "state=\(model.machine.state) injected=\(injector.injected) "
            + "captureStarts=\(capture.startCount) captureStops=\(capture.stopCount)"
        }) { injector.injected == ["latched words"] })
    }

    @Test("Cancel discards the utterance and injects nothing")
    func cancelInjectsNothing() async {
        let engine = MockTranscriptionEngine(
            configuration: .init(phrases: ["should never appear"], latency: .milliseconds(1)))
        let capture = SpyCapture()
        let injector = SpyInjector()
        let model = AppModel(engine: engine, capture: capture, injector: injector)

        model.handle(.pressed, at: 0)
        #expect(await settle { model.machine.state == .recording })
        capture.deliver(3)

        model.apply(.cancelRequested)

        #expect(await settle { model.machine.state == .idle })
        #expect(injector.injected.isEmpty, "cancel must not type anything")
        #expect(capture.isRunning == false, "cancel must close the microphone")
    }

    @Test("The indicator is shown while recording and hidden when the utterance ends")
    func indicatorFollowsState() async {
        let indicator = SpyIndicator()
        let engine = MockTranscriptionEngine(
            configuration: .init(phrases: ["some text"], latency: .milliseconds(1)))
        let capture = SpyCapture()
        let model = AppModel(engine: engine, capture: capture,
                             injector: SpyInjector(), indicator: indicator)

        model.handle(.pressed, at: 0)
        #expect(await settle { indicator.isVisible })
        #expect(await settle { model.machine.state == .recording })

        model.handle(.released, at: 0.5)

        #expect(await settle { indicator.hidden > 0 }, "the HUD stayed up after the utterance ended")
    }

    @Test("The HUD's cancel control discards, exactly as the event does")
    func indicatorCancelControlWorks() async {
        let indicator = SpyIndicator()
        let injector = SpyInjector()
        let model = AppModel(engine: MockTranscriptionEngine(configuration: .init(latency: .milliseconds(1))),
                             capture: SpyCapture(), injector: injector, indicator: indicator)

        model.handle(.pressed, at: 0)
        #expect(await settle { model.machine.state == .recording })

        indicator.onCancel()

        #expect(await settle { model.machine.state == .idle })
        #expect(injector.injected.isEmpty)
    }
}
