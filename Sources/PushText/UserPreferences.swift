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

    /// Whether the start and stop cues play (#172). Default ON, matching the tool this was compared
    /// to; the toggle is the point.
    var soundEnabled: Bool {
        didSet { if soundEnabled != oldValue { persist() } }
    }

    /// Whether the Mac's audio is silenced while dictating (#188). Default OFF.
    var silenceWhileDictating: Bool {
        didSet { if silenceWhileDictating != oldValue { persist() } }
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

    /// True while the settings recorder is waiting for a key (#128).
    ///
    /// It exists to SILENCE the tap. The tap is global and does not care that a settings field has
    /// focus, so without this, pressing Right Option to rebind would also start a dictation - the
    /// user would end up recording their own act of changing the setting.
    var isRecordingHotkey: Bool = false {
        didSet {
            guard isRecordingHotkey != oldValue else { return }
            onRecordingChange?(isRecordingHotkey)
        }
    }

    /// Set by the composition root, which owns the tap. Suspends it while `isRecordingHotkey`.
    var onRecordingChange: ((Bool) -> Void)?

    /// Set by the composition root, which owns the tap. A closure rather than a reference, so this
    /// type never needs to know what a `CGEventTapHotkeyMonitor` is.
    var onHotkeyChange: ((HotkeyBinding) -> Void)?

    private let store: (any SettingsStore)?

    init(store: (any SettingsStore)? = nil) {
        self.store = store
        let loaded = store?.load() ?? AppSettings.defaults
        self.cleanupEnabled = loaded.cleanupEnabled
        self.hotkeyBinding = loaded.hotkeyBinding
        self.soundEnabled = loaded.soundEnabled
        self.silenceWhileDictating = loaded.silenceWhileDictating
    }

    /// Writes EVERY field every time. `save` is all-keys, so persisting one field from a partial
    /// value would reset the others - the clobber TermTile's `AppSettings` comment warns about.
    private func persist() {
        store?.save(AppSettings(cleanupEnabled: cleanupEnabled,
                                hotkeyKeyCode: hotkeyBinding.keyCode,
                                soundEnabled: soundEnabled,
                                silenceWhileDictating: silenceWhileDictating))
    }
}
