import Testing
import Foundation
@testable import PushTextCore

/// Rewrites what the recognizer heard into what the user actually means (#9).
///
/// A POST-PASS, not engine biasing. `AnalysisContext.contextualStrings` is the obvious mechanism and
/// `docs/research/01` sec 1.6 says to treat it as "UNVERIFIED and probably absent" on
/// `SpeechTranscriber` - a forum responder reports it works only with `DictationTranscriber`, and
/// Argmax independently reports SpeechAnalyzer "lacks the Custom Vocabulary feature". #13 spikes
/// that question; this works regardless of how it lands.
@Suite("CustomDictionary")
struct CustomDictionaryTests {

    private func dictionary(_ pairs: [(String, String)]) -> CustomDictionary {
        CustomDictionary(entries: pairs.map { DictionaryEntry(spoken: $0.0, written: $0.1) })
    }

    @Test("An empty dictionary changes nothing")
    func emptyIsIdentity() {
        let text = "ship the release on Friday"
        #expect(dictionary([]).apply(to: text) == text)
    }

    @Test("A single word is rewritten")
    func singleWord() {
        let dict = dictionary([("pushtext", "PushText")])
        #expect(dict.apply(to: "I use pushtext every day") == "I use PushText every day")
    }

    /// The recognizer produces lowercase prose; the dictionary supplies the exact written form. So
    /// matching must ignore case while the OUTPUT must not.
    @Test("Matching ignores case, output preserves the written form exactly")
    func caseInsensitiveMatchExactOutput() {
        let dict = dictionary([("pushtext", "PushText")])
        #expect(dict.apply(to: "PUSHTEXT and PushText and pushtext") == "PushText and PushText and PushText")
    }

    /// The reason phrases are joined with a separator pattern rather than a literal space: a
    /// recognizer may hear "cloud code" as one word, two words, or hyphenated, and all three mean
    /// the same thing.
    @Test("A phrase matches whether it arrives spaced, hyphenated or joined")
    func phraseSeparatorVariants() {
        let dict = dictionary([("cloud code", "CloudCode")])
        #expect(dict.apply(to: "open cloud code now") == "open CloudCode now")
        #expect(dict.apply(to: "open cloud-code now") == "open CloudCode now")
        #expect(dict.apply(to: "open cloudcode now") == "open CloudCode now")
    }

    @Test("The longest matching entry wins")
    func longestMatchWins() {
        let dict = dictionary([("cloud code", "CloudCode"), ("cloud code studio", "CloudCode Studio")])
        #expect(dict.apply(to: "launch cloud code studio today") == "launch CloudCode Studio today")
    }

    /// The case above does NOT actually depend on ordering: removing the longest-first sort still
    /// passes it, because the separator pattern lets "cloud code studio" match "CloudCode studio"
    /// after the shorter rule has already run. Caught by planting the removal.
    ///
    /// This is the case that genuinely needs it: when the shorter replacement DESTROYS the text the
    /// longer entry would have matched, order is the only thing that saves it.
    @Test("A short entry must not consume text a longer entry needs")
    func longestMatchWinsWhenShortRuleIsDestructive() {
        let dict = dictionary([("cloud", "Nimbus"), ("cloud code", "CloudCode")])
        #expect(dict.apply(to: "open cloud code now") == "open CloudCode now",
                "the short entry ran first and destroyed the longer match")
    }

    /// Pins a real difference between the letter/number fence and `\b`, which treats underscore as
    /// a word character. Neither is obviously right - rewriting inside `foo_api_bar` is arguably
    /// wrong - so this exists to make the behaviour a DECISION rather than an accident, and to fail
    /// loudly if the fence is ever swapped.
    @Test("Underscores do not fence a match")
    func underscoreIsNotAFence() {
        let dict = dictionary([("api", "API")])
        #expect(dict.apply(to: "foo_api_bar") == "foo_API_bar")
    }

    /// The fence is what stops a dictionary turning ordinary words into product names. Without it
    /// "recloud coder" becomes "reCloudCoder" and the user's text is corrupted.
    @Test("A match inside a larger word is refused")
    func doesNotMatchInsideWords() {
        let dict = dictionary([("cloud code", "CloudCode")])
        #expect(dict.apply(to: "recloud coder") == "recloud coder")

        let single = dictionary([("api", "API")])
        #expect(single.apply(to: "rapid apiary") == "rapid apiary")
        #expect(single.apply(to: "the api docs") == "the API docs")
    }

    /// These pass with EITHER fence - swapping in `\b` leaves them green, because ICU's `\b` is
    /// Unicode-aware. Kept because the behaviour matters; the fence choice is pinned by the
    /// underscore test above, which is the case that actually discriminates.
    @Test("Punctuation around a match does not block it")
    func punctuationBoundaries() {
        let dict = dictionary([("pushtext", "PushText")])
        #expect(dict.apply(to: "(pushtext)") == "(PushText)")
        #expect(dict.apply(to: "pushtext, then quit") == "PushText, then quit")
        #expect(dict.apply(to: "use pushtext.") == "use PushText.")
    }

    /// Dictation and a typed dictionary do not agree on Unicode composition: "é" arrives either as
    /// one scalar or as "e" plus a combining accent, and the two are not equal without normalising.
    @Test("Composed and decomposed Unicode match the same entry")
    func unicodeNormalisation() {
        let dict = dictionary([("café", "Café")])
        let decomposed = "cafe\u{0301}"          // e + combining acute
        #expect(dict.apply(to: "the \(decomposed) is open") == "the Café is open")
        #expect(dict.apply(to: "the café is open") == "the Café is open")
    }

    @Test("Every occurrence is rewritten, not only the first")
    func replacesAllOccurrences() {
        let dict = dictionary([("api", "API")])
        #expect(dict.apply(to: "the api and the api again") == "the API and the API again")
    }

    @Test("Text with no entries present is returned unchanged")
    func noMatchIsUnchanged() {
        let dict = dictionary([("pushtext", "PushText")])
        let text = "nothing to rewrite here"
        #expect(dict.apply(to: text) == text)
    }

    /// A user typing a dictionary entry will eventually leave a blank row. It must not match
    /// everywhere, which is what an empty pattern does.
    @Test("An empty entry is ignored rather than matching everywhere")
    func emptyEntryIsIgnored() {
        let dict = dictionary([("", "NOPE"), ("api", "API")])
        #expect(dict.apply(to: "the api docs") == "the API docs")
    }

    /// Regex metacharacters in an entry must be literal - a user's dictionary is data, not a
    /// pattern language, and "C++" must not be a syntax error or match "C".
    @Test("Regex metacharacters in an entry are literal")
    func metacharactersAreLiteral() {
        let dict = dictionary([("c plus plus", "C++"), ("dot star", ".*")])
        #expect(dict.apply(to: "I write c plus plus") == "I write C++")
        #expect(dict.apply(to: "the dot star thing") == "the .* thing")
    }

    /// The replacement is data too: "$1" in a written form must be typed, not treated as a capture
    /// group reference.
    @Test("A dollar sign in the written form is not a template reference")
    func replacementIsLiteral() {
        let dict = dictionary([("price", "$1")])
        #expect(dict.apply(to: "the price is right") == "the $1 is right")
    }
}
