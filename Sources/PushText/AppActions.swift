import SwiftUI
import AppKit
import OSLog
import Sparkle
import MacFaceKit
import PushTextKit

/// The `···` overflow actions, matching TermTile's set so the two apps behave the same way (#47).
///
/// Kept out of `MenuContent` because each one touches the OS - the updater, the Trash, the app's own
/// lifetime - and a view file that also owns those is a view file nobody can read.
@MainActor
final class AppActions {

    /// Sparkle's standard controller. `startingUpdater: true` so the user-driven check works
    /// immediately; automatic checks stay off (`SUEnableAutomaticChecks` is false in Info.plist),
    /// because a dictation utility that phones home on its own schedule is not what was promised.
    ///
    /// Until #17 lands there is no published appcast and no `SUPublicEDKey`, so a check reports "no
    /// update" or a feed error rather than finding something. That is the honest pre-release state,
    /// and wiring it now means the menu item works the moment the first release exists.
    private let updater = SPUStandardUpdaterController(startingUpdater: true,
                                                       updaterDelegate: nil,
                                                       userDriverDelegate: nil)

    /// Acts on a permission row: prompt if the app can, otherwise open the right Settings pane.
    ///
    /// The pane is opened rather than described because Privacy panes are several clicks deep and
    /// naming a path is not help. Verified on macOS 26.6.2: opening the Accessibility anchor lands
    /// on a window titled "Accessibility" - the research called that anchor's survival on Tahoe its
    /// single highest-risk assumption (docs/research/04), so it is measured rather than trusted.
    func resolvePermission(_ advice: PermissionAdvice) {
        if advice.canPromptInApp {
            Task { _ = await AVAudioEngineCapture.requestMicrophoneAccess() }
            return
        }
        guard let url = advice.settingsURL else { return }
        NSWorkspace.shared.open(url)
    }

    func menuActions() -> [MenuAction] {
        [
            MenuAction(title: "Check for Updates", systemImage: "arrow.triangle.2.circlepath") { [weak self] in
                self?.checkForUpdates()
            },
            MenuAction(title: "Quit PushText", systemImage: "power") {
                NSApplication.shared.terminate(nil)
            },
            MenuAction(title: "Uninstall PushText...", systemImage: "trash", destructive: true) { [weak self] in
                self?.confirmUninstall()
            }
        ]
    }

    private func checkForUpdates() {
        dictationLog.info("update check requested")
        updater.checkForUpdates(nil)
    }

    /// Asks first, because this is irreversible from the user's point of view and the menu item is
    /// one slip away from Quit.
    private func confirmUninstall() {
        let alert = NSAlert()
        alert.messageText = "Uninstall PushText?"
        alert.informativeText = """
            PushText will be moved to the Trash and will quit.

            macOS keeps its Microphone and Accessibility permissions until you remove them yourself \
            in System Settings > Privacy & Security - no app can revoke its own grants.
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")

        // A background-only app has no window to attach a sheet to, so this is a modal panel. It has
        // to be brought forward explicitly or it opens behind whatever the user was working in.
        NSApplication.shared.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else {
            dictationLog.info("uninstall cancelled")
            return
        }
        uninstall()
    }

    private func uninstall() {
        let bundleURL = Bundle.main.bundleURL
        dictationLog.info("uninstalling from \(bundleURL.path, privacy: .public)")

        NSWorkspace.shared.recycle([bundleURL]) { _, error in
            Task { @MainActor in
                if let error {
                    dictationLog.error("uninstall FAILED: \(String(describing: error), privacy: .public)")
                    let failure = NSAlert()
                    failure.messageText = "Could not move PushText to the Trash"
                    failure.informativeText = error.localizedDescription
                    failure.runModal()
                    return
                }
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
