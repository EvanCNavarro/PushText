import Testing
import Foundation
@testable import PushTextCore

/// The history record and its JSONL encoding (#10).
///
/// JSONL is chosen over one big JSON array for ONE property: appending is a single `write` of one
/// line, and a truncated or corrupt line costs you that line rather than the file. An array has to
/// be read, parsed, mutated and rewritten on every utterance, so a crash mid-write loses
/// everything. These tests exist to hold that property, because it is the only reason the format
/// was picked and it is exactly what a naive implementation quietly gives up.
@Suite("Dictation history")
struct DictationHistoryTests {

    private let stamp = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("A record round-trips through one JSONL line")
    func roundTrip() throws {
        let record = HistoryRecord(text: "Send him the invoice today.",
                                   recordedAt: stamp,
                                   durationSeconds: 2.31)

        let line = try HistoryRecord.encodeLine(record)
        #expect(!line.contains("\n"), "a JSONL line that contains a newline is two records")

        #expect(try HistoryRecord.decodeLine(line) == record)
    }

    /// Multi-line dictation is ordinary - people say "new paragraph". If the encoder let a literal
    /// newline through, one record would be read back as two and the second would be garbage.
    @Test("A transcript containing newlines still occupies exactly one line")
    func newlinesInTextStayOnOneLine() throws {
        let record = HistoryRecord(text: "First line.\nSecond line.\n\nFourth.",
                                   recordedAt: stamp,
                                   durationSeconds: 5)

        let line = try HistoryRecord.encodeLine(record)

        #expect(line.components(separatedBy: "\n").count == 1)
        #expect(try HistoryRecord.decodeLine(line).text == "First line.\nSecond line.\n\nFourth.")
    }

    /// THE property JSONL is for. A corrupt line must cost that line only.
    @Test("A corrupt line is skipped and the rest of the file survives")
    func corruptLineDoesNotLoseTheFile() throws {
        let good1 = try HistoryRecord.encodeLine(HistoryRecord(text: "first", recordedAt: stamp,
                                                               durationSeconds: 1))
        let good2 = try HistoryRecord.encodeLine(HistoryRecord(text: "third", recordedAt: stamp,
                                                               durationSeconds: 3))
        let file = [good1, "{ this is not json", good2].joined(separator: "\n")

        let records = HistoryRecord.decodeFile(file)

        #expect(records.map(\.text) == ["first", "third"])
    }

    /// A crash mid-append leaves a half-written final line. That must not poison the read either.
    @Test("A truncated final line is skipped rather than throwing")
    func truncatedTailIsSkipped() throws {
        let good = try HistoryRecord.encodeLine(HistoryRecord(text: "complete", recordedAt: stamp,
                                                              durationSeconds: 1))
        let torn = String(good.dropLast(12))

        #expect(HistoryRecord.decodeFile(good + "\n" + torn).map(\.text) == ["complete"])
    }

    @Test("Blank lines are ignored rather than counted as records")
    func blankLinesAreIgnored() throws {
        let good = try HistoryRecord.encodeLine(HistoryRecord(text: "only", recordedAt: stamp,
                                                              durationSeconds: 1))

        #expect(HistoryRecord.decodeFile("\n\n" + good + "\n\n").count == 1)
    }

    /// The cap keeps the newest, not the oldest. Trimming from the wrong end silently discards the
    /// entries the user is most likely to want back.
    @Test("Trimming to a cap keeps the most recent entries")
    func trimKeepsNewest() throws {
        let lines = try (1...5).map {
            try HistoryRecord.encodeLine(HistoryRecord(text: "\($0)", recordedAt: stamp,
                                                       durationSeconds: 1))
        }

        let trimmed = HistoryRecord.trim(lines.joined(separator: "\n"), toMostRecent: 3)

        #expect(HistoryRecord.decodeFile(trimmed).map(\.text) == ["3", "4", "5"])
    }
}
