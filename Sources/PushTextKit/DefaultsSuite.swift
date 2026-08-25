import Foundation

/// Which `UserDefaults` domain this process should use (#185).
///
/// **`HOME` does not isolate preferences, and believing it did cost the user twice.** `cfprefsd`
/// serves the logged-in user's domain regardless of `HOME` and `CFFIXED_USER_HOME`, so a probe run
/// with a redirected home still reads and WRITES the real settings. Measured: a render probe under a
/// scratch home left no plist in that home at all, and changed the real `hotkeyKeyCode`.
///
/// So isolation is explicit. `PUSHTEXT_DEFAULTS_SUITE` names a separate domain; nothing else
/// changes, and production - which never sets it - keeps using the standard one.
public enum DefaultsSuite {

    public static let environmentKey = "PUSHTEXT_DEFAULTS_SUITE"

    /// The suite name for this process, or nil for the user's own domain.
    public static var name: String? {
        let raw = ProcessInfo.processInfo.environment[environmentKey]
        guard let raw, !raw.isEmpty else { return nil }
        return raw
    }

    /// The defaults every part of the app should use.
    ///
    /// `UserDefaults(suiteName:)` returns nil for a name that collides with the standard domain, and
    /// falling back to `.standard` there is correct - it is the same store the caller asked for.
    public static var current: UserDefaults {
        guard let name, let suite = UserDefaults(suiteName: name) else { return .standard }
        return suite
    }

    /// True when this process has been deliberately pointed away from the user's settings.
    public static var isIsolated: Bool { name != nil }
}
