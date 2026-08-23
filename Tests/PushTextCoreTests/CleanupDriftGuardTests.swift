import Testing
import Foundation
@testable import PushTextCore

/// The guard that stops an LLM's "cleanup" from replacing the user's words (#8).
///
/// This is the differentiator, not a nicety. `docs/research/06` sec 4.4 read the response-consuming
/// path in six projects: Handy (30k stars), VoiceInk (6k), Whispering (4.7k), PipeVoice and
/// mlxwhisperinput all fall back to the raw transcript ONLY on transport errors - blank input, API
/// failure, empty response - and never compare content at all. Zero occurrences of Levenshtein, edit
/// distance, similarity, word overlap or length ratio in any of them. "If the model answers the
/// question, VoiceInk types the answer."
///
/// Thresholds are taken from `EtanHey/voicelayer`'s `validatePolishCandidate()`, the only real
/// implementation found. The research is explicit that it is a 1-star repo - an existence proof and
/// a well-considered design, not a battle-tested standard - so these are a starting point to
/// calibrate, not received truth.
@Suite("Cleanup drift guard")
struct CleanupDriftGuardTests {

    // MARK: - The failure this exists for

    /// `MockTranscriptionEngine` ships "what is the capital of France" as a default phrase precisely
    /// because it is the case that makes a model answer instead of clean.
    @Test("Answering the question is rejected, not typed")
    func answeringTheQuestionIsRejected() {
        let verdict = CleanupDriftGuard.verdict(
            raw: "what is the capital of France",
            cleaned: "Paris")

        #expect(verdict != .plausible, "the model answered the question and the guard allowed it")
    }

    /// The worst possible failure for dictation: the text reads fluently and means the opposite.
    @Test("Meaning inversion is rejected")
    func negationFlipIsRejected() {
        let verdict = CleanupDriftGuard.verdict(
            raw: "I do not want to ship this on Friday",
            cleaned: "I want to ship this on Friday.")

        #expect(verdict == .rejected(.meaningInverted))
    }

    @Test("Adding a negation that was not spoken is rejected")
    func addedNegationIsRejected() {
        let verdict = CleanupDriftGuard.verdict(
            raw: "we should merge the branch today",
            cleaned: "we should not merge the branch today.")

        #expect(verdict == .rejected(.meaningInverted))
    }

    // MARK: - What legitimate cleanup looks like, and must survive

    /// If the guard rejects this, cleanup is useless and every utterance ships raw. A guard that
    /// only ever rejects is as broken as one that only ever accepts, which is why both directions
    /// are tested.
    @Test("Filler removal and punctuation are accepted")
    func ordinaryCleanupIsAccepted() {
        let verdict = CleanupDriftGuard.verdict(
            raw: "um so I think we should probably ship the thing on Friday you know",
            cleaned: "So I think we should probably ship the thing on Friday.")

        #expect(verdict == .plausible)
    }

    @Test("An unchanged transcript is trivially plausible")
    func identicalIsAccepted() {
        let text = "the quick brown fox jumps over the lazy dog"
        #expect(CleanupDriftGuard.verdict(raw: text, cleaned: text) == .plausible)
    }

    @Test("Capitalisation and punctuation alone are accepted")
    func punctuationOnlyIsAccepted() {
        let verdict = CleanupDriftGuard.verdict(
            raw: "the build passed and the tests are green so we can merge this now",
            cleaned: "The build passed and the tests are green, so we can merge this now.")

        #expect(verdict == .plausible)
    }

    // MARK: - Length

    /// The 0.72 floor is exactly the truncation failure Ma et al. measured (docs/research/06).
    @Test("Truncation is rejected for a long enough input")
    func truncationIsRejected() {
        let raw = "I think we should ship the release on Friday afternoon after the final "
            + "regression pass has finished and the changelog has been reviewed by the team"
        let verdict = CleanupDriftGuard.verdict(raw: raw, cleaned: "Ship Friday.")

        guard case .rejected(.tooShort) = verdict else {
            Issue.record("expected tooShort, got \(verdict)")
            return
        }
    }

    @Test("Padding the transcript out is rejected")
    func expansionIsRejected() {
        let raw = "I think we should ship the release on Friday afternoon after the final "
            + "regression pass has finished and the changelog has been reviewed"
        let cleaned = raw + " " + raw

        guard case .rejected(.tooLong) = CleanupDriftGuard.verdict(raw: raw, cleaned: cleaned) else {
            Issue.record("expected tooLong")
            return
        }
    }

    /// Short utterances legitimately change length a lot - "um yeah ok" -> "Yeah, okay." is a 30%
    /// swing on three words - so the length bounds only apply above the research's floor. Without
    /// this exemption the guard would reject most real short dictations.
    @Test("Short inputs are exempt from the length bounds")
    func shortInputsSkipLengthBounds() {
        #expect(CleanupDriftGuard.verdict(raw: "um yeah ok", cleaned: "Yeah, okay.") == .plausible)
    }

    // MARK: - Grounding

    /// The Apple paper's hallucination metric as a runtime guard: every content word in the output
    /// must be available in the input.
    @Test("A novel content word is rejected even when the length is plausible")
    func ungroundedContentIsRejected() {
        let verdict = CleanupDriftGuard.verdict(
            raw: "please add the login button to the settings page",
            cleaned: "please add the logout button to the dashboard page")

        guard case .rejected(.ungroundedContent) = verdict else {
            Issue.record("expected ungroundedContent, got \(verdict)")
            return
        }
    }

    /// Function words and inflections are what cleanup legitimately changes, so grounding must not
    /// trip on them - otherwise every real cleanup is rejected and the guard is useless.
    @Test("Function words and casing do not count as ungrounded")
    func functionWordsAreNotUngrounded() {
        let verdict = CleanupDriftGuard.verdict(
            raw: "so we need to fix the parser before the release goes out",
            cleaned: "So, we need to fix the parser before the release goes out.")

        #expect(verdict == .plausible)
    }

    // MARK: - Degenerate input

    @Test("An empty cleanup is rejected rather than typed as nothing")
    func emptyIsRejected() {
        #expect(CleanupDriftGuard.verdict(raw: "some real words here", cleaned: "") == .rejected(.empty))
        #expect(CleanupDriftGuard.verdict(raw: "some real words here", cleaned: "   ") == .rejected(.empty))
    }

    /// Nothing was said, so nothing can drift. The caller has already decided this is not an
    /// utterance; the guard must not turn it into a rejection the UI would report as a failure.
    @Test("An empty raw transcript is not the guard's problem")
    func emptyRawIsPlausible() {
        #expect(CleanupDriftGuard.verdict(raw: "", cleaned: "") == .plausible)
    }

    /// The verdict carries WHY, because #14 will log it in shadow mode to calibrate these
    /// thresholds against real dictation. A boolean would make that calibration impossible.
    @Test("Rejections identify themselves")
    func rejectionsCarryAReason() {
        let inverted = CleanupDriftGuard.verdict(raw: "do not merge", cleaned: "merge")
        #expect(inverted == .rejected(.meaningInverted))

        let empty = CleanupDriftGuard.verdict(raw: "words", cleaned: "")
        #expect(empty == .rejected(.empty))
    }

    /// The realistic form. People dictate "don't", not "do not" - and a negation check that only
    /// catches the spaced form catches nothing in practice. The first version of the tokeniser split
    /// "don't" into "don" + "t", neither of which is a negation, so this passed silently while the
    /// guard was blind to every contraction.
    @Test("Contracted negations are counted")
    func contractedNegationsAreCounted() {
        let dropped = CleanupDriftGuard.verdict(
            raw: "I don't want to ship this on Friday",
            cleaned: "I want to ship this on Friday.")
        #expect(dropped == .rejected(.meaningInverted), "a dropped contraction was not caught")

        let added = CleanupDriftGuard.verdict(
            raw: "we should merge the branch today",
            cleaned: "we shouldn't merge the branch today.")
        #expect(added == .rejected(.meaningInverted), "an added contraction was not caught")
    }

    @Test("Tokenising keeps a contraction as one negation word")
    func tokeniserHandlesApostrophes() {
        #expect(CleanupDriftGuard.tokens("don't") == ["dont"])
        #expect(CleanupDriftGuard.tokens("I can't do it") == ["i", "cant", "do", "it"])
    }
}
