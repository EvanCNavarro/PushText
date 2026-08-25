import Foundation
import PushTextCore

/// Reads the system's Globe-key action (#176).
///
/// READ ONLY. The write side of this preference is private SPI and a crash mid-write leaves the
/// user's Globe key permanently dead - see `GlobeKeyConflict` for the full reasoning.
public enum GlobeKeySetting {

    /// `com.apple.HIToolbox` / `AppleFnUsageType`, or nil when the key has never been written.
    ///
    /// Read through `CFPreferences` rather than `UserDefaults(suiteName:)` because this belongs to
    /// another application's domain, and `UserDefaults` will not see it reliably from inside a
    /// sandboxed or differently-suited process.
    public static func currentAction() -> GlobeKeyAction? {
        let value = CFPreferencesCopyAppValue("AppleFnUsageType" as CFString,
                                              "com.apple.HIToolbox" as CFString)
        guard let number = value as? Int else { return GlobeKeyConflict.conflict(fnUsageType: nil) }
        return GlobeKeyConflict.conflict(fnUsageType: number)
    }
}
