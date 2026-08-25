import Testing
import Foundation
@testable import PushText
import PushTextKit
import PushTextCore

/// #104. The picker is only honest if changing it re-registers the tap.
@Suite("User preferences")
@MainActor
struct UserPreferencesTests {

    /// Records what was written, so a test can assert persistence without touching real defaults.
    final class SpyStore: SettingsStore, @unchecked Sendable {
        private let lock = NSLock()
        private var stored: AppSettings
        init(_ initial: AppSettings) { stored = initial }
        func load() -> AppSettings { lock.lock(); defer { lock.unlock() }; return stored }
        func save(_ settings: AppSettings) { lock.lock(); stored = settings; lock.unlock() }
        func purge() {}
    }

    @Test("Loading takes the stored hotkey, not the default")
    func loadsStoredHotkey() {
        let store = SpyStore(AppSettings(cleanupEnabled: false,
                                         hotkeyKeyCode: HotkeyBinding.rightControl.keyCode, soundEnabled: true, silenceWhileDictating: false, globeNoticeDismissed: false))
        #expect(UserPreferences(store: store).hotkeyBinding == .rightControl)
    }

    /// THE assertion. Without it the menu would show the new key while the event tap kept listening
    /// to the old one - and every test about persistence would still pass, because persistence is
    /// not the part that breaks.
    @Test("Changing the hotkey re-registers the tap")
    func changeNotifiesTheTapOwner() {
        let prefs = UserPreferences(store: SpyStore(.defaults))
        var rebound: [HotkeyBinding] = []
        prefs.onHotkeyChange = { rebound.append($0) }

        prefs.hotkeyBinding = .rightCommand

        #expect(rebound == [.rightCommand], "the tap owner was never told")
    }

    @Test("Setting the same hotkey again does not re-register")
    func idempotentChange() {
        let prefs = UserPreferences(store: SpyStore(.defaults))
        var count = 0
        prefs.onHotkeyChange = { _ in count += 1 }

        prefs.hotkeyBinding = prefs.hotkeyBinding
        #expect(count == 0, "a no-op assignment tore down and rebuilt the event tap")
    }

    /// Writing one field must not reset the other - `save` is all-keys.
    @Test("Changing the hotkey preserves the cleanup setting")
    func hotkeyChangeKeepsCleanup() {
        let store = SpyStore(AppSettings(cleanupEnabled: true,
                                         hotkeyKeyCode: HotkeyBinding.rightOption.keyCode, soundEnabled: true, silenceWhileDictating: false, globeNoticeDismissed: false))
        let prefs = UserPreferences(store: store)
        prefs.hotkeyBinding = .rightShift

        #expect(store.load().hotkeyBinding == .rightShift)
        #expect(store.load().cleanupEnabled == true, "the hotkey write clobbered cleanup")
    }

    /// The dismissal has to SURVIVE a relaunch (#190). A note that comes back every launch is the
    /// nagging this change removed, and this is the second setting here whose default is `false` but
    /// whose OFF-to-ON transition must persist - the store reads with `object(forKey:) as? Bool` for
    /// exactly that reason.
    @Test("Dismissing the Globe note sticks")
    func globeDismissalPersists() {
        let store = SpyStore(AppSettings.defaults)
        let first = UserPreferences(store: store)
        #expect(first.globeNoticeDismissed == false)

        first.globeNoticeDismissed = true

        let reopened = UserPreferences(store: store)
        #expect(reopened.globeNoticeDismissed, "the note would come back at every launch")
    }
}
