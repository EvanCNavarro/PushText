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
        store.save(AppSettings(cleanupEnabled: true))

        #expect(store.load().cleanupEnabled == true,
                "saved true did not come back; load is not reading storage")
    }

    @Test("Purge returns the domain to its defaults")
    func purgeResets() {
        let store = makeStore("purge")
        store.save(AppSettings(cleanupEnabled: true))
        #expect(store.load().cleanupEnabled == true)

        store.purge()
        #expect(store.load() == AppSettings.defaults)
    }
}
