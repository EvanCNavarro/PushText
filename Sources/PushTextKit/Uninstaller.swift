import AppKit
import Foundation
import PushTextCore

/// Removing everything a shipped PushText left behind (#150).
///
/// Uninstall used to trash the app bundle and stop, while telling the user "PushText will be moved
/// to the Trash". True, and an incomplete account: 80 dictation transcripts, the preferences, the
/// caches and Sparkle's network storage all survived. For an app whose pitch is that nothing leaves
/// this machine, leaving the transcripts after the user asked for it gone is a privacy defect.
///
/// Ported in shape from TermTile's `Uninstaller`. The library root and the repairer are injected so
/// tests exercise real filesystem work without ever pointing at `~/Library`.
@MainActor
public struct Uninstaller {
    public struct DataOutcome: Sendable {
        public let removed: [URL]
        public let failed: [URL]
    }

    private let library: URL
    private let repairer: any PermissionRepairing
    private let fileManager: FileManager
    private let trash: (URL) throws -> Void
    private let loginItem: any LoginItemControlling

    public init(library: URL,
                repairer: any PermissionRepairing,
                fileManager: FileManager = .default,
                loginItem: any LoginItemControlling = SMAppServiceLoginItem(),
                trash: @escaping (URL) throws -> Void = { url in
                    var resulting: NSURL?
                    try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
                }) {
        self.library = library
        self.repairer = repairer
        self.fileManager = fileManager
        self.trash = trash
        self.loginItem = loginItem
    }

    /// Takes PushText out of the user's login items (#162).
    ///
    /// Uninstall was correct before this ONLY because there was nothing to deregister. The moment
    /// launch-at-login shipped, an uninstall that skipped this would leave macOS trying to start an
    /// application that is no longer there - every login, forever, with the app gone and nothing to
    /// point at. The backlog flagged it as a DEPENDENCY of #162 for exactly that reason.
    ///
    /// Returns whether anything had to be done, so the caller can log it. Failure is reported rather
    /// than thrown: an uninstall that aborts halfway because a login item would not deregister is
    /// worse than one that finishes and says so.
    @discardableResult
    public func deregisterLoginItem() -> Bool {
        guard loginItem.state != .disabled else { return false }
        do {
            try loginItem.disable()
            return true
        } catch {
            return false
        }
    }

    /// Moves every owned path to the Trash, skipping the ones that were never created.
    ///
    /// TRASH rather than delete: an uninstall the user regrets is recoverable, and the transcripts
    /// are the kind of thing someone might want back ten minutes later. An absent path is SKIPPED
    /// rather than failed - `Saved Application State` never exists for an app with no windows, and
    /// a warning nobody can act on is a warning nobody reads.
    public func removeData() -> DataOutcome {
        var removed: [URL] = []
        var failed: [URL] = []
        for url in OwnedPaths(library: library).dataPaths {
            guard fileManager.fileExists(atPath: url.path) else { continue }
            do {
                try trash(url)
                removed.append(url)
            } catch {
                failed.append(url)
            }
        }
        return DataOutcome(removed: removed, failed: failed)
    }

    /// Clears this app's own TCC rows, so an uninstall does not leave stale Accessibility and
    /// Microphone entries behind for a bundle that no longer exists.
    ///
    /// The old alert said "no app can revoke its own grants". That stopped being true when the
    /// repairer landed (#136); saying it anyway would be telling the user to go and do something the
    /// app has already done.
    @discardableResult
    public func resetPermissions() -> [PermissionRepairReport] {
        repairer.reset(Permission.allCases)
    }
}
