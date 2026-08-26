import AppKit
import SwiftUI
import PushTextKit
import PushTextCore

/// The history actions: opening the viewer, revealing the file, deleting the lot.
///
/// Split out of `AppActions` when that file passed 400 lines. They belong together - they are the
/// only actions that share `historyURL`, and every one of them is about the same JSONL file.
extension AppActions {

    /// Where history lives, so the actions below agree on one path.
    private var historyURL: URL? { HistoryLocation.current() }

    /// Opens the history file itself rather than a viewer.
    ///
    /// The file IS the feature: plain JSONL the user can read, grep and delete. Building a browser
    /// would put a worse reader in front of a file that every tool on the machine already opens.
    /// Opens the searchable viewer (#161).
    ///
    /// #154 made the FILE open, which is not the same as being readable: one JSON object per line,
    /// timestamps as ISO strings, and no way to find anything. The dictionary got a real editor in
    /// #156 and history is the surface with more content in it.
    ///
    /// The raw file is still one click away, inside the viewer - it is the user's data in a format
    /// every tool on the machine can open, and that was half the point of choosing JSONL.
    func showHistory() {
        MenuPanel.dismiss()
        guard let url = historyURL else { return }
        historyViewer.show(store: JSONLHistoryStore(url: url)) { [weak self] in
            self?.revealHistory()
        }
    }

    /// Opens the viewer on a KNOWN set of records so each state can be looked at (#161).
    ///
    /// Screenshotting the real store shows whatever this machine happens to hold, which on a fresh
    /// install is nothing at all - so the populated state, the one with all the layout in it, would
    /// never be seen.
    func showHistoryProbe(mode: String) {
        // "live" opens the REAL store rather than a fixture, because the thing being watched is the
        // window noticing a dictation that arrives while it is open (#202). A fixture cannot show
        // that: it is a fixed set of records with no file under it, so it never changes.
        // `PUSHTEXT_HISTORY_FILE` is what keeps that off the user's own history.
        if mode == "live" {
            showHistory()
            print("HISTORY_PROBE window=\(historyViewer.windowNumber ?? 0) mode=live")
            fflush(stdout)
            scheduleProbeAppend()
            scheduleProbeRekey()
            return
        }
        let fixture = HistoryProbeFixture(mode: mode)
        // The highlight only exists while something matches, so the searched states have to be
        // openable too - and the FUZZY one especially, since it is the state where the highlight
        // has to prove it lands on the word actually matched rather than the word typed.
        let query: String
        switch mode {
        case "nomatch": query = "quarterly"
        // Both words in the SAME transcript. "invoice release" was the first attempt and matched
        // nothing, correctly - they live in different dictations and the query is an AND.
        case "match": query = "invoice project"
        case "fuzzy": query = "invoce"
        default: query = ""
        }
        historyViewer.show(store: fixture, query: query) { [weak self] in self?.revealHistory() }
        // Printed rather than discovered: `kCGWindowName` is nil without Screen Recording, so an
        // outside lookup by title finds nothing and reads identically to the window never opening.
        print("HISTORY_PROBE window=\(historyViewer.windowNumber ?? 0) mode=\(mode)")
        fflush(stdout)
    }

    /// Writes one dictation THROUGH the app's own store, a moment after the viewer opens (#202).
    ///
    /// The append has to happen inside the process: what is being verified is the chain from
    /// `JSONLHistoryStore.append` to the open window redrawing, and a shell appending to the file
    /// would skip the notification that carries it - proving nothing about the fix.
    private func scheduleProbeAppend() {
        let environment = ProcessInfo.processInfo.environment
        guard let text = environment["PUSHTEXT_HISTORY_PROBE_APPEND"], !text.isEmpty,
              let url = historyURL else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            JSONLHistoryStore(url: url).append(
                HistoryRecord(text: text, recordedAt: Date(), durationSeconds: 30))
            print("HISTORY_PROBE appended")
            fflush(stdout)
        }
    }

    /// Drives the become-key path (#207): take key away from the viewer, then give it back.
    ///
    /// Both halves are necessary. `windowDidBecomeKey` only fires on a window that BECOMES key, so a
    /// viewer that never lost it would sit there while the delegate never ran - and a probe built
    /// without the thief would report the same green whether the delegate existed or not.
    ///
    /// The thief is a real `NSWindow` because that is what takes key; `orderFrontRegardless`, which
    /// the menu probe uses, deliberately does not, which is why the viewer kept key through every
    /// earlier probe run.
    private func scheduleProbeRekey() {
        let environment = ProcessInfo.processInfo.environment
        guard let raw = environment["PUSHTEXT_HISTORY_PROBE_REKEY"],
              let seconds = Double(raw) else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            let thief = NSWindow(contentRect: NSRect(x: 20, y: 20, width: 160, height: 90),
                                 styleMask: [.titled], backing: .buffered, defer: false)
            thief.title = "key thief (probe)"
            thief.makeKeyAndOrderFront(nil)
            self?.probeKeyThief = thief
            print("HISTORY_PROBE keystolen")
            fflush(stdout)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            // THE CONTROL, sampled the instant before key returns: the file was changed from
            // outside, which posts nothing, so an unkeyed window must still be showing the old
            // count. If this already reads the new number then something else refreshed it and
            // nothing below can be credited to becoming key.
            print("HISTORY_PROBE rows_before_key=\(self?.historyViewer.visibleRowCount ?? -1)")
            self?.historyViewer.makeKey()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                print("HISTORY_PROBE rows_after_key=\(self?.historyViewer.visibleRowCount ?? -1)")
                print("HISTORY_PROBE rekeyed")
                fflush(stdout)
            }
        }
    }

    func revealHistory() {
        MenuPanel.dismiss()
        guard let url = historyURL else { return }
        // Opened rather than revealed (#154). Revealing worked, and then the user double-clicked
        // the file and hit the same no-handler wall - so the menu item did its job and the user
        // still could not read their own transcripts.
        textOpener.open(url)
    }

    /// Deletes every recorded dictation. Irreversible, so it confirms first.
    func clearHistory() {
        MenuPanel.dismiss()
        guard let url = historyURL else { return }
        let alert = NSAlert()
        alert.messageText = "Delete all dictation history?"
        alert.informativeText = "Every transcript PushText has recorded will be removed from "
            + url.path + ". This cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        JSONLHistoryStore(url: url).clear()
    }
}
