import AppKit
import PushTextKit

/// Reproduces #209 - the update alert opening UNDERNEATH the menu-bar panel - against the real
/// `MenuBarExtra` panel.
///
/// **The menu probe cannot show this.** It renders `MenuContent` inside an ordinary `NSWindow`, and
/// an ordinary window does not carry the panel's window level, which is the entire mechanism. A
/// probe that cannot reproduce a defect is not evidence about it in either direction.
///
/// So this drives the real thing: it reports where the status item is once it EXISTS (at launch its
/// frame is still zero-height, which read as "no status item" on the first run), asks for an update
/// check on a timer so the alert arrives while the panel is up, and then samples every window every
/// second - because a single snapshot six seconds after the request showed no Sparkle window at all
/// and could not say whether that meant "never" or "not yet".
enum LayeringProbe {

    static var isRequested: Bool { seconds != nil }

    /// How long after launch to ask for an update check, leaving time to open the panel first.
    private static var seconds: Double? {
        guard let raw = ProcessInfo.processInfo.environment["PUSHTEXT_LAYERING_PROBE"] else {
            return nil
        }
        return Double(raw)
    }

    @MainActor
    static func install(on launchDelegate: LaunchDelegate, actions: AppActions) {
        guard let seconds else { return }
        launchDelegate.onLaunch {
            Task { @MainActor in
                // The PRIMARY screen, not `NSScreen.main`: AppKit's global origin is the bottom left
                // of the primary display and every mouse tool measures from its top left, so this is
                // the height that converts between them. `main` is whichever screen is active, which
                // on a multi-display Mac is a different number and puts the click on another row.
                if let primary = NSScreen.screens.first {
                    print("LAYERING_PROBE primaryHeight=\(Int(primary.frame.height))")
                }
                reportStatusItemWhenReady()
                // Open the panel IN PROCESS. Driving the real mouse to the status item's screen
                // coordinates is what this probe did first, and on a multi-display Mac the item sat
                // at x=-4607; the tool did not honour the negative coordinate and the click landed
                // on the APPLE MENU, with Restart highlighted. Asking the button to click itself has
                // no coordinates to get wrong and cannot land somewhere else.
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { openPanel() }
                DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                    actions.showHistory()
                    print("LAYERING_PROBE historyOpened")
                    fflush(stdout)
                }
                // Click the status item AGAIN afterwards. Ordering SwiftUI's own panel out could
                // leave the scene thinking it is still open, which would show up as the icon going
                // dead - a worse bug than the one being fixed, and invisible unless asked for.
                DispatchQueue.main.asyncAfter(deadline: .now() + seconds + 3) {
                    print("LAYERING_PROBE reopening")
                    openPanel()
                }
                sample(untilSecondsFromNow: seconds + 8)
            }
        }
    }

    /// Polls until the status item has a real frame.
    ///
    /// At launch it exists with a height of ZERO - `MenuBarExtra` fills it in afterwards - and a
    /// height check that runs once therefore reports no status item at all. The first run of this
    /// probe stopped there, correctly calling itself inconclusive rather than guessing a location.
    @MainActor
    private static func reportStatusItemWhenReady(attempt: Int = 0) {
        for window in NSApp.windows {
            let name = NSStringFromClass(type(of: window))
            guard name.contains("StatusBar") || name.contains("MenuBarExtra") else { continue }
            let frame = window.frame
            guard frame.width > 0, frame.height > 0 else { continue }
            print("LAYERING_PROBE statusitem x=\(Int(frame.midX)) y=\(Int(frame.midY)) "
                + "level=\(window.level.rawValue)")
            fflush(stdout)
            return
        }
        guard attempt < 40 else {
            print("LAYERING_PROBE statusitem NEVER APPEARED")
            fflush(stdout)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            reportStatusItemWhenReady(attempt: attempt + 1)
        }
    }

    /// Clicks the status item's own button, which is what opens the panel.
    ///
    /// `MenuBarExtra` does not hand out its `NSStatusItem`, so the button is found the way
    /// `DictationHUD` finds the status window: by class name, then down the view tree.
    @MainActor
    private static func openPanel() {
        for window in NSApp.windows {
            let name = NSStringFromClass(type(of: window))
            guard name.contains("StatusBar") || name.contains("MenuBarExtra") else { continue }
            guard let root = window.contentView, let button = statusButton(in: root) else { continue }
            button.performClick(nil)
            print("LAYERING_PROBE panelClicked")
            fflush(stdout)
            return
        }
        print("LAYERING_PROBE NO STATUS BUTTON FOUND")
        fflush(stdout)
    }

    @MainActor
    private static func statusButton(in view: NSView) -> NSButton? {
        if let button = view as? NSButton { return button }
        for subview in view.subviews {
            if let found = statusButton(in: subview) { return found }
        }
        return nil
    }

    /// Every visible window, once a second, with its LEVEL.
    ///
    /// The level is the whole question: `NSWindow.Level.normal` is 0 and a status or pop-up panel
    /// sits far above it, so two windows can both be visible with no ambiguity about which one wins.
    /// Unlike a screenshot, a number says which - and says it even when the window is off-screen or
    /// on another display.
    @MainActor
    private static func sample(untilSecondsFromNow deadline: Double, elapsed: Double = 0) {
        for window in NSApp.windows where window.isVisible {
            let frame = window.frame
            print("LAYERING_PROBE t=\(Int(elapsed)) class=\(NSStringFromClass(type(of: window))) "
                + "level=\(window.level.rawValue) key=\(window.isKeyWindow) "
                + "frame=\(Int(frame.origin.x)),\(Int(frame.origin.y)),"
                + "\(Int(frame.width)),\(Int(frame.height))")
        }
        fflush(stdout)
        guard elapsed < deadline else {
            print("LAYERING_PROBE done")
            fflush(stdout)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            sample(untilSecondsFromNow: deadline, elapsed: elapsed + 1)
        }
    }
}
