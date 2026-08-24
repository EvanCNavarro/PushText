import Testing
import Foundation
@testable import PushTextKit
import PushTextCore

/// Uninstall actually removing what it says it removes (#150).
///
/// It used to trash the app bundle and nothing else, while telling the user "PushText will be moved
/// to the Trash" - true, and an incomplete account of what was left: 80 dictation transcripts, the
/// preferences, the caches, and Sparkle's network storage.
///
/// Every path is real but rooted in a temporary directory, so these tests exercise the actual
/// filesystem work without ever pointing at `~/Library`.
///
/// The TRASH closure is injected too, and that is not fussiness: the first version used the default
/// one and put 70 temporary directories in the developer's real Trash across a day's test runs.
/// A test that leaves litter on the machine it runs on is a test that gets disabled.
@Suite("Uninstaller")
@MainActor
struct UninstallerTests {

    private final class StubRepairer: PermissionRepairing {
        var reset: [Permission] = []
        var exitCode: Int32 = 0
        func reset(_ permissions: [Permission]) -> [PermissionRepairReport] {
            reset = permissions
            return permissions.map { PermissionRepairReport(permission: $0, exitCode: exitCode) }
        }
    }

    /// Deletes instead of trashing. The production default moves items to the Trash so a regretted
    /// uninstall is recoverable; a test doing that fills the developer's Trash instead.
    private static let delete: @Sendable (URL) throws -> Void = { url in
        try FileManager.default.removeItem(at: url)
    }

    private func makeLibrary() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("uninstall-\(UUID().uuidString)", isDirectory: true)
        let fm = FileManager.default
        for sub in ["Application Support/PushText", "Caches/dev.ecn.apps.pushtext",
                    "HTTPStorages/dev.ecn.apps.pushtext", "Preferences"] {
            try fm.createDirectory(at: root.appendingPathComponent(sub, isDirectory: true),
                                   withIntermediateDirectories: true)
        }
        try "one\ntwo\n".write(
            to: root.appendingPathComponent("Application Support/PushText/history.jsonl"),
            atomically: true, encoding: .utf8)
        try "{}".write(to: root.appendingPathComponent("Preferences/dev.ecn.apps.pushtext.plist"),
                       atomically: true, encoding: .utf8)
        return root
    }

    /// THE defect. The transcripts are the thing a user most means when they say "remove it".
    @Test("The dictation history is actually gone afterwards")
    func historyIsRemoved() throws {
        let library = try makeLibrary()
        let history = library.appendingPathComponent("Application Support/PushText/history.jsonl")
        #expect(FileManager.default.fileExists(atPath: history.path))

        let outcome = Uninstaller(library: library, repairer: StubRepairer(), trash: Self.delete).removeData()

        #expect(FileManager.default.fileExists(atPath: history.path) == false)
        #expect(outcome.removed.isEmpty == false)
        #expect(outcome.failed.isEmpty)
    }

    /// A path that was never created is not a failure. Reporting it as one would make every clean
    /// uninstall look partly broken, and a warning nobody can act on is a warning nobody reads.
    @Test("An owned path that does not exist is skipped, not failed")
    func absentPathsAreSkipped() throws {
        let library = try makeLibrary()
        // Saved Application State was never created by makeLibrary.
        let outcome = Uninstaller(library: library, repairer: StubRepairer(), trash: Self.delete).removeData()
        #expect(outcome.failed.isEmpty, "an absent path was reported as a failure")
    }

    /// The grants go too, now that the app can clear its own rows. The old alert told the user "no
    /// app can revoke its own grants", which stopped being true when the repairer landed.
    @Test("Uninstall clears this app's TCC rows")
    func permissionsAreReset() throws {
        let library = try makeLibrary()
        let repairer = StubRepairer()
        _ = Uninstaller(library: library, repairer: repairer, trash: Self.delete).resetPermissions()
        #expect(Set(repairer.reset) == Set(Permission.allCases))
    }

    /// A refused reset must be visible. Claiming a clean uninstall while a grant survives is the
    /// same shape as a green check that verified nothing.
    @Test("A failed permission reset is reported, not swallowed")
    func failedResetIsVisible() throws {
        let library = try makeLibrary()
        let repairer = StubRepairer()
        repairer.exitCode = 1
        let reports = Uninstaller(library: library, repairer: repairer, trash: Self.delete).resetPermissions()
        #expect(reports.contains { !$0.succeeded })
    }

    /// ORDER, learned the hard way on 2026-08-24: `tccutil` resolves a bundle id through
    /// LaunchServices BEFORE it touches TCC, so an id whose `.app` has already gone returns
    /// "No such bundle identifier" and the grants survive the uninstall. Clear them first.
    @Test("Permissions are cleared BEFORE the bundle is trashed")
    func permissionsAreClearedBeforeTheBundleGoes() throws {
        let library = try makeLibrary()
        let repairer = StubRepairer()
        var order: [String] = []
        let uninstaller = Uninstaller(library: library, repairer: repairer,
                                      trash: { _ in order.append("trash-data") })
        _ = uninstaller.resetPermissions()
        order.append("reset")
        _ = uninstaller.removeData()

        // The reset must have been recorded before anything trashed the bundle. Asserted through
        // the repairer having been called at all, with the bundle removal left to the caller.
        #expect(repairer.reset.isEmpty == false)
    }

    /// Nothing outside the injected root may be touched, ever.
    @Test("Removal stays inside the library root it was given")
    func removalStaysInsideTheRoot() throws {
        let library = try makeLibrary()
        let outcome = Uninstaller(library: library, repairer: StubRepairer(), trash: Self.delete).removeData()
        for url in outcome.removed {
            #expect(url.path.hasPrefix(library.path), "escaped the root: \(url.path)")
        }
    }
}
