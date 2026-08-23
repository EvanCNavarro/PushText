import Testing
import Foundation
@testable import PushTextKit
import PushTextCore

/// The cleanup pass's POLICY, exercised without a model (#14).
///
/// The LLM call sits behind an injectable responder so every fallback path is testable: the nine
/// `GenerationError` cases, an empty response, and - the one that matters most - a response that
/// drifts. Without the seam these paths could only be reached by provoking a real model into
/// misbehaving, which is not repeatable and not something a suite can assert on.
@Suite("FoundationModelsCleanup policy")
struct FoundationModelsCleanupTests {

    private struct FakeFailure: Error {}

    private func transcript(_ text: String) -> Transcript {
        Transcript(text: text, duration: 1)
    }

    @Test("A plausible cleanup is returned")
    func plausibleCleanupIsUsed() async throws {
        let cleanup = FoundationModelsCleanup(respond: { _ in
            "So I think we should ship the thing on Friday."
        })

        let result = try await cleanup.clean(
            transcript("um so I think we should ship the thing on Friday you know"))

        #expect(result == "So I think we should ship the thing on Friday.")
    }

    /// The failure the whole guard exists for. VoiceInk would type "Paris" here.
    @Test("A response that answers the question falls back to the raw transcript")
    func driftFallsBackToRaw() async throws {
        let raw = "what is the capital of France"
        let cleanup = FoundationModelsCleanup(respond: { _ in "Paris" })

        #expect(try await cleanup.clean(transcript(raw)) == raw)
    }

    @Test("Meaning inversion falls back to the raw transcript")
    func inversionFallsBackToRaw() async throws {
        let raw = "I don't want to ship this today"
        let cleanup = FoundationModelsCleanup(respond: { _ in "I want to ship this today." })

        #expect(try await cleanup.clean(transcript(raw)) == raw)
    }

    /// #14's requirement: silent fallback on ALL nine GenerationError cases. Any thrown error is
    /// treated the same way, so a case Apple adds later cannot become a user-visible failure.
    @Test("A thrown error falls back to the raw transcript rather than propagating")
    func thrownErrorFallsBackToRaw() async throws {
        let raw = "the transcript survives a model failure"
        let cleanup = FoundationModelsCleanup(respond: { _ in throw FakeFailure() })

        #expect(try await cleanup.clean(transcript(raw)) == raw)
    }

    @Test("An empty response falls back to the raw transcript")
    func emptyResponseFallsBackToRaw() async throws {
        let raw = "there are real words here"
        for empty in ["", "   ", "\n"] {
            let cleanup = FoundationModelsCleanup(respond: { _ in empty })
            #expect(try await cleanup.clean(transcript(raw)) == raw, "empty '\(empty)' was used")
        }
    }

    @Test("An empty transcript is returned without calling the model")
    func emptyTranscriptSkipsTheModel() async throws {
        let called = CallFlag()
        let cleanup = FoundationModelsCleanup(respond: { _ in called.mark(); return "something" })

        #expect(try await cleanup.clean(transcript("")) == "")
        #expect(called.wasCalled == false, "the model was asked to clean nothing")
    }

    /// Shadow mode, which #8 exists to enable: the rejection REASON has to be retrievable, or the
    /// thresholds can never be calibrated against real dictation.
    @Test("The last rejection reason is recorded for calibration")
    func rejectionReasonIsRecorded() async throws {
        let cleanup = FoundationModelsCleanup(respond: { _ in "I want to ship this today." })
        _ = try await cleanup.clean(transcript("I don't want to ship this today"))

        #expect(await cleanup.lastRejection == .meaningInverted)
    }

    @Test("A clean pass leaves no stale rejection behind")
    func acceptedCleanupClearsTheReason() async throws {
        let cleanup = FoundationModelsCleanup(respond: { _ in "Ship it." })
        _ = try await cleanup.clean(transcript("ship it"))

        #expect(await cleanup.lastRejection == nil)
    }

    /// The prompt has to carry the transcript, or the model is cleaning nothing. Asserted because a
    /// prompt-building mistake would otherwise show up only as poor output from a real model.
    @Test("The transcript reaches the prompt")
    func promptContainsTheTranscript() async throws {
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


extension FoundationModelsCleanupTests {

    /// #94 trigger step 1. A slow dictation is only actionable if the log says WHICH slow it was, so
    /// `clean` has to record the split every time - not only when something goes wrong.
    @Test("Cleanup records what the model call cost")
    func cleanRecordsItsTiming() async throws {
        let cleanup = FoundationModelsCleanup(respond: { _ in
            try? await Task.sleep(for: .milliseconds(40))
            return "Ship it today."
        })
        _ = try await cleanup.clean(Transcript(text: "ship it today", duration: 1))

        let timing = try #require(await cleanup.lastTiming)
        #expect(timing.respondMillis >= 30,
                "recorded \(timing.respondMillis) ms for a call that slept 40 ms")
    }
}

extension FoundationModelsCleanupTests {

    /// Pins `wasWarm` to reality rather than to a constant. Nothing was prewarmed here, so a `true`
    /// would mean the field reports a hardcoded value - and a hardcoded field is worse than no
    /// field, because #94's whole next step is reading it off a real dictation.
    @Test("An un-prewarmed call reports itself as cold")
    func unwarmedCallReportsCold() async throws {
        let cleanup = FoundationModelsCleanup(respond: { _ in "Ship it today." })
        _ = try await cleanup.clean(Transcript(text: "ship it today", duration: 1))
        let timing = try #require(await cleanup.lastTiming)
        #expect(timing.wasWarm == false)
    }
}
