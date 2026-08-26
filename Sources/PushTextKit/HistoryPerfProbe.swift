import Foundation
import PushTextCore

/// What reading the history costs as the file grows (#222).
///
/// **Why this needs a probe rather than a test.** The cost is a curve, not a value, and it depends
/// on real file I/O and the real JSON decoder. A unit test asserting "under N milliseconds" would
/// encode one machine's speed as a requirement and go red on a slower one; what is wanted is the
/// SHAPE - does the cost stay flat, grow linearly, or worse - and whether the number at a realistic
/// size is something a person would feel.
///
/// **What makes the question live.** `load()` reads the WHOLE file, trims to the newest 500 in
/// memory, and decodes. Nothing ever writes the trimmed file back - `clear()` deleting it is the
/// only thing that shrinks it - so the 500 is a DISPLAY cap and the file itself grows without
/// bound. Since #202 an open viewer re-reads on every dictation, so this cost is paid repeatedly
/// rather than once at launch.
///
/// Samples five times per size and reports min/median/max, because a single timing on a machine
/// doing other things is noise, and the minimum is the honest floor.
public enum HistoryPerfProbe {

    public static var isRequested: Bool {
        ProcessInfo.processInfo.environment["PUSHTEXT_HISTORY_PERF_PROBE"] == "1"
    }

    /// Sizes to measure. Defaults span the cap and two futures: 5,000 is a few months of heavy use,
    /// 20,000 is about a year at fifty dictations a day.
    private static var counts: [Int] {
        let raw = ProcessInfo.processInfo.environment["PUSHTEXT_HISTORY_PERF_COUNTS"]
            ?? "23,500,5000,20000"
        return raw.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }

    public static func runAndExit() -> Never {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pushtext-history-perf-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        guard !counts.isEmpty else {
            print("HISTORY_PERF no counts given - inconclusive")
            exit(1)
        }

        for count in counts {
            let url = directory.appendingPathComponent("history-\(count).jsonl")
            guard let bytes = write(count: count, to: url) else {
                print("HISTORY_PERF FAILED to build a \(count)-record file")
                exit(1)
            }
            let store = JSONLHistoryStore(url: url)

            // The cheap check the viewer makes on every notification before deciding to re-read.
            let stamps = sample { _ = store.changeStamp() }
            // The expensive one: read, trim, decode.
            var loaded = 0
            let loads = sample { loaded = store.load().count }

            // A positive count first: a load that returned nothing would time beautifully and mean
            // nothing at all.
            guard loaded > 0 else {
                print("HISTORY_PERF FAILED count=\(count) decoded 0 records - timing is meaningless")
                exit(1)
            }

            print("HISTORY_PERF count=\(count) bytes=\(bytes) decoded=\(loaded)"
                + " stamp_ms=\(ms(stamps))"
                + " load_ms=\(ms(loads))")
            fflush(stdout)
        }
        appendRun(in: directory)
        print("HISTORY_PERF done")
        exit(0)
    }

    /// The measurement that can actually see the fix.
    ///
    /// The sizes above write the file DIRECTLY and never call `append()`, so compaction never fires
    /// and the numbers are identical before and after - a perfectly good read-cost curve that proves
    /// nothing about bounding. This drives the real write path instead: dictate `count` times and
    /// report what the file grows to.
    private static func appendRun(in directory: URL) {
        let count = Int(ProcessInfo.processInfo
            .environment["PUSHTEXT_HISTORY_PERF_APPENDS"] ?? "3000") ?? 3000
        guard count > 0 else { return }
        let url = directory.appendingPathComponent("append-run.jsonl")
        let store = JSONLHistoryStore(url: url)
        let transcript = "This is roughly what one dictation looks like when somebody speaks a "
            + "sentence or two into the microphone and lets go of the key."

        var unbounded = 0
        for index in 0..<count {
            let record = HistoryRecord(text: "\(index). \(transcript)",
                                       recordedAt: Date(timeIntervalSince1970: Double(index)),
                                       durationSeconds: 4.2)
            if let line = try? HistoryRecord.encodeLine(record) { unbounded += line.utf8.count + 1 }
            store.append(record)
        }

        let bytes = HistoryFileStamp.read(url)?.size ?? -1
        let loads = sample { _ = store.load() }
        let decoded = store.load().count
        // `unbounded` is what the file WOULD be with no compaction - the counterfactual, so the
        // saving is a number rather than an adjective.
        print("HISTORY_PERF appends=\(count) bytes=\(bytes) would_be=\(unbounded) "
            + "decoded=\(decoded) load_ms=\(ms(loads))")
        fflush(stdout)
    }

    /// Five timings of `body`, in seconds.
    private static func sample(_ body: () -> Void) -> [Double] {
        (0..<5).map { _ in
            let start = DispatchTime.now().uptimeNanoseconds
            body()
            return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
        }
    }

    private static func ms(_ samples: [Double]) -> String {
        let sorted = samples.sorted()
        let format = { (value: Double) in String(format: "%.2f", value * 1000) }
        return "min=\(format(sorted[0])) med=\(format(sorted[sorted.count / 2])) "
            + "max=\(format(sorted[sorted.count - 1]))"
    }

    /// Builds a file of `count` records through the REAL encoder, so the bytes measured are the
    /// bytes the app would have written.
    private static func write(count: Int, to url: URL) -> Int? {
        var text = ""
        // Representative rather than minimal: a one-word transcript would understate the decode by
        // making every record tiny. This is close to the length of a real dictation.
        let transcript = "This is roughly what one dictation looks like when somebody speaks a "
            + "sentence or two into the microphone and lets go of the key."
        for index in 0..<count {
            let record = HistoryRecord(text: "\(index). \(transcript)",
                                       recordedAt: Date(timeIntervalSince1970: Double(index)),
                                       durationSeconds: 4.2)
            guard let line = try? HistoryRecord.encodeLine(record) else { return nil }
            text += line + "\n"
        }
        guard let data = text.data(using: .utf8), (try? data.write(to: url)) != nil else {
            return nil
        }
        return data.count
    }
}
