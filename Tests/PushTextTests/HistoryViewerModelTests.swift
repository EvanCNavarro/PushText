import Testing
import Foundation
@testable import PushText
import PushTextCore

/// The searchable history viewer (#161).
///
/// The model exists because these are questions with right and wrong answers, and a SwiftUI view is
/// where right and wrong answers go to hide.
@Suite("History viewer")
@MainActor
struct HistoryViewerModelTests {

    private func record(_ text: String, at seconds: TimeInterval,
                        duration: TimeInterval = 1) -> HistoryRecord {
        HistoryRecord(text: text, recordedAt: Date(timeIntervalSince1970: seconds),
                      durationSeconds: duration)
    }

    private func model(_ records: [HistoryRecord]) -> HistoryViewerModel {
        HistoryViewerModel(records: records)
    }

    /// The file is oldest-first because it is appended to. A viewer that showed it in that order
    /// would open on the user's oldest dictation and bury today's under five hundred of them.
    @Test("Opens on the newest dictation, not the oldest")
    func newestFirst() {
        let subject = model([record("oldest", at: 100), record("middle", at: 200),
                             record("newest", at: 300)])

        #expect(subject.visible.map(\.record.text) == ["newest", "middle", "oldest"])
    }

    @Test("Search ignores case")
    func searchIgnoresCase() {
        let subject = model([record("Send the Invoice", at: 100), record("book a table", at: 200)])

        subject.query = "INVOICE"

        #expect(subject.visible.map(\.record.text) == ["Send the Invoice"])
    }

    /// A query of spaces is what a trackpad and a stray thumb produce. Treating it as a real search
    /// empties the window and reads as "your history is gone", which is the one wrong answer here.
    @Test("A blank or whitespace query shows everything")
    func blankQueryShowsEverything() {
        let subject = model([record("one", at: 100), record("two", at: 200)])

        subject.query = "   "

        #expect(subject.visible.count == 2)
    }

    /// Nothing-found and nothing-recorded are different sentences to put in front of someone, and
    /// only one of them means their history was deleted.
    @Test("An empty history is a different state from a search that found nothing")
    func emptyStatesAreDistinct() {
        let empty = model([])
        #expect(empty.emptyMessage == HistoryViewerModel.nothingRecorded)

        let searched = model([record("hello", at: 100)])
        searched.query = "goodbye"
        #expect(searched.visible.isEmpty)
        #expect(searched.emptyMessage == HistoryViewerModel.nothingMatched)

        searched.query = "hello"
        #expect(searched.emptyMessage == nil, "a list with results must not claim to be empty")
    }

    /// Searching the whole record rather than its text would let a year match every dictation from
    /// that year while matching nothing the user ever said.
    ///
    /// The needles matter more than the assertion here. A first version of this test searched for
    /// "1970" and "T00:", and a plant that searched the ENTIRE record sailed through it - neither
    /// string appears in a record's description, so the test was green against the very regression
    /// it was written to catch. These three all appear in some serialisation of the record and in
    /// none of its text.
    @Test("Search reads what was said, not how it was stored")
    func searchDoesNotMatchTheEncoding() {
        let subject = model([record("hello", at: 1_700_000_000, duration: 3)])

        for needle in ["2023", "durationSeconds", "+0000"] {
            subject.query = needle
            #expect(subject.visible.isEmpty, "\(needle) matched the record's storage, not its text")
        }
    }

    /// Found by RENDERING it, not by reading it. The never-recorded state drew a search field over
    /// an empty list, a footer reading "0 dictations" directly under the words "No dictations
    /// recorded yet", and an Open File button for a file that does not exist - `clear()` removes
    /// it. Three controls, none of which could do anything.
    ///
    /// A search that found nothing is the opposite case: the field has to stay, because the user
    /// needs it back to undo the query that emptied the list.
    @Test("A history with nothing in it offers no controls that cannot work")
    func neverRecordedHidesDeadControls() {
        let empty = model([])
        #expect(empty.hasHistory == false)

        let searched = model([record("hello", at: 100)])
        searched.query = "goodbye"
        #expect(searched.visible.isEmpty)
        #expect(searched.hasHistory, "a search that found nothing must keep the search field")
    }

    /// The count and the empty message state the same fact, and the empty message says it better.
    @Test("The footer count goes quiet when a message already says it")
    func countYieldsToTheMessage() {
        let empty = model([])
        #expect(empty.countLabel == nil)

        let subject = model([record("one", at: 100), record("two", at: 200)])
        #expect(subject.countLabel == "2 dictations")

        subject.query = "one"
        #expect(subject.countLabel == "1 match", "a filtered list counts matches, not dictations")

        subject.query = "nothing here"
        #expect(subject.countLabel == nil)
    }

    /// SwiftUI keys per-row `@State` off the row's id, and the copy button's checkmark IS per-row
    /// state. With the id taken from the position in the FILTERED list, that state follows a
    /// POSITION rather than a transcript: copy the top row, type into the search box, and the tick
    /// reappears on whatever is now on top - a different dictation.
    @Test("A transcript keeps its identity when the search changes")
    func identityIsStableAcrossQueries() {
        let subject = model([record("alpha", at: 100), record("beta", at: 200)])

        let unfiltered = subject.visible.first { $0.text == "alpha" }?.id
        subject.query = "alpha"
        let filtered = subject.visible.first { $0.text == "alpha" }?.id

        #expect(unfiltered != nil)
        #expect(unfiltered == filtered,
                "the same transcript changed identity when the list was filtered")
    }

    @Test("Durations read as seconds a person would say")
    func durationsAreReadable() {
        let subject = model([record("a", at: 100, duration: 2.4)])

        #expect(subject.visible.first?.duration == "2.4s")
    }
}
