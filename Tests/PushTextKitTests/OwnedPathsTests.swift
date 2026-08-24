import Testing
import Foundation
@testable import PushTextKit

/// Everything a shipped PushText leaves in `~/Library` (#150).
///
/// Ported from TermTile's `OwnedPaths`. Uninstall used to trash only the app bundle, so **80 real
/// dictation transcripts survived it** - for an app whose pitch is that nothing leaves this machine,
/// leaving the transcripts behind after the user asked for it gone is a privacy defect, not untidiness.
///
/// EXACT literals, never a glob or a prefix: a neighbour like `dev.ecn.apps.pushtext.selftest.plist`
/// must never be caught by removing `dev.ecn.apps.pushtext`.
@Suite("Owned paths")
struct OwnedPathsTests {

    private let library = URL(fileURLWithPath: "/tmp/fake-library", isDirectory: true)

    private var paths: [String] {
        OwnedPaths(library: library, bundleID: "dev.ecn.apps.pushtext", appName: "PushText")
            .dataPaths.map(\.path)
    }

    /// THE one that matters. The transcripts live under the app NAME, not the bundle id - a list
    /// derived only from the bundle id would miss them entirely and look complete.
    @Test("The dictation history and dictionary are owned")
    func historyIsOwned() {
        #expect(paths.contains("/tmp/fake-library/Application Support/PushText"))
    }

    @Test("Preferences, caches and network storage are owned")
    func libraryLeftoversAreOwned() {
        for expected in ["Preferences/dev.ecn.apps.pushtext.plist",
                         "Caches/dev.ecn.apps.pushtext",
                         "HTTPStorages/dev.ecn.apps.pushtext",
                         "HTTPStorages/dev.ecn.apps.pushtext.binarycookies",
                         "Saved Application State/dev.ecn.apps.pushtext.savedState"] {
            #expect(paths.contains("/tmp/fake-library/\(expected)"), "not owned: \(expected)")
        }
    }

    /// A prefix match would take a neighbour's data with it. This is why the list is literals.
    @Test("A neighbouring bundle id is never caught")
    func neighboursAreSafe() {
        for path in paths {
            #expect(path.hasSuffix(".selftest") == false)
            #expect(path.contains("dev.ecn.apps.pushtext.selftest") == false)
        }
    }

    /// The bundle is removed separately - a running app cannot delete itself, so listing it here
    /// would produce a failure on every uninstall.
    @Test("The app bundle is NOT in the data list")
    func bundleIsNotDataOwned() {
        #expect(paths.contains { $0.hasSuffix(".app") } == false)
    }

    /// The library root is injected so a test can never touch the real one.
    @Test("Every path sits under the injected library root")
    func everythingIsUnderTheInjectedRoot() {
        #expect(paths.isEmpty == false)
        for path in paths {
            #expect(path.hasPrefix("/tmp/fake-library/"), "escaped the root: \(path)")
        }
    }
}
