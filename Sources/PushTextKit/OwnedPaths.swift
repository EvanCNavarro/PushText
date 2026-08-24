import Foundation

/// The exact `~/Library`-rooted paths a shipped PushText owns (#150).
///
/// Ported from TermTile's `OwnedPaths`, and the port found a gap that its original does not have:
/// PushText keeps its transcripts under the app NAME, not the bundle id. A list derived only from
/// the bundle id would have missed `Application Support/PushText` entirely and looked complete while
/// leaving every dictation behind.
///
/// EXACT literals, never a glob or a prefix, so a neighbour like
/// `dev.ecn.apps.pushtext.selftest.plist` can never be caught by removing `dev.ecn.apps.pushtext`.
/// The `library` root is INJECTED so tests are deterministic and can never reach the real one.
public struct OwnedPaths: Sendable {
    private let library: URL
    private let bundleID: String
    private let appName: String

    public init(library: URL,
                bundleID: String = "dev.ecn.apps.pushtext",
                appName: String = "PushText") {
        self.library = library
        self.bundleID = bundleID
        self.appName = appName
    }

    /// The owned data paths, folder-granular.
    ///
    /// The `.app` bundle is deliberately absent: a running app cannot delete itself, so listing it
    /// here would produce a failure on every uninstall. The uninstaller trashes it separately.
    ///
    /// Entries that do not exist yet are harmless - `Saved Application State` never appears for an
    /// app with no windows - because the uninstaller existence-checks each one. An owned-but-absent
    /// path is skipped; an omitted-but-later-present path is a silent orphan, which is the worse
    /// direction and the reason this list is longer than what happens to be on disk today.
    public var dataPaths: [URL] {
        [
            // The transcripts and the custom dictionary. Under the app NAME - see the type comment.
            library.appendingPathComponent("Application Support/\(appName)", isDirectory: true),
            library.appendingPathComponent("Preferences/\(bundleID).plist", isDirectory: false),
            library.appendingPathComponent("Caches/\(bundleID)", isDirectory: true),
            library.appendingPathComponent("HTTPStorages/\(bundleID)", isDirectory: true),
            library.appendingPathComponent("HTTPStorages/\(bundleID).binarycookies",
                                           isDirectory: false),
            library.appendingPathComponent("Saved Application State/\(bundleID).savedState",
                                           isDirectory: true)
        ]
    }
}
