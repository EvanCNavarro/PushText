import Testing
import Foundation
@testable import PushText
import MacFaceKit
import PushTextKit
import PushTextCore

/// The update dot, end to end through the menu's own data (#138).
///
/// TermTile shows a mark in three places when an update is waiting: the menu-bar icon, the `···`
/// button, and the "Check for Updates" row. MacFaceKit already lifts the mark from a `MenuAction`
/// onto the `···`, so getting the flag onto that one action lights two of the three.
@Suite("Update indicator")
@MainActor
struct UpdateIndicatorTests {

    private func actions(_ availability: UpdateAvailability) -> [MenuAction] {
        let appActions = AppActions(repairer: StubRepairer())
        appActions.updateAvailability = availability
        return appActions.menuActions()
    }

    private final class StubRepairer: PermissionRepairing {
        func reset(_ permissions: [Permission]) -> [PermissionRepairReport] { [] }
    }

    /// Nothing waiting, nothing marked - or the dot means nothing.
    @Test("No update means no attention anywhere in the menu")
    func quietWhenUpToDate() {
        for availability in [UpdateAvailability.unknown, .checking, .unavailable, .failed] {
            #expect(actions(availability).contains { $0.attention } == false,
                    "\(availability) lit the dot")
        }
    }

    /// THE case. One flag on one action; MacFaceKit carries it to the ellipsis.
    @Test("An available update marks the Check for Updates row")
    func availableMarksTheRow() {
        let marked = actions(.available(version: "9.9.9")).filter { $0.attention }
        #expect(marked.count == 1)
        #expect(marked.first?.title.contains("Check for Updates") == true)
    }

    /// Exactly ONE row lights up. A dot on every row is wallpaper.
    @Test("Only the update row is marked, never the rest of the menu")
    func onlyTheUpdateRow() {
        let all = actions(.available(version: nil))
        #expect(all.count > 1)
        #expect(all.filter { $0.attention }.count == 1)
        for action in all where !action.attention {
            #expect(action.title.contains("Check for Updates") == false)
        }
    }

    /// A screen reader must hear what the dot means; the dot itself is decorative.
    @Test("The marked row carries a hint saying what the dot means")
    func markedRowIsAnnounced() {
        let marked = actions(.available(version: "1.0.0")).first { $0.attention }
        #expect(marked?.attentionAccessibilityHint?.isEmpty == false)
    }

    /// The menu-bar icon is the third place, and it must change with the state rather than being
    /// badged unconditionally.
    @Test("The menu bar image is badged only when an update is waiting")
    func menuBarImageFollowsAvailability() throws {
        let plain = try #require(MenuBarBadge.badged(systemImage: "waveform", attention: false))
        let badged = try #require(MenuBarBadge.badged(systemImage: "waveform", attention: true))
        #expect(plain.isTemplate)
        #expect(badged.isTemplate == false)
    }
}
