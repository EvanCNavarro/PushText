import AppKit

/// The menu-bar panel `MenuBarExtra(.window)` puts on screen, and closing it (#209).
///
/// **Why anything needs to close it.** Measured on the real panel:
///
/// ```
/// class=_TtGC7SwiftUI18MenuBarExtraWindowVS_7AnyView_  level=101
/// class=NSStatusBarWindow                              level=25
/// class=NSWindow                                       level=0    <- the history viewer
/// ```
///
/// 101 against 0. Every window this app opens from that panel - the history viewer, the dictionary
/// editor, Sparkle's update alert - is BELOW it by window level, so activating the app or calling
/// `makeKeyAndOrderFront` cannot help: those decide key and front WITHIN a level. Bobby hit it twice,
/// once with the update alert (its Install button covered) and once with Dictation History.
///
/// Closing it is also just what a menu does when you pick an item.
enum MenuPanel {

    /// Closes the panel if it is open. Does nothing when it is already closed.
    ///
    /// **Closed the way a person closes it - by clicking the menu-bar icon - and NOT with
    /// `orderOut`.** Ordering the window out was the first fix and it shipped a worse bug than the
    /// one it solved: the panel disappeared correctly, but SwiftUI went on believing it was open, so
    /// the next click on the icon toggled it "closed" and nothing happened. Measured - the panel was
    /// gone at t=6, the icon was clicked at t=9, and no panel came back for the rest of the run.
    /// The menu-bar icon appearing dead is worse than a window in the wrong order.
    ///
    /// Clicking the status item toggles the same state SwiftUI is tracking, so the two cannot drift.
    ///
    /// The visibility check is what makes this safe to call unconditionally: clicking when the panel
    /// is already closed would OPEN it, which is the opposite of dismissing.
    @MainActor
    static func dismiss() {
        guard isPanelOpen else { return }
        guard let button = statusItemButton() else { return }
        button.performClick(nil)
    }

    /// Whether the panel is on screen right now.
    ///
    /// Matched on the class NAME because `MenuBarExtra` is a SwiftUI scene that hands out no window
    /// and no `NSStatusItem` to hold on to. The real name is a mangled generic,
    /// `_TtGC7SwiftUI18MenuBarExtraWindowVS_7AnyView_`, so this matches the readable middle of it -
    /// a change to the wrapped view type must not silently stop this working.
    @MainActor
    private static var isPanelOpen: Bool {
        NSApp.windows.contains { window in
            window.isVisible && isPanelWindow(className: NSStringFromClass(type(of: window)))
        }
    }

    /// Whether a window class name is the `MenuBarExtra` panel.
    ///
    /// Pulled out as a pure function so it can be tested. It is the fragile part: if SwiftUI ever
    /// renames the class, `dismiss()` finds nothing, does nothing, and the layering bug returns in
    /// SILENCE. `scripts/probe-window-layering.sh` is what would actually catch that - this test
    /// only pins the name that was measured.
    static func isPanelWindow(className: String) -> Bool {
        className.contains("MenuBarExtraWindow")
    }

    /// The status item's own button. `DictationHUD` finds the same window the same way.
    @MainActor
    private static func statusItemButton() -> NSButton? {
        for window in NSApp.windows {
            let name = NSStringFromClass(type(of: window))
            guard name.contains("StatusBar") || name.contains("MenuBarExtra") else { continue }
            guard let root = window.contentView, let button = firstButton(in: root) else { continue }
            return button
        }
        return nil
    }

    @MainActor
    private static func firstButton(in view: NSView) -> NSButton? {
        if let button = view as? NSButton { return button }
        for subview in view.subviews {
            if let found = firstButton(in: subview) { return found }
        }
        return nil
    }
}
