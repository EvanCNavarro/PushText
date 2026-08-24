import Foundation
import PushTextCore

/// The persistence port for `AppSettings` (#102), following TermTile's `SettingsStore`.
///
/// Synchronous by design: a settings read is a plist lookup, not I/O worth an `async` seam.
public protocol SettingsStore: Sendable {
    /// The persisted settings, with `AppSettings.defaults` substituted PER KEY for anything never
    /// written - so a partially written domain still loads sane values.
    func load() -> AppSettings
    func save(_ settings: AppSettings)
    /// Remove the entire persisted domain. Lives on the persistence authority so "how we own our
    /// defaults" has one home.
    func purge()
}

/// The production store, backed by `UserDefaults`.
///
/// Holds only the `suiteName` (a `Sendable` `String?`) and resolves `UserDefaults` per call:
/// `UserDefaults` is not `Sendable`, so a stored reference would break this type's conformance
/// under Swift 6 strict concurrency. `nil` suite means `.standard`; tests inject a named one.
public struct UserDefaultsSettingsStore: SettingsStore {

    private enum Key {
        static let cleanupEnabled = "cleanupEnabled"
        static let hotkeyKeyCode = "hotkeyKeyCode"
    }

    private let suiteName: String?

    public init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    /// Never `UserDefaults(suiteName: nil)`, which Apple documents as misuse.
    private var defaults: UserDefaults {
        suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    /// `object(forKey:) as? Bool`, NOT `bool(forKey:)`: the latter returns `false` for an absent
    /// key and for a stored `false` alike, so it cannot fall back per-key.
    ///
    /// **That distinction is invisible today** - the only setting defaults to `false`, so both
    /// spellings behave identically. It is written correctly now because the first setting whose
    /// default is `true` would otherwise be silently unable to persist an OFF, and that bug reads
    /// as "the toggle does not stick" long after this file was last opened.
    public func load() -> AppSettings {
        let stored = defaults
        let fallback = AppSettings.defaults
        return AppSettings(
            cleanupEnabled: stored.object(forKey: Key.cleanupEnabled) as? Bool
                ?? fallback.cleanupEnabled,
            hotkeyKeyCode: (stored.object(forKey: Key.hotkeyKeyCode) as? NSNumber)?.int64Value
                ?? fallback.hotkeyKeyCode)
    }

    public func save(_ settings: AppSettings) {
        defaults.set(settings.cleanupEnabled, forKey: Key.cleanupEnabled)
        defaults.set(NSNumber(value: settings.hotkeyKeyCode), forKey: Key.hotkeyKeyCode)
    }

    public func purge() {
        suiteName.map { defaults.removePersistentDomain(forName: $0) }
    }
}
