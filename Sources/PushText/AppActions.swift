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
        // RESET, then REGISTER, then OPEN - and the middle step is the one that was missing (#146).
        //
        // Clearing the stale row leaves the Accessibility list with no PushText in it, because that
        // list contains apps which have REQUESTED the permission. Opening the pane at that point
        // shows the user twenty other apps and nothing to switch on. Bobby hit exactly that.
        //
        // Prompting is the registration: it puts a fresh row back, bound to the CURRENT code
        // identity, which is the entire reason the stale one was cleared.
        if advice.repairs, let permission = advice.permission {
            for report in repairer.reset([permission]) where !report.succeeded {
                dictationLog.error("tccutil reset failed exit=\(report.exitCode, privacy: .public)")
            }
        }
        // ONE thing per press, in the order macOS expects (#148).
        //
        // The prompt carries its own "Open System Settings" button, so opening the pane as well is a
        // second copy of an affordance the dialog already provides - Bobby got both at once. And the
        // prompt fires ONCE: after the user answers, Deny included, macOS never shows it again. So a
        // later press has to become the Settings press, or it does visibly nothing.
        if advice.registersByPrompting, let permission = advice.permission,
           !hasRequestedTrust(permission) {
            recordRequestedTrust(permission)
            requestAccessibilityTrust()
            return
        }
        guard let url = advice.settingsURL else { return }
        openURL(url)
    }

    /// Clears this app's stale TCC rows. Injectable so tests never shell out to `tccutil`, which
    /// would destroy the developer's own grants.
    private let repairer: any PermissionRepairing

    /// Opens the app's plain-text files. Injected so tests never launch TextEdit.
    private let textOpener: PlainTextOpener

    /// Where this app is in its update cycle, which decides whether the menu shows a mark (#138).
    ///
    /// `checking` and `failed` deliberately do not mark: a dot that appears while merely checking
    /// teaches the user to ignore dots. See `MacFaceKit.UpdateAvailability`.
    var updateAvailability: UpdateAvailability = .unknown

    /// Asks macOS for Accessibility trust, which is ALSO what registers this app so the pane has a
    /// row to switch on (#146). Injected so tests never raise a real system dialog.
    private let requestAccessibilityTrust: () -> Void
    /// Injected for the same reason: a test must not open System Settings on the developer's Mac.
    private let openURL: (URL) -> Void

    /// Whether macOS has already been asked for this permission. The prompt fires ONCE - after the
    /// user answers, Deny included, it never appears again - so a second press must do something
    /// else or it does visibly nothing.
    private let hasRequestedTrust: (Permission) -> Bool
    private let recordRequestedTrust: (Permission) -> Void

    init(repairer: any PermissionRepairing = TCCPermissionRepairer(),
         requestAccessibilityTrust: @escaping () -> Void = {
             AccessibilityTrust.isTrusted(prompting: true)
         },
         openURL: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) },
         hasRequestedTrust: @escaping (Permission) -> Bool = { TrustRequestLatch.wasRequested($0) },
         recordRequestedTrust: @escaping (Permission) -> Void = { TrustRequestLatch.record($0) },
         textOpener: PlainTextOpener = PlainTextOpener()) {
        self.textOpener = textOpener
        self.repairer = repairer
        self.requestAccessibilityTrust = requestAccessibilityTrust
        self.openURL = openURL
        self.hasRequestedTrust = hasRequestedTrust
        self.recordRequestedTrust = recordRequestedTrust
    }

    /// Where history lives, so the two actions below agree on one path.
    private var historyURL: URL? { JSONLHistoryStore.defaultURL() }

    /// Opens the history file itself rather than a viewer.
    ///
    /// The file IS the feature: plain JSONL the user can read, grep and delete. Building a browser
    /// would put a worse reader in front of a file that every tool on the machine already opens.
    func revealHistory() {
        guard let url = historyURL else { return }
        // Opened rather than revealed (#154). Revealing worked, and then the user double-clicked
        // the file and hit the same no-handler wall - so the menu item did its job and the user
        // still could not read their own transcripts.
        textOpener.open(url)
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
        // NOT NSWorkspace.open(url): `.jsonl` has no handler on macOS - it gets a dynamic UTI - so
        // that produced "There is no application set to open the document" and nothing else (#154).
        textOpener.open(url)
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
            MenuAction(title: "Open History File", systemImage: "clock.arrow.circlepath") { [weak self] in
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
            PushText will quit, and these move to the Trash:

            \u{2022} the app itself
            \u{2022} your dictation history and custom dictionary
            \u{2022} its settings and caches

            Its Microphone and Accessibility entries are cleared too, so nothing is left listed in \
            System Settings.
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

        // ORDER MATTERS, and it cost an hour to learn on 2026-08-24: `tccutil` resolves a bundle id
        // through LaunchServices BEFORE touching TCC, so once the .app is in the Trash the reset
        // returns "No such bundle identifier" and the grants outlive the app. Clear them FIRST.
        if let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first {
            let uninstaller = Uninstaller(library: library, repairer: repairer)
            for report in uninstaller.resetPermissions() where !report.succeeded {
                dictationLog.error("uninstall: reset failed exit=\(report.exitCode, privacy: .public)")
            }
            let data = uninstaller.removeData()
            dictationLog.info("""
                uninstall removed \(data.removed.count, privacy: .public) data paths, \
                \(data.failed.count, privacy: .public) failed
                """)
        }

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

/// Remembers that macOS has been asked for a permission, because it will only ask once (#148).
///
/// Persisted rather than held in memory: the prompt's once-only behaviour survives relaunch, so a
/// flag that did not would send the user back to a dialog macOS will never show again.
enum TrustRequestLatch {
    private static func key(_ permission: Permission) -> String {
        "dev.ecn.apps.pushtext.trustRequested.\(permission)"
    }

    static func wasRequested(_ permission: Permission) -> Bool {
        UserDefaults.standard.bool(forKey: key(permission))
    }

    static func record(_ permission: Permission) {
        UserDefaults.standard.set(true, forKey: key(permission))
    }
}
