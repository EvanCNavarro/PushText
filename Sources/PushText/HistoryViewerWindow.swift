import AppKit
import SwiftUI
import PushTextKit

/// Shows the history viewer in its own window (#161).
///
/// The same shape as `DictionaryEditorWindow`, and for the same two reasons: a popover dismisses
/// when the search field takes focus, and a menu item that stacks a new window on every click is
/// the kind of thing nobody notices until there are nine of them.
@MainActor
final class HistoryViewerWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var model: HistoryViewerModel?
    private var listener: (any NSObjectProtocol)?

    /// `query` is for the render probe only: the searched-to-nothing state cannot be captured
    /// without one, and it is the state most likely to be got wrong.
    func show(store: any HistoryReading, query: String = "",
              onOpenFile: @escaping () -> Void) {
        // Re-read on every open. History grows while the window is closed, and a viewer showing a
        // stale copy of a file the app is actively appending to is worse than no viewer.
        let model = HistoryViewerModel(store: store)
        model.query = query
        self.model = model
        let root = HistoryViewerView(model: model, onOpenFile: onOpenFile)

        startListening()

        if let window {
            window.contentView = NSHostingView(rootView: root)
            bringForward(window)
            return
        }

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
                              styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Dictation History"
        window.contentView = NSHostingView(rootView: root)
        window.isReleasedWhenClosed = false   // it is reused; releasing it would crash the next open
        window.delegate = self
        window.center()
        self.window = window
        bringForward(window)
    }

    /// Re-reads when the store says the history moved (#202).
    ///
    /// Listening rather than polling: no timer has to stay alive for a window that may sit open for
    /// hours, and the transcript appears the moment it is written instead of up to a poll interval
    /// later. The app already knows when it appends.
    ///
    /// A one-second poll was the first design, and it is worth recording WHY the probe that
    /// replaced it looked like it had failed. The timer fired zero times, and the reason was not
    /// the timer: `sample` showed the main thread parked in `[NSAlert runModal]` under Sparkle,
    /// which had put up a modal in an unbundled probe binary. A modal run loop starves default-mode
    /// timers AND the main dispatch queue, so every scheduling mechanism looked equally broken.
    /// The first explanation reached for was App Nap; the stack said otherwise. See
    /// `ProbeActivation.isProbeProcess`, which now keeps Sparkle out of a probe entirely.
    private func startListening() {
        guard listener == nil else { return }
        listener = NotificationCenter.default.addObserver(
            forName: .historyDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.model?.refresh() }
        }
    }

    /// Covers the history file being changed by something OTHER than PushText - the user editing it
    /// in a text editor, which the viewer's own Open File button invites. Nothing posts a
    /// notification for that, and coming back to the window is when it would be noticed anyway.
    func windowDidBecomeKey(_ notification: Notification) {
        model?.refresh()
    }

    func windowWillClose(_ notification: Notification) {
        if let listener { NotificationCenter.default.removeObserver(listener) }
        listener = nil
    }

    /// The window number, so a probe can hand it to `screencapture -l` instead of hunting for it.
    ///
    /// Discovery from outside does not work here: `kCGWindowName` is nil without Screen Recording,
    /// so matching on the title finds nothing and reads exactly like the window failing to open.
    var windowNumber: Int? { window?.windowNumber }

    /// An `.accessory` app does not become active on its own, so a window it opens can appear
    /// BEHIND whatever the user was working in.
    private func bringForward(_ window: NSWindow) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
