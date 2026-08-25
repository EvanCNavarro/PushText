import Testing
import Foundation
@testable import PushTextKit
import PushTextCore

/// #102. A NAMED suite throughout, never `.standard`: a test that writes real user defaults changes
/// the developer's own app behaviour, and would do it on every run.
@Suite("Settings store")
struct SettingsStoreTests {

    private func makeStore(_ label: String) -> UserDefaultsSettingsStore {
        UserDefaultsSettingsStore(suiteName: "dev.ecn.apps.pushtext.test.\(label)")
    }

    @Test("An unwritten domain loads the defaults")
    func absentLoadsDefaults() {
        let store = makeStore("absent")
        store.purge()
        #expect(store.load() == AppSettings.defaults)
        #expect(store.load().cleanupEnabled == false)
    }

    @Test("A saved setting survives a reload")
    func savedValueRoundTrips() {
        let store = makeStore("roundtrip")
        store.purge()
        store.save(AppSettings(cleanupEnabled: true, hotkeyKeyCode: HotkeyBinding.rightOption.keyCode, soundEnabled: true, silenceWhileDictating: false))

        #expect(store.load().cleanupEnabled == true,
                "saved true did not come back; load is not reading storage")
    }

    @Test("Purge returns the domain to its defaults")
    func purgeResets() {
        let store = makeStore("purge")
        store.save(AppSettings(cleanupEnabled: true, hotkeyKeyCode: HotkeyBinding.rightOption.keyCode, soundEnabled: true, silenceWhileDictating: false))
        #expect(store.load().cleanupEnabled == true)

        store.purge()
        #expect(store.load() == AppSettings.defaults)
    }
}

extension SettingsStoreTests {

    /// #104. The hotkey must persist independently of the cleanup flag - a store that writes one key
    /// and drops the other is the "partial write clobbers a sibling" bug TermTile's AppSettings
    /// comment warns about, and it would look like "my hotkey resets itself".
    @Test("The chosen hotkey survives a reload")
    func hotkeyRoundTrips() {
        let store = makeStore("hotkey")
        store.purge()
        #expect(store.load().hotkeyBinding == .rightOption, "default")

        store.save(AppSettings(cleanupEnabled: false,
                               hotkeyKeyCode: HotkeyBinding.rightCommand.keyCode, soundEnabled: true, silenceWhileDictating: false))
        #expect(store.load().hotkeyBinding == .rightCommand,
                "saved hotkey did not come back; load is not reading the key")
    }

    /// Both fields at once, because saving is all-keys: writing the hotkey must not reset cleanup.
    @Test("Saving both settings keeps both")
    func bothFieldsPersist() {
        let store = makeStore("both")
        store.purge()
        store.save(AppSettings(cleanupEnabled: true,
                               hotkeyKeyCode: HotkeyBinding.rightShift.keyCode, soundEnabled: true, silenceWhileDictating: false))
        let loaded = store.load()
        #expect(loaded.cleanupEnabled == true)
        #expect(loaded.hotkeyBinding == .rightShift)
    }

    /// A code we do not offer resolves to the default rather than leaving the app with a binding
    /// whose mask is unknown - which would be a hotkey that can never fire.
    @Test("An unknown keycode falls back to the default binding")
    func unknownCodeFallsBack() {
        let settings = AppSettings(cleanupEnabled: false, hotkeyKeyCode: 0x7FFF, soundEnabled: true, silenceWhileDictating: false)
        #expect(settings.hotkeyBinding == .rightOption)
    }
}
