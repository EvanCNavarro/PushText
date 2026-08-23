import Testing
import Foundation
import AVFoundation
@testable import PushTextKit
import PushTextCore

/// Deterministic parts of `AppleSpeechEngine` only.
///
/// The engine's real proof is `TranscriptionProbe`, not this suite - whether `SpeechAnalyzer`
/// accepts our buffers depends on an installed model and on the OS build, and a format mismatch is
/// a SIGTRAP rather than a failed assertion (#32). What IS testable here is the contract around
/// that call: an engine that has not been started must refuse work instead of silently doing
/// nothing, because "no transcript" and "never began" are indistinguishable to a caller otherwise.
@Suite("AppleSpeechEngine")
struct AppleSpeechEngineTests {

    @Test("Appending before beginUtterance throws rather than dropping the audio")
    func appendBeforeBeginThrows() async {
        let engine = AppleSpeechEngine()
        await #expect(throws: AppleSpeechEngine.EngineError.notStarted) {
            try await engine.append(
                PushTextKit.AudioBuffer(samples: [0.1, 0.2, 0.3], sampleRate: 48_000, startTime: 0))
        }
    }

    @Test("Finishing before beginUtterance throws rather than returning an empty transcript")
    func finishBeforeBeginThrows() async {
        let engine = AppleSpeechEngine()
        await #expect(throws: AppleSpeechEngine.EngineError.notStarted) {
            _ = try await engine.finishUtterance()
        }
    }

    /// Guards the failure mode where a caller reads `deliveredSeconds` and sees a plausible number
    /// from a previous utterance.
    @Test("Reports zero delivered audio before anything has been appended")
    func deliveredSecondsStartsAtZero() async {
        let engine = AppleSpeechEngine()
        #expect(await engine.deliveredSeconds == 0)
    }

    @Test("isAvailable is a hardware predicate that answers without starting an utterance")
    func availabilityIsReadable() async {
        let engine = AppleSpeechEngine()
        // The VALUE is hardware-dependent, so asserting true would make this suite a machine
        // check rather than a code check. What matters is that it answers rather than hanging or
        // throwing, and that reading it leaves the engine unstarted.
        _ = await engine.isAvailable
        await #expect(throws: AppleSpeechEngine.EngineError.notStarted) {
            _ = try await engine.finishUtterance()
        }
    }

    @Test("An unsupported locale is rejected by name rather than failing deep inside the analyzer")
    func unsupportedLocaleThrows() async throws {
        guard await AppleSpeechEngine().isAvailable else { return }
        let engine = AppleSpeechEngine(locale: Locale(identifier: "zz-ZZ"))
        await #expect(throws: AppleSpeechEngine.EngineError.localeUnsupported("zz-ZZ")) {
            try await engine.beginUtterance()
        }
    }
    /// #36's central claim, and the only test that can hold it: `beginUtterance` must REFUSE when
    /// the model is absent, not download it.
    ///
    /// The not-installed state cannot occur on this machine - `AssetInventory` has no uninstall -
    /// so the installed-check is injected. Asserting on the ERROR is what makes this real: a
    /// version that downloaded would either hang or eventually succeed, and both are visibly
    /// different from `.modelNotReady`.
    @Test("beginUtterance refuses a missing model instead of downloading it")
    func beginRefusesWhenTheModelIsAbsent() async {
        let engine = AppleSpeechEngine(isModelInstalled: { _ in false },
                                       isTranscriberAvailable: { true })

        await #expect(throws: AppleSpeechEngine.EngineError.modelNotReady) {
            try await engine.beginUtterance()
        }
    }

    /// Hardware beats readiness, and CI is why this is asserted rather than assumed. GitHub's
    /// macos-26 runner has no Neural Engine, so the test above failed there with `.unavailable`
    /// until availability was injected too - a machine-dependent test that passed locally.
    ///
    /// The ordering is correct and worth pinning: an unusable Neural Engine is PERMANENT, so
    /// "Preparing model..." would promise a wait that never ends.
    @Test("Unusable hardware is reported ahead of a missing model")
    func hardwareFailureOutranksModelReadiness() async {
        let engine = AppleSpeechEngine(isModelInstalled: { _ in false },
                                       isTranscriberAvailable: { false })

        await #expect(throws: AppleSpeechEngine.EngineError.unavailable) {
            try await engine.beginUtterance()
        }
    }

    /// The refusal has to be FAST. A slow refusal is the same user-visible defect as a download:
    /// the key is held, the words are being spoken, and nothing is listening.
    @Test("The refusal is immediate rather than a disguised wait")
    func theRefusalIsFast() async {
        let engine = AppleSpeechEngine(isModelInstalled: { _ in false },
                                       isTranscriberAvailable: { true })

        let started = ContinuousClock.now
        _ = try? await engine.beginUtterance()
        let elapsed = ContinuousClock.now - started

        #expect(elapsed < .seconds(2), "refusal took \(elapsed), which is a wait not a refusal")
    }

    // The installed case is NOT unit-tested here on purpose. `beginUtterance` with a real
    // installed model starts SpeechAnalyzer, and a first attempt at asserting it hung past 600s -
    // the engine's real path belongs to `TranscriptionProbe`, which drives it end to end and is
    // what AGENTS.md says to cite for any claim about transcription.

}
