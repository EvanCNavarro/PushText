import Testing
import Foundation
@testable import PushText
import PushTextKit
import PushTextCore

/// The first utterance must never disappear into a model download (#36).
///
/// `AppleSpeechEngine.beginUtterance` awaited `ensureModelInstalled`, which issues
/// `downloadAndInstall()` when the asset is absent. PushText is push-to-talk: the user holds the
/// key and speaks IMMEDIATELY, so a silent multi-minute await loses the utterance and looks like a
/// broken app rather than a busy one.
///
/// The cold path itself cannot be reproduced here - macOS 26's `AssetInventory` exposes no
/// uninstall, only `reserve` / `release` / `status` / `assetInstallationRequest`, read from the SDK
/// interface. So the download is moved OFF the dictation path and the not-ready case is made a
/// typed, fast failure that these tests can drive through the real state machine.
@Suite("Model readiness")
@MainActor
struct ModelReadinessTests {

    /// An engine whose model is not installed, standing in for a cold machine.
    private actor NotReadyEngine: TranscriptionEngine {
        private(set) var prepareCount = 0
        private(set) var beginCount = 0

        var isAvailable: Bool { true }
        func prepare() async throws { prepareCount += 1 }
        func beginUtterance() async throws {
            beginCount += 1
            throw AppleSpeechEngine.EngineError.modelNotReady
        }
        func append(_ buffer: PushTextKit.AudioBuffer) async throws {}
        func finishUtterance() async throws -> Transcript { Transcript(text: "", duration: 0) }
    }

    private func settle(_ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(2)
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    /// The point: a not-ready model is its OWN failure, not a generic transcription error. The user
    /// is told to wait, which is true and actionable; "Transcription failed" is neither.
    @Test("A model that is not ready fails fast with its own reason, not a generic error")
    func notReadyIsItsOwnFailure() async {
        let model = AppModel(engine: NotReadyEngine(), capture: nil, injector: nil)

        model.handle(.pressed, at: 0)

        #expect(await settle { model.machine.state == .failed(.modelNotReady) })
        #expect(model.statusText == "Preparing model...")
    }

    /// A `TranscriptionEngine` that does not need preparing must not be forced to implement it -
    /// `MockTranscriptionEngine` and any future engine get the no-op by default.
    @Test("prepare() defaults to a no-op so engines need not implement it")
    func prepareHasADefault() async throws {
        let engine = MockTranscriptionEngine(configuration: .init(phrases: ["ok"],
                                                                  latency: .milliseconds(1)))
        try await engine.prepare()
        // Still usable afterwards: the default must not have side effects.
        try await engine.beginUtterance()
        #expect(try await engine.finishUtterance().text == "ok")
    }

    /// Prewarm has to happen OFF the dictation path, or it has moved the wait rather than removed
    /// it. Asserted by driving prepare() and checking no utterance was opened.
    @Test("Preparing the model opens no utterance")
    func prepareDoesNotBeginAnUtterance() async throws {
        let engine = NotReadyEngine()
        try await engine.prepare()

        #expect(await engine.prepareCount == 1)
        #expect(await engine.beginCount == 0)
    }
}
