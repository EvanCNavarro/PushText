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
    /// The delegate exists to drive the update DOT (#138) - it records what a check found so the
    /// menu can mark itself. It never presents UI; the passive probe uses Sparkle's
    /// non-presenting `checkForUpdateInformation()`, which is the whole reason a mark can appear
    /// without a dialog interrupting the user.
    private let updateWatcher = UpdateWatcher()

    private lazy var updater = SPUStandardUpdaterController(startingUpdater: true,
                                                            updaterDelegate: updateWatcher,
                                                            userDriverDelegate: nil)

    /// Asks Sparkle what is out there WITHOUT showing anything, so the dot can appear on its own.
    /// A dictation utility that opens a dialog unprompted is not what was promised; a quiet mark is.
    func refreshUpdateAvailability() {
        updateWatcher.onChange = { [weak self] availability in
            self?.updateAvailability = availability
        }
        updateAvailability = .checking
        updater.updater.checkForUpdateInformation()
    }

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
        // Clear the stale row BEFORE opening Settings, so the pane the user lands on no longer
        // lists a copy of PushText that cannot be switched back on (#136). Reported, not assumed:
        // a refused reset must not leave the user believing they have a clean slate.
        if advice.repairs, let permission = advice.permission {
            for report in repairer.reset([permission]) where !report.succeeded {
                dictationLog.error("tccutil reset failed exit=\(report.exitCode, privacy: .public)")
            }
        }
        guard let url = advice.settingsURL else { return }
        NSWorkspace.shared.open(url)
    }

    /// Clears this app's stale TCC rows. Injectable so tests never shell out to `tccutil`, which
    /// would destroy the developer's own grants.
    private let repairer: any PermissionRepairing

    /// Where this app is in its update cycle, which decides whether the menu shows a mark (#138).
    ///
    /// `checking` and `failed` deliberately do not mark: a dot that appears while merely checking
    /// teaches the user to ignore dots. See `MacFaceKit.UpdateAvailability`.
    var updateAvailability: UpdateAvailability = .unknown

    init(repairer: any PermissionRepairing = TCCPermissionRepairer()) {
        self.repairer = repairer
    }

    /// Where history lives, so the two actions below agree on one path.
    private var historyURL: URL? { JSONLHistoryStore.defaultURL() }

    /// Opens the history file itself rather than a viewer.
    ///
    /// The file IS the feature: plain JSONL the user can read, grep and delete. Building a browser
    /// would put a worse reader in front of a file that every tool on the machine already opens.
    func revealHistory() {
        guard let url = historyURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Deletes every recorded dictation. Irreversible, so it confirms first.
    func clearHistory() {
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

    /// Opens the dictionary file for editing, creating a self-documenting one if it is missing.
    ///
    /// The file IS the editor. A 320pt menu cannot hold a table, and every Mac already has a text
    /// editor that opens `.jsonl` - building a worse one inside the panel would be the wrong trade.
    func editDictionary() {
        guard let url = JSONLDictionaryStore.defaultURL() else { return }
        JSONLDictionaryStore(url: url).createWithExampleIfMissing()
        NSWorkspace.shared.open(url)
    }

    func menuActions() -> [MenuAction] {
        [
            // The dot rides on THIS action, and MacFaceKit lifts it onto the `...` button for
            // free - `OverflowMenu` marks itself when any action is marked (#138). So one flag
            // lights two of the three places TermTile shows an update.
            MenuAction(title: "Check for Updates", systemImage: "arrow.triangle.2.circlepath",
                       attention: updateAvailability.hasAvailableUpdate,
                       attentionAccessibilityHint: "Update available") { [weak self] in
                self?.checkForUpdates()
            },
            MenuAction(title: "Edit Dictionary", systemImage: "character.book.closed") { [weak self] in
                self?.editDictionary()
            },
            MenuAction(title: "Show History File", systemImage: "clock.arrow.circlepath") { [weak self] in
                self?.revealHistory()
            },
            MenuAction(title: "Delete History", systemImage: "trash") { [weak self] in
                self?.clearHistory()
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

/// Records what a Sparkle check found, so the menu can show a mark (#138).
///
/// Separate from `AppActions` because it must be an `NSObject` conforming to `SPUUpdaterDelegate`,
/// and because it has one job: translate Sparkle's callbacks into `UpdateAvailability`.
@MainActor
final class UpdateWatcher: NSObject, SPUUpdaterDelegate {
    var onChange: ((UpdateAvailability) -> Void)?

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        Task { @MainActor in self.onChange?(.available(version: version)) }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        Task { @MainActor in self.onChange?(.unavailable) }
    }

    /// A failed check is NOT "up to date". Reporting it as unavailable would tell the user they are
    /// current when the app has no idea - which is the same shape as a CI summary where zero checks
    /// and all-green render identically.
    nonisolated func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
                             error: (any Error)?) {
        guard error != nil else { return }
        Task { @MainActor in self.onChange?(.failed) }
    }
}
