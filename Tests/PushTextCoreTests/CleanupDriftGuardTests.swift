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
    /// Measured in shadow mode over 20 real `SpeechTranscriber` transcripts, 3 model runs each
    /// (docs/verification/task68-cleanup-shadow-mode.md): 12 of 60 runs were rejected, 10 of them
    /// by grounding, and the single most common token was "first" - the model expanding the
    /// transcriber's "1st".
    ///
    /// That is a NORMALISATION, not invented content, and it is exactly the kind of tidying
    /// cleanup exists to do. Rejecting it means the guard fires hardest on the correction the user
    /// most wanted.
    @Test("An ordinal expanded from its digit form is grounded, not invented")
    func digitOrdinalExpansionIsGrounded() {
        let raw = "I think we should cut the scope for the 1st release"
        let cleaned = "I think we should cut the scope for the first release."

        #expect(CleanupDriftGuard.verdict(raw: raw, cleaned: cleaned) == .plausible)
    }

    @Test("The equivalence runs both ways and covers cardinals")
    func numeralEquivalenceIsSymmetric() {
        #expect(CleanupDriftGuard.verdict(raw: "give me 2 minutes",
                                          cleaned: "Give me two minutes.") == .plausible)
        #expect(CleanupDriftGuard.verdict(raw: "give me two minutes",
                                          cleaned: "Give me 2 minutes.") == .plausible)
        #expect(CleanupDriftGuard.verdict(raw: "the 3rd option",
                                          cleaned: "The third option.") == .plausible)
    }

    /// The equivalence must not become a hole. A number the transcript never contained is still
    /// invented content, and this is the assertion that stops the fix from simply disabling
    /// grounding for anything numeric.
    @Test("A number that was never said is still ungrounded")
    func unspokenNumberIsStillRejected() {
        #expect(CleanupDriftGuard.verdict(raw: "how many users signed up",
                                          cleaned: "How many users signed up? 47.")
                != .plausible)
        #expect(CleanupDriftGuard.verdict(raw: "the 1st release",
                                          cleaned: "The second release.") != .plausible)
    }

    // MARK: - Inflection (#73)

    /// The measured near-miss from `docs/verification/task68-cleanup-shadow-mode.md`.
    ///
    /// The model changed "fails" to "fail" for subject-verb agreement against a plural subject.
    /// That is a grammatical correction of a word that IS present, and grounding rejected it because
    /// it compares surface tokens.
    @Test("An inflection of a word that IS in the transcript is grounded")
    func inflectionOfAPresentWordIsGrounded() {
        let raw = "The tests with us is locally, but fails in continuous integration."
        let cleaned = "The tests with us is locally, but fail in continuous integration."
        #expect(CleanupDriftGuard.verdict(raw: raw, cleaned: cleaned) == .plausible)
    }

    /// THE regression this relaxation could cause, from the same measured batch.
    ///
    /// "faming" is what was heard; "failing" is the model guessing at the misrecognition. It must
    /// stay rejected - if a stem match let this through, the relaxation would have traded the guard
    /// for the near-miss it was meant to fix.
    @Test("A guessed substitution is still ungrounded, inflection relaxation or not")
    func guessedSubstitutionStaysRejected() {
        let raw = "The build is faming on the winter again."
        let cleaned = "The build is failing on the linter again."
        #expect(CleanupDriftGuard.verdict(raw: raw, cleaned: cleaned)
                == .rejected(.ungroundedContent(token: "failing")))
    }

    /// A near-homophone substitution is not an inflection of anything in the transcript, so the
    /// relaxation must not reach it. ("loss" and "lose" are not related by any suffix in the list -
    /// this asserts the VERDICT, and the floor that separates short stems is asserted directly in
    /// `theStemFloorRefusesShortWords` below, because this case would pass without it.)
    @Test("A near-homophone substitution is still ungrounded")
    func nearHomophoneStaysRejected() {
        let raw = "That was a real loss for the whole team this quarter, honestly."
        let cleaned = "That was a real lose for the whole team this quarter, honestly."
        #expect(CleanupDriftGuard.verdict(raw: raw, cleaned: cleaned)
                == .rejected(.ungroundedContent(token: "lose")))
    }

    /// The 4-character floor, asserted where it actually bites.
    ///
    /// Measured over `/usr/share/dict/words` (221,702 entries): dropping the floor to 1 merges 833
    /// additional pairs, and they are not all inflections - `an`/`and`, `ai`/`aid`, `ad`/`as` and
    /// `ami`/`amid` are distinct words that a 1-character stem collapses together. A false MERGE
    /// lets invention past the guard, which is the failure the guard exists to prevent.
    ///
    /// It costs real coverage and that is the accepted trade: `act`/`acting`, `aim`/`aiming` and
    /// `air`/`airing` are genuine inflections the floor also refuses. A refusal costs the user the
    /// raw transcript, which is already punctuated and capitalised; a false merge costs them text
    /// they never said.
    @Test("Stems shorter than four characters do not count as inflections")
    func theStemFloorRefusesShortWords() {
        #expect(CleanupDriftGuard.isInflectionPair("an", "and") == false)
        #expect(CleanupDriftGuard.isInflectionPair("ai", "aid") == false)
        #expect(CleanupDriftGuard.isInflectionPair("act", "acts") == false)
        // Long enough, so they do relate - and the relation holds whichever way round it is asked.
        #expect(CleanupDriftGuard.isInflectionPair("request", "requests"))
        #expect(CleanupDriftGuard.isInflectionPair("requests", "request"))
        #expect(CleanupDriftGuard.isInflectionPair("fails", "fail"))
        // The pair a stem-key version got wrong: "build" reduced to "buil" and never met "building".
        #expect(CleanupDriftGuard.isInflectionPair("build", "building"))
        // Not related by any single ending, however similar they look.
        #expect(CleanupDriftGuard.isInflectionPair("faming", "failing") == false)
        #expect(CleanupDriftGuard.isInflectionPair("loss", "lose") == false)
    }

    /// The case the guard exists for is untouched: no inflection relates a country to a city.
    @Test("Answering a dictated question is still ungrounded")
    func answeringAQuestionStaysRejected() {
        let verdict = CleanupDriftGuard.verdict(raw: "what is the capital of france",
                                                cleaned: "Paris")
        #expect(verdict == .rejected(.ungroundedContent(token: "paris")))
    }

    /// Each raw word grounds ONE cleaned word, and the relaxation must not spend a token twice.
    @Test("An inflection consumes its source token, so a repeat is still ungrounded")
    func inflectionConsumesItsSource() {
        let verdict = CleanupDriftGuard.verdict(raw: "the request timed out",
                                                cleaned: "the requests requests timed out")
        #expect(verdict == .rejected(.ungroundedContent(token: "requests")))
    }

}
