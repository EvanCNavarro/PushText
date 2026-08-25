import AppKit

/// What each menu item does (#164).
///
/// `checkForUpdates()` and `editDictionary()` already existed with these exact names and satisfy the
/// protocol directly - the only change was dropping `private` from the first, since a protocol
/// requirement cannot be. The rest are one-line adapters onto methods whose names describe the
/// mechanism (`showHistory`, `clearHistory`, `confirmUninstall`) rather than the menu item.
///
/// The point is not the indirection, it is that `MenuDispatch.perform` is now the ONE place a kind
/// is paired with an effect, and a swap there is a failing test rather than a title sitting beside
/// the wrong closure in an array literal.
///
/// `quit` does its work inline: terminating is a single call with nothing to arrange, and a private
/// method wrapping it would add a hop that says nothing.
extension AppActions: MenuEffects {
    func viewHistory() { showHistory() }
    func deleteHistory() { clearHistory() }
    func quit() { NSApplication.shared.terminate(nil) }
    func beginUninstall() { confirmUninstall() }
}
