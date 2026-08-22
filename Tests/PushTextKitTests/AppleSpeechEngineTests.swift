import Testing
import Foundation
import AVFoundation
@testable import PushTextKit
import PushTextCore

// `SpeechAnalyzer` ships with the macOS 26 SDK, NOT with the OS, so `@available(macOS 26, *)`
// alone is not enough: on an older SDK the symbols do not exist and the file cannot compile at all.
// CI runs `macos-15`, where exactly that happened - `cannot find type 'SpeechTranscriber' in scope`.
// `canImport(FoundationModels)` is the repo's chosen proxy for "building against the 26 SDK"
// (Package.swift), since that framework is absent from the 15 SDK and present in 26 - verified by
// `ls` on both before and after the Xcode upgrade.
#if canImport(FoundationModels)

/// Deterministic parts of `AppleSpeechEngine` only.
///
/// The engine's real proof is `TranscriptionProbe`, not this suite - whether `SpeechAnalyzer`
/// accepts our buffers depends on an installed model and on the OS build, and a format mismatch is
/// a SIGTRAP rather than a failed assertion (#32). What IS testable here is the contract around
/// that call: an engine that has not been started must refuse work instead of silently doing
/// nothing, because "no transcript" and "never began" are indistinguishable to a caller otherwise.
@Suite("AppleSpeechEngine")
struct AppleSpeechEngineTests {

    /// `SpeechAnalyzer` is macOS 26+, and the package floor is still macOS 15 (#16). Gating with a
    /// trait rather than an early `return` keeps a skip visible as a SKIP in the run output - an
    /// early return would render as a pass on a machine that never ran the code.
    static let supportsSpeechAnalyzer: Bool = {
        if #available(macOS 26, *) { return true }
        return false
    }()

    @Test("Appending before beginUtterance throws rather than dropping the audio", .enabled(if: AppleSpeechEngineTests.supportsSpeechAnalyzer))
    func appendBeforeBeginThrows() async {
        guard #available(macOS 26, *) else { return }
        let engine = AppleSpeechEngine()
        await #expect(throws: AppleSpeechEngine.EngineError.notStarted) {
            try await engine.append(
                PushTextKit.AudioBuffer(samples: [0.1, 0.2, 0.3], sampleRate: 48_000, startTime: 0))
        }
    }

    @Test("Finishing before beginUtterance throws rather than returning an empty transcript", .enabled(if: AppleSpeechEngineTests.supportsSpeechAnalyzer))
    func finishBeforeBeginThrows() async {
        guard #available(macOS 26, *) else { return }
        let engine = AppleSpeechEngine()
        await #expect(throws: AppleSpeechEngine.EngineError.notStarted) {
            _ = try await engine.finishUtterance()
        }
    }

    /// Guards the failure mode where a caller reads `deliveredSeconds` and sees a plausible number
    /// from a previous utterance.
    @Test("Reports zero delivered audio before anything has been appended", .enabled(if: AppleSpeechEngineTests.supportsSpeechAnalyzer))
    func deliveredSecondsStartsAtZero() async {
        guard #available(macOS 26, *) else { return }
        let engine = AppleSpeechEngine()
        #expect(await engine.deliveredSeconds == 0)
    }

    @Test("isAvailable is a hardware predicate that answers without starting an utterance", .enabled(if: AppleSpeechEngineTests.supportsSpeechAnalyzer))
    func availabilityIsReadable() async {
        guard #available(macOS 26, *) else { return }
        let engine = AppleSpeechEngine()
        // The VALUE is hardware-dependent, so asserting true would make this suite a machine
        // check rather than a code check. What matters is that it answers rather than hanging or
        // throwing, and that reading it leaves the engine unstarted.
        _ = await engine.isAvailable
        await #expect(throws: AppleSpeechEngine.EngineError.notStarted) {
            _ = try await engine.finishUtterance()
        }
    }

    @Test("An unsupported locale is rejected by name rather than failing deep inside the analyzer", .enabled(if: AppleSpeechEngineTests.supportsSpeechAnalyzer))
    func unsupportedLocaleThrows() async throws {
        guard #available(macOS 26, *) else { return }
        guard await AppleSpeechEngine().isAvailable else { return }
        let engine = AppleSpeechEngine(locale: Locale(identifier: "zz-ZZ"))
        await #expect(throws: AppleSpeechEngine.EngineError.localeUnsupported("zz-ZZ")) {
            try await engine.beginUtterance()
        }
    }
}
#endif
