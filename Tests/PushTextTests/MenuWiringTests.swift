import Testing
import Foundation
@testable import PushText
import MacFaceKit

/// That a menu item does what its label says (#164).
///
/// Everything the menu's closures CALL was already covered - the history store, the uninstaller, the
/// dictionary editor, the update check. The association between a TITLE and its effect was covered by
/// nothing, so pointing "Delete History" at `confirmUninstall()` would have passed `swift test`,
/// `swiftlint`, all eleven `.engine/checks` and the packaged smoke. Two of the six items are
/// destructive and one is silent.
@Suite("Menu wiring")
@MainActor
struct MenuWiringTests {

    /// Records which effect ran, so the assertions are about DISPATCH rather than about doing the
    /// real thing. Invoking the production effects in a test either blocks on `NSAlert.runModal()`
    /// or genuinely quits the process - which is exactly why this was never tested before.
    private final class SpyEffects: MenuEffects {
        var performed: [MenuItemKind] = []
        func checkForUpdates() { performed.append(.checkForUpdates) }
        func editDictionary() { performed.append(.editDictionary) }
        func viewHistory() { performed.append(.viewHistory) }
        func deleteHistory() { performed.append(.deleteHistory) }
        func quit() { performed.append(.quit) }
        func beginUninstall() { performed.append(.uninstall) }
    }

    /// THE test. Every kind must reach its own effect and no other.
    ///
    /// Written as a loop over `allCases` on purpose: a hand-written list would silently stop
    /// covering a seventh item the day someone adds one.
    @Test("Every menu item runs its own effect, and only that one")
    func eachKindDispatchesToItself() {
        for kind in MenuItemKind.allCases {
            let spy = SpyEffects()
            MenuDispatch.perform(kind, on: spy)
            #expect(spy.performed == [kind],
                    "\(kind) ran \(spy.performed) - a menu item is wired to the wrong effect")
        }
    }

    /// The labels a user reads. A swap here is as bad as a swap in the dispatch: the button that
    /// says Delete History would still delete the app.
    @Test("The titles are the ones the user is promised")
    func titlesAreStable() {
        #expect(MenuItemKind.checkForUpdates.title == "Check for Updates")
        #expect(MenuItemKind.editDictionary.title == "Edit Dictionary")
        #expect(MenuItemKind.viewHistory.title == "View History")
        #expect(MenuItemKind.deleteHistory.title == "Delete History")
        #expect(MenuItemKind.quit.title == "Quit PushText")
        #expect(MenuItemKind.uninstall.title == "Uninstall PushText...")
    }

    /// `destructive` drives the red styling. An uninstall that does not look destructive is a
    /// one-slip mistake, and a Quit that DOES look destructive trains the user to ignore the colour.
    @Test("Only the genuinely destructive item is marked destructive")
    func destructiveIsMarkedExactly() {
        let destructive = MenuItemKind.allCases.filter(\.destructive)
        #expect(destructive == [.uninstall], "destructive marks are \(destructive)")
    }

    /// The order the user sees. Delete History sitting next to Quit is the adjacency that makes a
    /// mis-tap expensive, so the order is pinned rather than left to whoever edits the array next.
    @Test("The menu is built from the kinds, in order")
    func menuMatchesTheKinds() {
        let actions = MenuDispatch.actions(for: MenuItemKind.allCases,
                                           attention: { _ in false },
                                           run: { _ in })
        #expect(actions.map(\.title) == MenuItemKind.allCases.map(\.title))
    }

    /// Icons are pinned to LITERALS, not compared against `MenuItemKind`'s own values.
    ///
    /// The first version of this asserted `actions.map(\.systemImage) == kinds.map(\.systemImage)`
    /// - both sides read from the same source, so changing an icon changed both and the assertion
    /// could never fail. Planting a trash can on View History proved it: green. A test that compares
    /// a thing to itself is not a weak test, it is not a test.
    ///
    /// `deleteHistory` and `uninstall` legitimately share `trash`; that is the only repeat, and it
    /// is stated here so a third one has to be deliberate.
    @Test("Each item wears the icon the user is shown")
    func iconsAreStable() {
        #expect(MenuItemKind.checkForUpdates.systemImage == "arrow.triangle.2.circlepath")
        #expect(MenuItemKind.editDictionary.systemImage == "character.book.closed")
        #expect(MenuItemKind.viewHistory.systemImage == "clock.arrow.circlepath")
        #expect(MenuItemKind.deleteHistory.systemImage == "trash")
        #expect(MenuItemKind.quit.systemImage == "power")
        #expect(MenuItemKind.uninstall.systemImage == "trash")
    }

    /// The update dot rides on one item only. If it moved to another, the menu would mark something
    /// that has nothing to do with updates.
    @Test("Only Check for Updates can carry the update mark")
    func onlyUpdatesCarriesAttention() {
        let actions = MenuDispatch.actions(for: MenuItemKind.allCases,
                                           attention: { $0 == .checkForUpdates },
                                           run: { _ in })
        let marked = actions.filter(\.attention).map(\.title)
        #expect(marked == ["Check for Updates"], "marked: \(marked)")
    }

    /// Pressing an item must run THAT item's effect - the last place a swap could hide is the
    /// closure the builder attaches.
    @Test("Pressing an item invokes its own kind")
    func pressingRunsItsKind() {
        var ran: [MenuItemKind] = []
        let actions = MenuDispatch.actions(for: MenuItemKind.allCases,
                                           attention: { _ in false },
                                           run: { ran.append($0) })
        for action in actions { action.action() }
        #expect(ran == MenuItemKind.allCases, "ran \(ran)")
    }
}
