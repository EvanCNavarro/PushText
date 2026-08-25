import Foundation
import MacFaceKit

/// The overflow menu as DATA rather than as a list of closures (#164).
///
/// **Why this exists.** `menuActions()` used to build `[MenuAction]` inline, each with a title and a
/// closure written side by side. Everything those closures CALL was covered by tests; the
/// association between a title and its effect was covered by nothing. Pointing "Delete History" at
/// `confirmUninstall()` would have passed `swift test`, `swiftlint`, all eleven `.engine/checks` and
/// the packaged smoke - and two of the six items are destructive while a third quits silently.
///
/// The closures could not be tested directly, and that is the whole difficulty: they call
/// `NSAlert.runModal()`, `NSWorkspace` and `NSApplication.terminate`, so invoking one in a test
/// either blocks forever or genuinely quits the process. Making the pairing DATA moves it somewhere
/// a test can look without performing it.
enum MenuItemKind: CaseIterable, Equatable, Sendable {
    case checkForUpdates
    case editDictionary
    case viewHistory
    case deleteHistory
    case quit
    case uninstall

    var title: String {
        switch self {
        case .checkForUpdates: return "Check for Updates"
        case .editDictionary: return "Edit Dictionary"
        case .viewHistory: return "View History"
        case .deleteHistory: return "Delete History"
        case .quit: return "Quit PushText"
        case .uninstall: return "Uninstall PushText..."
        }
    }

    var systemImage: String {
        switch self {
        case .checkForUpdates: return "arrow.triangle.2.circlepath"
        case .editDictionary: return "character.book.closed"
        case .viewHistory: return "clock.arrow.circlepath"
        case .deleteHistory: return "trash"
        case .quit: return "power"
        case .uninstall: return "trash"
        }
    }

    /// Drives the red styling. Uninstall alone: a Quit that looked destructive would train the user
    /// to ignore the colour, which is worse than not colouring anything.
    var destructive: Bool { self == .uninstall }
}

/// What each menu item actually does. One method per kind, so a swap is a compile error rather than
/// a silent mis-wiring.
@MainActor
protocol MenuEffects: AnyObject {
    func checkForUpdates()
    func editDictionary()
    func viewHistory()
    func deleteHistory()
    func quit()
    /// NAMED `beginUninstall`, not `uninstall`. `AppActions` already has a private `uninstall()`
    /// that trashes the app IMMEDIATELY, and `confirmUninstall()` is the one that asks first - so a
    /// requirement called `uninstall()` can bind to the non-confirming path and the menu item would
    /// skip its own confirmation. That is precisely the mis-wiring this whole change exists to make
    /// impossible, and it appeared while writing it.
    func beginUninstall()
}

/// Turns kinds into `MenuAction`s, and kinds into effects. The two halves are separate so both can
/// be asserted without AppKit.
@MainActor
enum MenuDispatch {

    /// The ONLY place a kind is paired with its effect.
    static func perform(_ kind: MenuItemKind, on effects: any MenuEffects) {
        switch kind {
        case .checkForUpdates: effects.checkForUpdates()
        case .editDictionary: effects.editDictionary()
        case .viewHistory: effects.viewHistory()
        case .deleteHistory: effects.deleteHistory()
        case .quit: effects.quit()
        case .uninstall: effects.beginUninstall()
        }
    }

    /// Builds the menu. `attention` and `run` are injected so a test can watch both without an
    /// updater or a live app.
    static func actions(for kinds: [MenuItemKind],
                        attention: (MenuItemKind) -> Bool,
                        run: @escaping (MenuItemKind) -> Void) -> [MenuAction] {
        kinds.map { kind in
            MenuAction(title: kind.title,
                       systemImage: kind.systemImage,
                       destructive: kind.destructive,
                       attention: attention(kind),
                       attentionAccessibilityHint: kind == .checkForUpdates ? "Update available" : nil) {
                run(kind)
            }
        }
    }
}
