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
}
