import Testing
import Foundation
@testable import PushTextCore

/// Fuzzy transcript search (#167).
///
/// The rules here have right and wrong answers and a SwiftUI view is where those go to hide, so the
/// matcher is pure and lives in Core.
@Suite("Transcript search")
struct TranscriptSearchTests {

    private func matched(_ query: String, _ text: String) -> Bool {
        TranscriptSearch.match(query: query, in: text) != nil
    }

    private func highlighted(_ query: String, _ text: String) -> [String] {
        guard let match = TranscriptSearch.match(query: query, in: text) else { return [] }
        return match.ranges.map { String(text[$0]) }
    }

    @Test("An exact word still matches, as it did before fuzzing")
    func exactStillMatches() {
        #expect(matched("invoice", "Ask about the invoice today"))
    }

    @Test("Matching ignores case and accents")
    func foldsCaseAndAccents() {
        #expect(matched("INVOICE", "Ask about the invoice"))
        #expect(matched("cafe", "Meet at the Café"))
    }

    /// The point of the feature: a dictation you half-remember, typed the way you remember it.
    @Test("A single typo still finds the dictation")
    func toleratesOneTypo() {
        #expect(matched("invoce", "Ask about the invoice today"), "one deletion")
        #expect(matched("invocie", "Ask about the invoice today"), "one transposition")
        #expect(matched("invoicez", "Ask about the invoice today"), "one insertion")
    }

    /// The other half, and the half that makes fuzz safe to ship. Short words are where edit
    /// distance stops discriminating - at three characters, "cat" is one edit from "car", "cot",
    /// "can" and "hat". Fuzzing them turns search into noise.
    @Test("Short words are matched exactly, never fuzzily")
    func shortWordsDoNotFuzz() {
        #expect(matched("car", "Get in the car") )
        #expect(!matched("car", "Get in the cat"))
        #expect(!matched("the", "She said so"))
    }

    /// AND, not OR. Typing a second word has to NARROW the list - a search that widens as you type
    /// is one you cannot use to find anything.
    @Test("Every word in the query has to match something")
    func allTokensMustMatch() {
        let text = "Ask about the invoice and book a table"
        #expect(matched("invoice table", text))
        #expect(!matched("invoice spreadsheet", text))
    }

    @Test("An empty or whitespace query matches nothing to highlight")
    func emptyQueryIsNotAMatch() {
        #expect(TranscriptSearch.match(query: "", in: "anything") == nil)
        #expect(TranscriptSearch.match(query: "   ", in: "anything") == nil)
    }

    /// What the view paints. Highlighting the whole transcript would be the same as highlighting
    /// none of it.
    @Test("Only the matched words are returned for highlighting")
    func highlightsWordsNotTheWholeLine() {
        #expect(highlighted("invoice", "Ask about the invoice today") == ["invoice"])
        #expect(highlighted("invoce", "Ask about the invoice today") == ["invoice"],
                "a fuzzy hit highlights the word it actually matched")
    }

    /// The needles here are chosen so the test can actually SEE the sorting and the coalescing.
    ///
    /// A first version searched a single word and passed even with sorting and merging removed:
    /// one token's hits come back in document order already, so there was nothing to sort and
    /// nothing to merge. It was green against the exact defect it was written for. Two tokens, the
    /// later word typed FIRST, plus a second token landing on a word the first already hit, is what
    /// makes the difference visible.
    @Test("Ranges come back in order and never overlap")
    func rangesAreOrderedAndDisjoint() {
        let text = "invoice for the table about an invoice"
        // "table" appears AFTER "invoice", and "invoic" hits the same two words "invoice" does.
        guard let match = TranscriptSearch.match(query: "table invoice invoic", in: text) else {
            Issue.record("expected a match"); return
        }
        #expect(match.ranges.map { String(text[$0]) } == ["invoice", "table", "invoice"],
                "hits were not sorted into document order, or duplicates were not coalesced")
        for (earlier, later) in zip(match.ranges, match.ranges.dropFirst()) {
            #expect(earlier.upperBound <= later.lowerBound, "ranges overlap or are out of order")
        }
    }

    /// Punctuation sits inside the transcript, not inside what the user types.
    @Test("Trailing punctuation does not stop a word matching")
    func punctuationDoesNotBlockAMatch() {
        #expect(highlighted("invoice", "Send the invoice, please") == ["invoice"])
    }
}
