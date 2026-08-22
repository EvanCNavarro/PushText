import Testing
@testable import PushTextCore

@Suite("ClipboardRestore")
struct ClipboardRestoreTests {

    @Test("Unchanged change count means we are still the last writer, so restore")
    func restoreWhenUntouched() {
        #expect(ClipboardRestore.decide(changeCountAfterOurWrite: 42, currentChangeCount: 42)
                == .restore)
    }

    @Test("Any foreign write after ours means leave their clipboard alone",
          arguments: [43, 44, 100])
    func skipWhenSomeoneElseWrote(current: Int) {
        #expect(ClipboardRestore.decide(changeCountAfterOurWrite: 42, currentChangeCount: current)
                == .skipForeignWrite)
    }

    /// `changeCount` is monotonic, so going BACKWARDS is impossible — which makes it a signal that
    /// something is wrong (a different pasteboard, a reset). The safe reading of "impossible" is
    /// don't touch the user's data.
    @Test("A change count that went backwards is treated as unsafe, not as a match")
    func backwardsCountIsUnsafe() {
        #expect(ClipboardRestore.decide(changeCountAfterOurWrite: 42, currentChangeCount: 41)
                == .skipForeignWrite)
    }

    @Test("Zero and negative counts are handled without special-casing into a restore")
    func degenerateCounts() {
        #expect(ClipboardRestore.decide(changeCountAfterOurWrite: 0, currentChangeCount: 0)
                == .restore)
        #expect(ClipboardRestore.decide(changeCountAfterOurWrite: 0, currentChangeCount: 1)
                == .skipForeignWrite)
        #expect(ClipboardRestore.decide(changeCountAfterOurWrite: -1, currentChangeCount: 0)
                == .skipForeignWrite)
    }
}
