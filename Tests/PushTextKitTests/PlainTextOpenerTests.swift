import Testing
import Foundation
@testable import PushTextKit

/// Opening PushText's plain-text files so a user can actually read and edit them (#154).
///
/// "Edit Dictionary" called `NSWorkspace.open` on a `.jsonl`, and macOS answered with *"There is no
/// application set to open the document"*. Measured: `.jsonl` gets a DYNAMIC UTI
/// (`dyn.ah62d4rv4ge80y65tr30a`) because macOS does not know the extension, so there is no handler
/// for the file itself - while `public.plain-text` resolves to TextEdit.
///
/// So the file has to be opened AS PLAIN TEXT, not as itself.
@Suite("Plain text opener")
struct PlainTextOpenerTests {

    private final class Spy {
        var openedWith: [(URL, URL)] = []
        var revealed: [URL] = []
        var editor: URL?
        var openSucceeds = true
    }

    private func opener(_ spy: Spy) -> PlainTextOpener {
        PlainTextOpener(plainTextEditor: { spy.editor },
                        open: { file, app in spy.openedWith.append((file, app)); return spy.openSucceeds },
                        reveal: { spy.revealed.append($0) })
    }

    private let file = URL(fileURLWithPath: "/tmp/dictionary.jsonl")

    /// THE fix. The file goes to the plain-text editor rather than to whatever claims `.jsonl`,
    /// which is nothing.
    @Test("The file is opened with the default plain-text editor")
    func opensWithTheTextEditor() {
        let spy = Spy()
        spy.editor = URL(fileURLWithPath: "/System/Applications/TextEdit.app")
        opener(spy).open(file)

        #expect(spy.openedWith.count == 1)
        #expect(spy.openedWith.first?.0 == file)
        #expect(spy.openedWith.first?.1.lastPathComponent == "TextEdit.app")
        #expect(spy.revealed.isEmpty, "revealed in Finder even though it opened fine")
    }

    /// With no text editor at all, showing the user where the file lives beats doing nothing.
    @Test("With no editor resolvable it reveals the file in Finder instead")
    func fallsBackToRevealing() {
        let spy = Spy()
        spy.editor = nil
        opener(spy).open(file)

        #expect(spy.openedWith.isEmpty)
        #expect(spy.revealed == [file])
    }

    /// An editor that exists but refuses is the same dead end as no editor. This is the case the old
    /// code hit and did not handle: it called open, open failed, and nothing else happened.
    @Test("An editor that fails to open still leaves the user somewhere useful")
    func fallsBackWhenOpeningFails() {
        let spy = Spy()
        spy.editor = URL(fileURLWithPath: "/System/Applications/TextEdit.app")
        spy.openSucceeds = false
        opener(spy).open(file)

        #expect(spy.openedWith.count == 1, "it should still have tried")
        #expect(spy.revealed == [file], "a failed open left the user with nothing")
    }
}
