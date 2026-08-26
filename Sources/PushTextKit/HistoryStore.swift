import Foundation
import PushTextCore

public extension Notification.Name {
    /// Posted whenever the history file is written or removed (#202).
    ///
    /// The open viewer listens for this instead of polling. A notification costs nothing while
    /// nobody is dictating, puts the transcript on screen the moment it is written rather than up
    /// to a poll-interval later, and needs no timer to be alive for a window that may sit open for
    /// hours. The app already knows when it appends; asking the filesystem was the long way round.
    static let historyDidChange = Notification.Name("PushTextHistoryDidChange")
}

/// Where dictations are kept.
///
/// A port so `AppModel` never touches the filesystem, matching every other system capability in
/// this target (ADR-0001).
public protocol HistoryStore: Sendable {
    func append(_ record: HistoryRecord)
    func load() -> [HistoryRecord]
    func clear()
}

/// JSONL under Application Support (#10).
///
/// **Append is O(one line) and never rewrites the file.** That is the whole reason for JSONL: a
/// crash mid-write costs the last entry, where an array would have to be read-parse-mutate-rewrite
/// on every utterance and could lose everything.
///
/// **Bounded, and trimmed on read rather than on every append.** Rewriting the file to enforce a
/// cap on each dictation would reintroduce exactly the whole-file write JSONL exists to avoid, and
/// would do it on the latency-sensitive path. The file is allowed to overshoot between launches.
public final class JSONLHistoryStore: HistoryStore, @unchecked Sendable {

    /// Newest kept when trimming. 500 utterances is roughly a month of heavy use and a few hundred
    /// kilobytes - small enough that the read-and-trim is not worth optimising.
    public static let defaultLimit = 500

    /// Compact once the file passes this (#222).
    ///
    /// Measured, not chosen by feel: `load()` costs ~6 ms at 101 KB, ~25 ms at 1 MB and ~88 ms at
    /// 4 MB, because it reads and trims the WHOLE file to show the newest 500. Half a megabyte keeps
    /// that read in single digits while still being large enough that compaction is rare.
    public static let compactionThreshold = 512 * 1024

    private let url: URL
    private let limit: Int
    private let lock = NSLock()

    public init(url: URL, limit: Int = JSONLHistoryStore.defaultLimit) {
        self.url = url
        self.limit = limit
    }

    /// `~/Library/Application Support/PushText/history.jsonl`.
    ///
    /// A plain text file on purpose: the user can read it with `tail`, delete it with `rm`, and see
    /// exactly what the app kept. For an app whose pitch is that nothing leaves the machine, the
    /// store being inspectable is part of the claim rather than an implementation detail.
    public static func defaultURL(fileManager: FileManager = .default) -> URL? {
        guard let base = fileManager.urls(for: .applicationSupportDirectory,
                                          in: .userDomainMask).first else { return nil }
        let directory = base.appendingPathComponent("PushText", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("history.jsonl")
    }

    public func append(_ record: HistoryRecord) {
        guard let line = try? HistoryRecord.encodeLine(record) else { return }
        guard let data = (line + "\n").data(using: .utf8) else { return }
        write(data)
        // In the WRITE path, never in `load()`. The viewer reaches the store through `HistoryReading`
        // precisely so it cannot rewrite the file, and compacting on read would hand it that power
        // through the back door.
        compactIfOversized()
        // Announced AFTER the lock is given up - see `announceChange`.
        announceChange()
    }

    /// Rewrites the file down to `limit` records once it grows past `compactionThreshold` (#222).
    ///
    /// **The check is a `stat`, not a read.** Reading the file on every append to decide whether it
    /// is too big would BE the cost this exists to remove.
    ///
    /// This does not reintroduce the whole-file write JSONL was chosen to avoid: that objection was
    /// to rewriting on EVERY append, and at half a megabyte this runs roughly once per fourteen
    /// hundred dictations. The write is atomic, so a crash during it cannot leave a truncated
    /// history - the old file stays until the new one is complete.
    private func compactIfOversized() {
        lock.lock()
        defer { lock.unlock() }
        guard let stamp = HistoryFileStamp.read(url),
              stamp.size > Self.compactionThreshold,
              let contents = try? String(contentsOf: url, encoding: .utf8) else { return }
        let trimmed = HistoryRecord.trim(contents, toMostRecent: limit)
        guard trimmed.count < contents.count else { return }
        // The trailing newline is load-bearing: `trim` joins WITHOUT one, and the next append would
        // then land on the same line and merge two dictations into one unparseable record.
        guard let data = (trimmed + "\n").data(using: .utf8) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func write(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            // Seek to end and write: the ONE syscall that makes this format worth using.
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }

    public func load() -> [HistoryRecord] {
        lock.lock()
        defer { lock.unlock() }
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return HistoryRecord.decodeFile(HistoryRecord.trim(contents, toMostRecent: limit))
    }

    /// The current version of the file on disk, for a reader that wants to know whether re-reading
    /// would tell it anything new (#202).
    public func changeStamp() -> HistoryFileStamp? {
        lock.lock()
        defer { lock.unlock() }
        return HistoryFileStamp.read(url)
    }

    public func clear() {
        remove()
        announceChange()
    }

    private func remove() {
        lock.lock()
        defer { lock.unlock() }
        try? FileManager.default.removeItem(at: url)
    }

    /// Tells anyone displaying this history that it moved.
    ///
    /// Posted OUTSIDE the lock: an observer that reads the store synchronously would otherwise
    /// deadlock on a lock the posting thread still holds.
    ///
    /// Sent WITH the store as the object, so a listener can narrow to one history if it wants to.
    /// The app has a single history file and its viewer listens for any of them - but the broadcast
    /// being unattributable is how two independent stores become indistinguishable, which showed up
    /// immediately as a test counting four posts where one store had appended once.
    private func announceChange() {
        NotificationCenter.default.post(name: .historyDidChange, object: self)
    }
}
