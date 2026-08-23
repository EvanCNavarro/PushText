import Testing
import Foundation
import CoreGraphics
@testable import PushTextKit

/// Regression guard for the crash that killed the app mid-dictation (TRAP-32).
///
/// `pasteKeyCode()` uses Text Input Source APIs, and `TSMGetInputSourceProperty` ASSERTS its
/// dispatch queue - called off the main thread it does not return an error, it SIGTRAPs and takes
/// the process with it:
///
///     _dispatch_assert_queue_fail <- TSMGetInputSourceProperty <- pasteKeyCode()
///
/// `@MainActor` makes the compiler enforce the hop, so the original defect can no longer be
/// written. This asserts the other half at runtime: that resolving the keycode FROM a background
/// task - which is where `TextInjector.inject` actually runs, since the protocol is not main-actor
/// isolated - still works rather than trapping or deadlocking.
@Suite("pasteKeyCode threading")
struct PasteKeyCodeThreadingTests {

    @Test("Resolving the paste keycode from a background task does not trap")
    func resolvesFromBackgroundTask() async {
        // Detached: no inherited actor context, exactly like the cooperative-pool execution of
        // `inject` that crashed.
        let keyCode = await Task.detached { @Sendable in
            await MainActor.run { PasteboardTextInjector.pasteKeyCode() }
        }.value

        // The VALUE is layout-dependent (9 on ANSI, different on Dvorak-QWERTY-Command), so this
        // asserts only that the call completed and found a key - a machine with no "v" reachable
        // under Command would legitimately return nil, and that is not this test's business.
        #expect(keyCode != nil, "no keycode produces \"v\" with Command on this layout")
    }

    @Test("Repeated background resolutions stay stable rather than trapping on a later call")
    func repeatedResolutionsAreStable() async {
        // The crash did not happen on the first injection of the session - it appeared later, which
        // is what made it read as "crashes if I record too long". Resolving repeatedly is the
        // cheapest approximation of that: a hop that only works once would show up here.
        var results: [CGKeyCode?] = []
        for _ in 0..<5 {
            let value = await Task.detached { @Sendable in
                await MainActor.run { PasteboardTextInjector.pasteKeyCode() }
            }.value
            results.append(value)
        }

        #expect(results.allSatisfy { $0 == results.first }, "keycode changed between calls: \(results)")
    }
}
