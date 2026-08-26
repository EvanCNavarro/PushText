import Foundation

/// Which history file this process should read and write (#202).
///
/// The same reasoning as `DefaultsSuite`, for the same reason: the live-refresh fix cannot be shown
/// to work without appending a dictation to an OPEN viewer's file, and doing that against the real
/// store would write into the user's own history to prove a point about the app.
///
/// Production never sets the variable and keeps using Application Support.
public enum HistoryLocation {

    public static let environmentKey = "PUSHTEXT_HISTORY_FILE"

    /// The history file for this process.
    public static func current(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL? {
        guard let path = environment[environmentKey], !path.isEmpty else {
            return JSONLHistoryStore.defaultURL(fileManager: fileManager)
        }
        return URL(fileURLWithPath: path)
    }

    /// True when this process has been pointed away from the user's own history.
    public static var isIsolated: Bool {
        let raw = ProcessInfo.processInfo.environment[environmentKey]
        return !(raw ?? "").isEmpty
    }
}
