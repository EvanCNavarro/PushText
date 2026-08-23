import Foundation

/// Whether this process owns its TCC grants or may have INHERITED them from whatever launched it
/// (#44).
///
/// **Why this exists.** macOS attributes TCC responsibility to the launching process. A binary run
/// from a terminal inherits the terminal's Accessibility grant, so `AXIsProcessTrusted()` returns
/// true for a reason that has nothing to do with the app. Every hotkey proof in this repo - #3,
/// #19-#22, and the permanent `test-packaged-app.sh` gate - ran that way and reported
/// `trusted=true`, while the app launched normally had no grant at all. The gate could never have
/// noticed, because a green from an inherited grant is byte-identical to a green from a real one.
///
/// **The signal is the parent process, and it is not a heuristic.** LaunchServices reparents an app
/// to `launchd` (pid 1); a shell-launched process keeps the shell as its parent. Reporting it makes
/// the two runs visibly different instead of identical.
public struct LaunchProvenance: Sendable, Equatable {
    public let parentProcessID: Int32
    public let parentName: String

    public init(parentProcessID: Int32, parentName: String) {
        self.parentProcessID = parentProcessID
        self.parentName = parentName
    }

    /// True when this process's TCC identity is its own.
    ///
    /// Keyed on pid 1, NOT on the name: a process merely called "launchd" is not the system
    /// launchd, and trusting a name would be trivially spoofable by anything that can set its own
    /// process name.
    public var isSelfResponsible: Bool { parentProcessID == 1 }

    public var description: String {
        isSelfResponsible
            ? "launched by launchd - TCC grants are this app's own"
            : "launched by \(parentName) (pid \(parentProcessID)) - TCC grants may be inherited"
    }

    /// Reads the real parent of the running process.
    public static func current() -> LaunchProvenance {
        let parent = getppid()
        return LaunchProvenance(parentProcessID: parent, parentName: name(of: parent))
    }

    /// Best-effort process name for a pid. Empty rather than a guess when it cannot be read - an
    /// invented name in a diagnostic is worse than a blank one, because it reads as fact.
    private static func name(of pid: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: 4 * 1024)
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return "" }
        return String(cString: buffer)
    }
}

// `proc_name` lives in libproc, which has no Swift overlay - declared here rather than pulling in a
// module map for one symbol.
@_silgen_name("proc_name")
private func proc_name(_ pid: Int32, _ buffer: UnsafeMutablePointer<CChar>, _ size: UInt32) -> Int32
