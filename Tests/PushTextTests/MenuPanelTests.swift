import Testing
@testable import PushText

/// Closing the menu panel before opening a window (#209).
///
/// Only the window-name match is testable here: `dismiss()` reaches into `NSApp.windows` and clicks
/// a real status item, so the behaviour is proven by `scripts/probe-window-layering.sh` instead,
/// which measures window LEVELS on the running app. What this pins is the string the matcher looks
/// for - the piece that, if it silently stopped matching, would bring the bug back with no symptom
/// until someone opened a window over the panel.
@Suite("Menu panel")
struct MenuPanelTests {

    /// The real class name, copied from a running app rather than guessed:
    /// SwiftUI mangles the generic, and matching the whole string would break the moment the wrapped
    /// view type changed.
    @Test("Recognises SwiftUI's mangled panel class")
    func recognisesTheRealName() {
        #expect(MenuPanel.isPanelWindow(className: "_TtGC7SwiftUI18MenuBarExtraWindowVS_7AnyView_"))
    }

    /// The other two windows measured in the same dump. Matching either would make `dismiss()` click
    /// the status item when no panel is open, which OPENS it - the exact opposite of dismissing.
    @Test("Does not match the status bar window or an ordinary window")
    func rejectsTheOthers() {
        #expect(MenuPanel.isPanelWindow(className: "NSStatusBarWindow") == false)
        #expect(MenuPanel.isPanelWindow(className: "NSWindow") == false)
    }

    /// A rename is the failure mode this cannot catch on its own, stated so the next reader knows
    /// the probe is the real gate.
    @Test("A renamed class would not match")
    func aRenameWouldNotMatch() {
        #expect(MenuPanel.isPanelWindow(className: "_TtGC7SwiftUI14MenuBarPanelWindow_") == false)
    }
}
