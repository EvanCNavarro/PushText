import Foundation
import PushTextCore

/// Known records for the history viewer probe (#161).
///
/// The viewer has three states that look nothing alike - populated, searched-to-nothing, and never
/// recorded - and on a fresh install the real store is in the third. Rendering against it would
/// mean the state with all the layout in it never gets looked at, which is how #156 shipped a
/// full-width Add Entry button with an external-link arrow on it.
///
/// Lives in the app target rather than the tests because a probe that renders the REAL view has to
/// run inside the real app.
struct HistoryProbeFixture: HistoryReading {
    let mode: String

    func load() -> [HistoryRecord] {
        guard mode != "empty" else { return [] }
        let now = Date(timeIntervalSince1970: 1_787_000_000)
        return [
            record("Push the release once CI is green.", now.addingTimeInterval(-9_000), 2.4),
            // A long one on purpose: wrapping is the thing a fixed-height row gets wrong, and a
            // one-line sample would never show it.
            record("Remind me to ask about the invoice for the second half of the project, and "
                   + "whether they want it split across two months or sent as one.",
                   now.addingTimeInterval(-3_600), 11.8),
            record("New paragraph. That reads better.", now.addingTimeInterval(-600), 1.9),
            record("Book a table for four at seven.", now, 3.1)
        ]
    }

    private func record(_ text: String, _ date: Date, _ duration: TimeInterval) -> HistoryRecord {
        HistoryRecord(text: text, recordedAt: date, durationSeconds: duration)
    }
}
