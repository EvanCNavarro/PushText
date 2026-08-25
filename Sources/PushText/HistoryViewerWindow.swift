import AppKit
import SwiftUI
import PushTextKit

/// Shows the history viewer in its own window (#161).
///
/// The same shape as `DictionaryEditorWindow`, and for the same two reasons: a popover dismisses
/// when the search field takes focus, and a menu item that stacks a new window on every click is
/// the kind of thing nobody notices until there are nine of them.
@MainActor
final class HistoryViewerWindow: NSObject {
    private var window: NSWindow?
    private var model: HistoryViewerModel?

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
        window.center()
        self.window = window
        bringForward(window)
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
