import AppKit
import SwiftUI
import PushTextKit

/// Shows the dictionary editor in its own window (#156).
///
/// A window rather than a popover, for the reason `DictionaryEditorView` records: the menu-bar
/// popover dismisses as soon as focus moves, and a text field takes focus.
///
/// One window, reused. A menu item that stacks a new window on every click is the kind of thing
/// nobody notices until there are nine of them.
@MainActor
final class DictionaryEditorWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var model: DictionaryEditorModel?

    func show(store: any DictionaryStore) {
        if let window {
            // Re-read from disk: the file is the user's document and they may have edited it in a
            // text editor since - #154 makes that a normal thing to have done.
            let model = DictionaryEditorModel(store: store)
            self.model = model
            window.contentView = NSHostingView(rootView: DictionaryEditorView(model: model))
            bringForward(window)
            return
        }

        let model = DictionaryEditorModel(store: store)
        self.model = model
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 380),
                              styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Custom Dictionary"
        window.contentView = NSHostingView(rootView: DictionaryEditorView(model: model))
        window.isReleasedWhenClosed = false   // it is reused; releasing it would crash the next open
        window.delegate = self
        window.center()
        self.window = window
        bringForward(window)
    }

    /// An `.accessory` app is not in the Dock and does not become active on its own, so a window it
    /// opens can appear BEHIND whatever the user was working in. Activating explicitly is what puts
    /// it in front - the same lesson the uninstall alert already carries.
    private func bringForward(_ window: NSWindow) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Save once more on close: the view saves as you type, and this is the belt to that braces -
    /// a field still being edited has not fired its change yet.
    func windowWillClose(_ notification: Notification) {
        model?.save()
    }
}
