import Foundation
import Observation
import PushTextCore
import PushTextKit

/// The user's two choices, and what happens when they change (#102, #103, #104).
///
/// Its own type for the reason `HUDDriver` and `TranscriptFinisher` are: it owns state with its own
/// lifetime, it changes for reasons unrelated to the dictation flow, and `AppModel` had reached
/// swiftlint's file-length limit again. Settings are also the one part of the app a user edits
/// directly, so having them in one readable place is worth more than proximity to the state machine.
@Observable
@MainActor
final class UserPreferences {

    /// Whether on-device cleanup runs. Default OFF because #94 measured a ~3.2 s asset load on half
    /// of all dictations, against 206 ms without it.
    var cleanupEnabled: Bool {
        didSet { if cleanupEnabled != oldValue { persist() } }
    }

    /// Which bare modifier starts a dictation.
    ///
    /// Setting it persists AND re-registers the event tap. A picker that only changed the label
    /// would leave the app listening to the old key while the menu claimed otherwise - the UI
    /// telling a lie about its own state.
    var hotkeyBinding: HotkeyBinding {
        didSet {
            guard hotkeyBinding != oldValue else { return }
            persist()
            onHotkeyChange?(hotkeyBinding)
        }
    }

    /// Set by the composition root, which owns the tap. A closure rather than a reference, so this
    /// type never needs to know what a `CGEventTapHotkeyMonitor` is.
    var onHotkeyChange: ((HotkeyBinding) -> Void)?

    private let store: (any SettingsStore)?

    init(store: (any SettingsStore)? = nil) {
        self.store = store
        let loaded = store?.load() ?? AppSettings.defaults
        self.cleanupEnabled = loaded.cleanupEnabled
        self.hotkeyBinding = loaded.hotkeyBinding
    }

    /// Writes BOTH fields every time. `save` is all-keys, so persisting one field from a partial
    /// value would reset the other - the clobber TermTile's `AppSettings` comment warns about.
    private func persist() {
        store?.save(AppSettings(cleanupEnabled: cleanupEnabled,
                                hotkeyKeyCode: hotkeyBinding.keyCode))
    }
}
