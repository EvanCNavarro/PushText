import Foundation
import Dispatch
import PushTextCore

/// Clears this app's own stale TCC rows (#136).
///
/// Ported from TermTile's `TCCPermissionRepairer`, and its docstring is the argument: *"This does
/// not grant permission; it only clears TermTile's own old rows so the current signed app can be
/// granted normally in System Settings."*
///
/// **This reverses the conclusion recorded in #6.** That issue declined a repairer, reasoning that
/// resetting deletes the entry so the user must re-ADD the app with `+`, which is more work than
/// toggling an entry already there. That argument assumes toggling WORKS. It does not when the row
/// is stale: TCC binds a grant to the app's code identity, so after a re-sign or an update the
/// listed entry belongs to a build that no longer exists, and toggling it re-grants the OLD one.
/// Clearing it is the only thing that lets the current app be granted at all.
///
/// Observed on 2026-08-24: replacing a locally dev-signed PushText with the Developer ID-signed
/// release left Accessibility asking for a grant the user had already given.
public struct PermissionRepairReport: Equatable, Sendable {
    public let permission: Permission
    public let exitCode: Int32

    public init(permission: Permission, exitCode: Int32) {
        self.permission = permission
        self.exitCode = exitCode
    }

    public var succeeded: Bool { exitCode == 0 }
}

@MainActor
public protocol PermissionRepairing: AnyObject {
    @discardableResult
    func reset(_ permissions: [Permission]) -> [PermissionRepairReport]
}

@MainActor
public final class TCCPermissionRepairer: PermissionRepairing {
    /// Injected so tests can drive this without shelling out - a test that ran the real command
    /// would destroy the developer's own grants.
    public typealias Runner = (_ executable: String, _ arguments: [String]) -> Int32

    private static let processTimeout: DispatchTimeInterval = .seconds(2)
    /// Matches the shell convention, so a hang is distinguishable from a refusal in the report.
    private static let timedOutExitCode: Int32 = 124

    private let bundleID: String
    private let runner: Runner

    public convenience init(bundleID: String = "dev.ecn.apps.pushtext") {
        self.init(bundleID: bundleID, runner: TCCPermissionRepairer.runProcess)
    }

    public init(bundleID: String, runner: @escaping Runner) {
        self.bundleID = bundleID
        self.runner = runner
    }

    /// ALWAYS bundle-scoped. `tccutil reset Accessibility` with no identifier clears the grant for
    /// every app on the machine, so the id is not a nicety - it is the difference between repairing
    /// this app and vandalising someone's Mac.
    @discardableResult
    public func reset(_ permissions: [Permission]) -> [PermissionRepairReport] {
        permissions.map { permission in
            let exitCode = runner("/usr/bin/tccutil",
                                  ["reset", Self.service(for: permission), bundleID])
            return PermissionRepairReport(permission: permission, exitCode: exitCode)
        }
    }

    /// TCC service names, which are NOT the UI labels. PostEvent is its own service despite sharing
    /// a single toggle with Accessibility in System Settings - an app can hold one and not the other.
    private static func service(for permission: Permission) -> String {
        switch permission {
        case .microphone: "Microphone"
        case .accessibility: "Accessibility"
        case .postEvent: "PostEvent"
        }
    }

    private static func runProcess(_ executable: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        let finished = DispatchSemaphore(value: 0)
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.terminationHandler = { _ in finished.signal() }
        do {
            try process.run()
            guard finished.wait(timeout: .now() + processTimeout) == .success else {
                if process.isRunning { process.terminate() }
                return timedOutExitCode
            }
            return process.terminationStatus
        } catch {
            return 127
        }
    }
}
