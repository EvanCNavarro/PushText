import SwiftUI
import AppKit
import OSLog
import Sparkle
import MacFaceKit
import PushTextKit
import PushTextCore

/// The `···` overflow actions, matching TermTile's set so the two apps behave the same way (#47).
///
/// Kept out of `MenuContent` because each one touches the OS - the updater, the Trash, the app's own
/// lifetime - and a view file that also owns those is a view file nobody can read.
///
/// **`@Observable`, and that is not decoration (#170).** `updateAvailability` is written when
/// Sparkle's passive check comes BACK, which is seconds after the menu has already rendered. Without
/// observation SwiftUI is never told, so the menu-bar icon and the `...` keep drawing the value they
/// had at render time - which is `.unknown`, which is no dot. The update indicator could therefore
/// never appear in real use, on any of the three surfaces, no matter how correct the rest of it was.
///
/// The reason that survived #138's verification is worth keeping: the probe forced
/// `updateAvailability = .available` BEFORE the view was built, so the screenshot showed a dot and
/// the check could only ever pass. A test that sets the value before the render cannot see a
/// missing update notification.
@MainActor
@Observable
final class AppActions {

    /// Sparkle's standard controller. `startingUpdater: true` so the user-driven check works
    /// immediately; automatic checks stay off (`SUEnableAutomaticChecks` is false in Info.plist),
    /// because a dictation utility that phones home on its own schedule is not what was promised.
    ///
    /// The delegate exists to drive the update DOT (#138) - it records what a check found so the
    /// menu can mark itself. It never presents UI; the passive probe uses Sparkle's
    /// non-presenting `checkForUpdateInformation()`, which is the whole reason a mark can appear
    /// without a dialog interrupting the user.
    @ObservationIgnored
    private let updateWatcher = UpdateWatcher()

    @ObservationIgnored
    private lazy var updater = SPUStandardUpdaterController(startingUpdater: true,
                                                            updaterDelegate: updateWatcher,
                                                            userDriverDelegate: nil)

    /// When the last passive check finished, so the policy can decide whether to run another.
    @ObservationIgnored
    private var lastUpdateCheck: Date?

    /// The unattended re-check (#170). Held so it can be invalidated; a repeating timer nobody owns
    /// is a leak with a heartbeat.
    @ObservationIgnored
    private var updateTimer: Timer?

    /// Asks Sparkle what is out there WITHOUT showing anything, so the dot can appear on its own.
    /// A dictation utility that opens a dialog unprompted is not what was promised; a quiet mark is.
    ///
    /// Rate-limited by `UpdateCheckPolicy` (#170), because this is now called from three places -
    /// launch, the timer, and every time the menu opens - and the menu gets opened constantly.
    func refreshUpdateAvailability(now: Date = Date()) {
        guard UpdateCheckPolicy.shouldCheck(lastCompleted: lastUpdateCheck,
                                            now: now,
                                            isChecking: updateAvailability == .checking) else {
            return
        }
        updateWatcher.onChange = { [weak self] availability in
            guard let self else { return }
            self.updateAvailability = availability
            // Stamped on the ANSWER, not on the request: timing from the request would let a check
            // that never came back hold the quiet period open and silence the probe for good.
            self.lastUpdateCheck = Date()
        }
        updateAvailability = .checking
        updater.updater.checkForUpdateInformation()
    }

    /// Starts the unattended re-check (#170).
    ///
    /// Without it the dot could only ever be right about releases that already existed when the app
    /// STARTED - measured on Bobby's machine, where a running 0.3.0 never noticed 0.3.1 published
    /// 26 minutes after it launched. The menu-bar icon is the one mark visible without the user
    /// doing anything, so it needs a cadence rather than an invitation.
    func startUpdateChecking() {
        updateTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: UpdateCheckPolicy.background,
                                         repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshUpdateAvailability() }
        }
        // The menu-bar run loop spends its time in event tracking; a timer in the default mode
        // alone would stall while a menu is open.
        RunLoop.main.add(timer, forMode: .common)
        updateTimer = timer
        refreshUpdateAvailability()
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
    @ObservationIgnored
    private let repairer: any PermissionRepairing

    /// Opens the app's plain-text files. Injected so tests never launch TextEdit.
    @ObservationIgnored
    private let textOpener: PlainTextOpener

    /// One reused editor window - a menu item that stacks a new one per click is the kind of thing
    /// nobody notices until there are nine of them.
    @ObservationIgnored
    private let dictionaryEditor = DictionaryEditorWindow()

    /// Where this app is in its update cycle, which decides whether the menu shows a mark (#138).
    ///
    /// `checking` and `failed` deliberately do not mark: a dot that appears while merely checking
    /// teaches the user to ignore dots. See `MacFaceKit.UpdateAvailability`.
    var updateAvailability: UpdateAvailability = .unknown

    /// Asks macOS for Accessibility trust, which is ALSO what registers this app so the pane has a
    /// row to switch on (#146). Injected so tests never raise a real system dialog.
    @ObservationIgnored
    private let requestAccessibilityTrust: () -> Void
    /// Injected for the same reason: a test must not open System Settings on the developer's Mac.
    @ObservationIgnored
    private let openURL: (URL) -> Void

    /// Whether macOS has already been asked for this permission. The prompt fires ONCE - after the
    /// user answers, Deny included, it never appears again - so a second press must do something
    /// else or it does visibly nothing.
    @ObservationIgnored
    private let hasRequestedTrust: (Permission) -> Bool
    @ObservationIgnored
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

    /// The viewer window, reused across opens (#161).
    @ObservationIgnored
    private let historyViewer = HistoryViewerWindow()

    /// Launch at login (#162). Read through, never cached - see AppActions+LoginItem.
    @ObservationIgnored
    let loginItem: any LoginItemControlling = SMAppServiceLoginItem()

    /// Bumped after a change so the menu re-reads `SMAppService`.
    var loginItemRevision = 0

    /// Where history lives, so the actions below agree on one path.
    private var historyURL: URL? { JSONLHistoryStore.defaultURL() }

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
    /// Opens the editor (#156). #154 made the FILE open in TextEdit, which is not the same as being
    /// editable in any sense a user would call an interface - it handed them JSONL and hoped.
    func editDictionary() {
        guard let url = JSONLDictionaryStore.defaultURL() else { return }
        let store = JSONLDictionaryStore(url: url)
        store.createWithExampleIfMissing()
        dictionaryEditor.show(store: store)
    }

    /// Built from `MenuItemKind` rather than written inline (#164).
    ///
    /// The titles, icons, order and destructive marks are DATA now, and the pairing of a kind with
    /// its effect lives in exactly one `switch`. Both halves are asserted in `MenuWiringTests`,
    /// which the previous inline array made impossible: its closures call `NSAlert.runModal()` and
    /// `NSApplication.terminate`, so a test that pressed one would block or quit the process.
    func menuActions() -> [MenuAction] {
        MenuDispatch.actions(for: MenuItemKind.allCases,
                             // The dot rides on Check for Updates, and MacFaceKit lifts it onto the
                             // `...` button for free - `OverflowMenu` marks itself when any action
                             // is marked (#138). One flag lights two of the three places.
                             attention: { [updateAvailability] kind in
                                 kind == .checkForUpdates && updateAvailability.hasAvailableUpdate
                             },
                             run: { [weak self] kind in
                                 guard let self else { return }
                                 MenuDispatch.perform(kind, on: self)
                             })
    }

    func checkForUpdates() {
        dictationLog.info("update check requested")
        updater.checkForUpdates(nil)
    }

    /// Asks first, because this is irreversible from the user's point of view and the menu item is
    /// one slip away from Quit.
    func confirmUninstall() {
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
            // BEFORE the bundle goes: an uninstall that skips this leaves macOS trying to start
            // an application that is no longer on disk, every login, with nothing to point at
            // (#162).
            if uninstaller.deregisterLoginItem() {
                dictationLog.info("uninstall: login item deregistered")
            }
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

/// Remembers that macOS has been asked for a permission, because it will only ask once (#148).
///
/// Persisted rather than held in memory: the prompt's once-only behaviour survives relaunch, so a
/// flag that did not would send the user back to a dialog macOS will never show again.
enum TrustRequestLatch {
    private static func key(_ permission: Permission) -> String {
        "dev.ecn.apps.pushtext.trustRequested.\(permission)"
    }

    static func wasRequested(_ permission: Permission) -> Bool {
        DefaultsSuite.current.bool(forKey: key(permission))
    }

    static func record(_ permission: Permission) {
        DefaultsSuite.current.set(true, forKey: key(permission))
    }
}
