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

    public init(cleanupEnabled: Bool) {
        self.cleanupEnabled = cleanupEnabled
    }

    public static let defaults = AppSettings(cleanupEnabled: false)
}
