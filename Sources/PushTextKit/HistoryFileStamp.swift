import Foundation

/// A cheap identity for "which version of the history file is on disk" (#202).
///
/// The viewer refreshes while it is open, and the alternative was to decode up to five hundred JSON
/// lines on every tick to find out whether anything had changed. This is one `stat` instead, and
/// the decode happens only when the answer is yes.
///
/// **All three fields, and none of them is redundant.** `size` misses a rewrite that happens to land
/// on the same length. `modified` alone would too, and dictations can land inside one timestamp's
/// resolution. `inode` is the one that catches Delete History followed by a new dictation: `clear()`
/// REMOVES the file and the next append recreates it, so a same-size, same-second recreation is a
/// completely different file that the first two fields would call unchanged.
public struct HistoryFileStamp: Equatable, Sendable {
    public let size: Int
    public let modified: Date
    public let inode: UInt64

    public init(size: Int, modified: Date, inode: UInt64) {
        self.size = size
        self.modified = modified
        self.inode = inode
    }

    /// `nil` when there is no file - which is a real state, not an error: `clear()` deletes it, and
    /// a fresh install has never had one. Absent and present are different stamps, so the viewer
    /// notices a history being deleted out from under it.
    public static func read(_ url: URL, fileManager: FileManager = .default) -> HistoryFileStamp? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else { return nil }
        guard let size = attributes[.size] as? Int,
              let modified = attributes[.modificationDate] as? Date,
              let inode = attributes[.systemFileNumber] as? UInt64 else { return nil }
        return HistoryFileStamp(size: size, modified: modified, inode: inode)
    }
}
