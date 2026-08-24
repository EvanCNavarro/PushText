import Testing
import Foundation
import AppKit
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

    /// Writes the plain and badged menu-bar images side by side so the dot can be LOOKED AT.
    ///
    /// Opt-in via PUSHTEXT_SNAPSHOT_DIR, like the other snapshots: CI has no reason to rasterise.
    /// The template is tinted white here because that is what the menu bar does to it - comparing an
    /// untinted template against a badged non-template would flatter the difference.
    @Test("Render the menu bar images, badged and not",
          .enabled(if: ProcessInfo.processInfo.environment["PUSHTEXT_SNAPSHOT_DIR"] != nil))
    func renderMenuBarImages() throws {
        let directory = try #require(ProcessInfo.processInfo.environment["PUSHTEXT_SNAPSHOT_DIR"])
        let scale: CGFloat = 8
        let canvas = NSImage(size: NSSize(width: 70 * scale, height: 24 * scale))
        canvas.lockFocus()
        NSColor(calibratedWhite: 0.11, alpha: 1).setFill()
        NSRect(origin: .zero, size: canvas.size).fill()
        var x: CGFloat = 6 * scale
        for attention in [false, true] {
            guard let image = MenuBarBadge.badged(systemImage: "waveform", attention: attention)
            else { continue }
            let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
            let scaled = NSImage(size: size)
            scaled.lockFocus()
            image.draw(in: NSRect(origin: .zero, size: size),
                       from: NSRect(origin: .zero, size: image.size),
                       operation: NSCompositingOperation.sourceOver, fraction: 1)
            if image.isTemplate {
                NSColor.white.setFill()
                NSRect(origin: .zero, size: size).fill(using: NSCompositingOperation.sourceIn)
            }
            scaled.unlockFocus()
            scaled.draw(in: NSRect(x: x, y: 4 * scale, width: size.width, height: size.height),
                        from: NSRect(origin: .zero, size: size),
                        operation: NSCompositingOperation.sourceOver, fraction: 1)
            x += size.width + 10 * scale
        }
        canvas.unlockFocus()

        let tiff = try #require(canvas.tiffRepresentation)
        let rep = try #require(NSBitmapImageRep(data: tiff))
        let png = try #require(rep.representation(using: .png, properties: [:]))
        let url = URL(fileURLWithPath: directory).appendingPathComponent("menu-bar-badge.png")
        try png.write(to: url)
        print("SNAPSHOT \(url.path) bytes=\(png.count)")
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
