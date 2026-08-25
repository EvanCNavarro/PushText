/// The user-changeable settings, as a pure value (#102).
///
/// One field today, deliberately. #102 asked for the store to be built with its FIRST consumer
/// rather than speculatively: a settings type with no reader is an abstraction invented ahead of
/// its use, and the shape of the second setting is unknown until something needs it.
///
/// `init` takes every field with NO default, following TermTile's `AppSettings`, whose comment
/// records why: a partial write must not silently clobber another field back to a default.
public struct AppSettings: Equatable, Sendable {

    /// Whether on-device cleanup runs on each transcript (#103).
    ///
    /// Default OFF, and that default is a MEASUREMENT rather than caution: with cleanup enabled a
    /// ~3.2 s asset load hits half of all dictations (#94), against a 206 ms release-to-text
    /// without it. Some users will happily pay that for tidier text - which is precisely why this
    /// is a setting and not a constant.
    public var cleanupEnabled: Bool

    /// Which bare modifier starts a dictation (#104), stored as its virtual keycode.
    ///
    /// The KEYCODE rather than the whole binding: the device mask and display name are properties of
    /// the key, already recorded once in `HotkeyBinding`, and persisting them would create a second
    /// copy that can disagree with the first. An unknown code resolves back to the default.
    public var hotkeyKeyCode: Int64

    /// Whether the start and stop cues play (#172).
    ///
    /// Default ON, matching the tool Bobby compared it to. The cues are the only feedback that the
    /// hotkey registered when the HUD is behind a full-screen window, and a hold-to-talk key with no
    /// acknowledgement is one you press twice. Anyone who wants silence has a toggle - which is the
    /// half of the request that mattered.
    public var soundEnabled: Bool

    public init(cleanupEnabled: Bool, hotkeyKeyCode: Int64, soundEnabled: Bool) {
        self.cleanupEnabled = cleanupEnabled
        self.hotkeyKeyCode = hotkeyKeyCode
        self.soundEnabled = soundEnabled
    }

    public static let defaults = AppSettings(cleanupEnabled: false,
                                             hotkeyKeyCode: HotkeyBinding.rightOption.keyCode,
                                             soundEnabled: true)

    /// The binding this setting names, or the default when the stored code is not one we offer -
    /// which is what a downgrade, a hand-edited plist, or a removed binding all look like.
    public var hotkeyBinding: HotkeyBinding {
        HotkeyBinding.selectable.first { $0.keyCode == hotkeyKeyCode } ?? .rightOption
    }
}
