import AppKit
import Foundation
import UniformTypeIdentifiers

/// Opens PushText's plain-text files so a user can actually read and edit them (#154).
///
/// "Edit Dictionary" used to call `NSWorkspace.open` on a `.jsonl` and macOS answered *"There is no
/// application set to open the document"*. Measured rather than guessed: `.jsonl` gets a DYNAMIC UTI
/// - `dyn.ah62d4rv4ge80y65tr30a` - because macOS does not know the extension, so
/// `urlForApplication(toOpen:)` on the file returns nothing. `public.plain-text` resolves to
/// TextEdit on the same machine.
///
/// So the file is opened AS PLAIN TEXT, not as itself. Every dependency is injected because none of
/// this is testable otherwise, and the fallback order is the part worth asserting.
public struct PlainTextOpener {
    private let plainTextEditor: () -> URL?
    private let open: (URL, URL) -> Bool
    private let reveal: (URL) -> Void

    public init(
        plainTextEditor: @escaping () -> URL? = {
            NSWorkspace.shared.urlForApplication(toOpen: UTType.plainText)
        },
        open: @escaping (URL, URL) -> Bool = { file, app in
            // Synchronous answer is what the caller needs in order to fall back, and the async
            // completion form cannot give one without blocking the main actor.
            NSWorkspace.shared.open([file], withApplicationAt: app,
                                    configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
            return true
        },
        reveal: @escaping (URL) -> Void = { NSWorkspace.shared.activateFileViewerSelecting([$0]) }
    ) {
        self.plainTextEditor = plainTextEditor
        self.open = open
        self.reveal = reveal
    }

    /// Opens `file` in the default plain-text editor, falling back to revealing it in Finder.
    ///
    /// Revealing is the fallback rather than nothing at all: with no editor resolvable, showing the
    /// user where the file lives still lets them act. Doing nothing is what the old code did when
    /// its single `open` call failed.
    public func open(_ file: URL) {
        guard let editor = plainTextEditor(), open(file, editor) else {
            reveal(file)
            return
        }
    }
}
