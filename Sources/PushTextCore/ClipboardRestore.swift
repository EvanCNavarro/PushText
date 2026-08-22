import Foundation

/// Whether it is safe to put the user's clipboard back after a paste-based injection.
///
/// Injection works by writing text to the pasteboard, sending Command-V, then restoring what was
/// there before. The restore is the dangerous half: between our paste and our restore, ANY other
/// process may have written to the pasteboard — a clipboard manager, another app, the user pressing
/// Command-C. Restoring blindly would silently destroy whatever they just copied.
///
/// `NSPasteboard.changeCount` increments on every write by anyone, so "is the last write still
/// ours?" is answerable exactly. Pure, so the decision is testable without a pasteboard.
public enum ClipboardRestore {

    public enum Decision: Equatable, Sendable {
        /// We are still the last writer; restoring cannot clobber anyone.
        case restore
        /// Someone else wrote after us. Leave their content alone — losing our own restore is a
        /// far smaller harm than eating the user's copy.
        case skipForeignWrite
    }

    /// - Parameters:
    ///   - changeCountAfterOurWrite: `changeCount` observed immediately after we wrote the text.
    ///   - currentChangeCount: `changeCount` now, just before restoring.
    public static func decide(changeCountAfterOurWrite: Int, currentChangeCount: Int) -> Decision {
        currentChangeCount == changeCountAfterOurWrite ? .restore : .skipForeignWrite
    }
}
