import Testing
import Foundation
@testable import PushTextKit
import PushTextCore

#if canImport(FoundationModels)

/// The cleanup pass's POLICY, exercised without a model (#14).
///
/// The LLM call sits behind an injectable responder so every fallback path is testable: the nine
/// `GenerationError` cases, an empty response, and - the one that matters most - a response that
/// drifts. Without the seam these paths could only be reached by provoking a real model into
/// misbehaving, which is not repeatable and not something a suite can assert on.
@Suite("FoundationModelsCleanup policy")
struct FoundationModelsCleanupTests {

    /// `@available` cannot be applied to `@Suite`/`@Test`, so the gate is a trait plus an inner
    /// availability check - the same shape `AppleSpeechEngineTests` uses. A trait keeps a skip
    /// visible as a SKIP; an early return would render as a pass on a machine that never ran it.
    static let supportsFoundationModels: Bool = {
        if #available(macOS 26, *) { return true }
        return false
    }()

    private struct FakeFailure: Error {}

    private func transcript(_ text: String) -> Transcript {
        Transcript(text: text, duration: 1)
    }

    @Test("A plausible cleanup is returned", .enabled(if: FoundationModelsCleanupTests.supportsFoundationModels))
    func plausibleCleanupIsUsed() async throws {
        guard #available(macOS 26, *) else { return }
        let cleanup = FoundationModelsCleanup(respond: { _ in
            "So I think we should ship the thing on Friday."
        })

        let result = try await cleanup.clean(
            transcript("um so I think we should ship the thing on Friday you know"))

        #expect(result == "So I think we should ship the thing on Friday.")
    }

    /// The failure the whole guard exists for. VoiceInk would type "Paris" here.
    @Test("A response that answers the question falls back to the raw transcript", .enabled(if: FoundationModelsCleanupTests.supportsFoundationModels))
    func driftFallsBackToRaw() async throws {
        guard #available(macOS 26, *) else { return }
        let raw = "what is the capital of France"
        let cleanup = FoundationModelsCleanup(respond: { _ in "Paris" })

        #expect(try await cleanup.clean(transcript(raw)) == raw)
    }

    @Test("Meaning inversion falls back to the raw transcript", .enabled(if: FoundationModelsCleanupTests.supportsFoundationModels))
    func inversionFallsBackToRaw() async throws {
        guard #available(macOS 26, *) else { return }
        let raw = "I don't want to ship this today"
        let cleanup = FoundationModelsCleanup(respond: { _ in "I want to ship this today." })

        #expect(try await cleanup.clean(transcript(raw)) == raw)
    }

    /// #14's requirement: silent fallback on ALL nine GenerationError cases. Any thrown error is
    /// treated the same way, so a case Apple adds later cannot become a user-visible failure.
    @Test("A thrown error falls back to the raw transcript rather than propagating", .enabled(if: FoundationModelsCleanupTests.supportsFoundationModels))
    func thrownErrorFallsBackToRaw() async throws {
        guard #available(macOS 26, *) else { return }
        let raw = "the transcript survives a model failure"
        let cleanup = FoundationModelsCleanup(respond: { _ in throw FakeFailure() })

        #expect(try await cleanup.clean(transcript(raw)) == raw)
    }

    @Test("An empty response falls back to the raw transcript", .enabled(if: FoundationModelsCleanupTests.supportsFoundationModels))
    func emptyResponseFallsBackToRaw() async throws {
        guard #available(macOS 26, *) else { return }
        let raw = "there are real words here"
        for empty in ["", "   ", "\n"] {
            let cleanup = FoundationModelsCleanup(respond: { _ in empty })
            #expect(try await cleanup.clean(transcript(raw)) == raw, "empty '\(empty)' was used")
        }
    }

    @Test("An empty transcript is returned without calling the model", .enabled(if: FoundationModelsCleanupTests.supportsFoundationModels))
    func emptyTranscriptSkipsTheModel() async throws {
        guard #available(macOS 26, *) else { return }
        let called = CallFlag()
        let cleanup = FoundationModelsCleanup(respond: { _ in called.mark(); return "something" })

        #expect(try await cleanup.clean(transcript("")) == "")
        #expect(called.wasCalled == false, "the model was asked to clean nothing")
    }

    /// Shadow mode, which #8 exists to enable: the rejection REASON has to be retrievable, or the
    /// thresholds can never be calibrated against real dictation.
    @Test("The last rejection reason is recorded for calibration", .enabled(if: FoundationModelsCleanupTests.supportsFoundationModels))
    func rejectionReasonIsRecorded() async throws {
        guard #available(macOS 26, *) else { return }
        let cleanup = FoundationModelsCleanup(respond: { _ in "I want to ship this today." })
        _ = try await cleanup.clean(transcript("I don't want to ship this today"))

        #expect(await cleanup.lastRejection == .meaningInverted)
    }

    @Test("A clean pass leaves no stale rejection behind", .enabled(if: FoundationModelsCleanupTests.supportsFoundationModels))
    func acceptedCleanupClearsTheReason() async throws {
        guard #available(macOS 26, *) else { return }
        let cleanup = FoundationModelsCleanup(respond: { _ in "Ship it." })
        _ = try await cleanup.clean(transcript("ship it"))

        #expect(await cleanup.lastRejection == nil)
    }

    /// The prompt has to carry the transcript, or the model is cleaning nothing. Asserted because a
    /// prompt-building mistake would otherwise show up only as poor output from a real model.
    @Test("The transcript reaches the prompt", .enabled(if: FoundationModelsCleanupTests.supportsFoundationModels))
    func promptContainsTheTranscript() async throws {
        guard #available(macOS 26, *) else { return }
        let seen = PromptBox()
        let cleanup = FoundationModelsCleanup(respond: { prompt in
            seen.record(prompt)
            return "Ship it."
        })

        _ = try await cleanup.clean(transcript("ship it"))

        #expect(seen.value.contains("ship it"))
    }
}

/// Small mutable boxes: the responder is `@Sendable`, so a captured `var` will not compile.
private final class CallFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var called = false
    func mark() { lock.lock(); called = true; lock.unlock() }
    var wasCalled: Bool { lock.lock(); defer { lock.unlock() }; return called }
}

private final class PromptBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = ""
    func record(_ text: String) { lock.lock(); stored = text; lock.unlock() }
    var value: String { lock.lock(); defer { lock.unlock() }; return stored }
}

#endif
