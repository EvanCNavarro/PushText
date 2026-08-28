import Testing
import AppKit
@testable import PushText

/// The menu-bar mark (#216).
///
/// These assert the two properties that make it usable and that nothing else checks: the artwork is
/// actually IN the bundle, and "active" differs from "idle" in ALPHA - because a template image has
/// no colour, so an inversion that is not a real knockout would look identical in the menu bar.
@Suite("Menu bar glyph")
struct MenuBarGlyphTests {

    /// Alpha at a pixel of the underlying raster.
    ///
    /// Read off the file's own representation rather than `tiffRepresentation`: `load` sets `size`
    /// to 18pt while the PNG is 36px, and rasterising through the size would resample and blur the
    /// exact edges these tests are about.
    private func alpha(_ kind: MenuBarGlyph.Kind, x: Int, y: Int) throws -> CGFloat {
        let image = try #require(MenuBarGlyph.load(kind), "artwork missing from the bundle")
        let rep = try #require(image.representations.first as? NSBitmapImageRep)
        #expect(rep.pixelsWide == 36, "the raster should be 18pt at 2x")
        let colour = try #require(rep.colorAt(x: x, y: y))
        return colour.alphaComponent
    }

    /// The failure this catches is total: no artwork means no menu-bar icon, and a menu-bar app with
    /// no icon has no way to reach its own menu.
    @Test("Both marks are in the bundle and sized for the menu bar")
    func bothLoad() throws {
        for kind in [MenuBarGlyph.Kind.idle, .active] {
            let image = try #require(MenuBarGlyph.load(kind))
            #expect(image.size == NSSize(width: 18, height: 18))
        }
    }

    @Test("The idle mark is bars on transparency")
    func idleIsBarsOnTransparency() throws {
        // Dead centre is the tallest bar.
        #expect(try alpha(.idle, x: 18, y: 18) > 0.9)
        // The far corner is outside every bar.
        #expect(try alpha(.idle, x: 0, y: 0) < 0.1)
    }

    /// The inversion, stated as alpha rather than as "a different image". Two marks could differ in
    /// every byte and still both read as bars; what makes the active one legible is that the fill
    /// and the bars have SWAPPED which of them is transparent.
    @Test("The active mark is a filled squircle with the bars knocked out")
    func activeIsAKnockout() throws {
        // Dead centre is the middle bar - transparent here, opaque in the idle mark.
        #expect(try alpha(.active, x: 18, y: 18) < 0.1)
        // The gap between the first and second bars is inside the fill, so it is opaque here and
        // transparent in the idle mark.
        #expect(try alpha(.active, x: 10, y: 18) > 0.9)
        // And the corner is inside the squircle rather than outside the artwork.
        #expect(try alpha(.active, x: 18, y: 2) > 0.9)
    }

    /// The pair, compared directly: at the same pixel the two marks must disagree, or the menu bar
    /// would show no change when dictation starts.
    @Test("Idle and active disagree where it matters")
    func theTwoDiffer() throws {
        let idleCentre = try alpha(.idle, x: 18, y: 18)
        let activeCentre = try alpha(.active, x: 18, y: 18)
        #expect(idleCentre > 0.9 && activeCentre < 0.1)
    }

    /// The letterform itself (#228). The mark is a lowercase "p" only because column one carries on
    /// past every other tile; a stem that merely started higher would look like a taller bar and no
    /// assertion above would notice.
    ///
    /// Low in the glyph - row 32 of 36 - the stem must still be there and the tallest tile must not.
    /// Both halves are needed: opacity alone would pass on a mark with no descender at all, and
    /// transparency alone would pass on an empty image.
    @Test("The stem descends below every other tile")
    func stemDescends() throws {
        #expect(try alpha(.idle, x: 4, y: 32) > 0.9, "the stem should still be drawing here")
        #expect(try alpha(.idle, x: 18, y: 32) < 0.1, "the tallest tile should have ended above this")
    }

    /// Unbadged, the mark must stay a template so macOS tints it for a light or dark menu bar. The
    /// app never picks a colour, so it can never pick the wrong one.
    @Test("An unbadged mark is a template")
    func unbadgedIsTemplate() throws {
        let image = try #require(MenuBarGlyph.image(.idle, attention: false, glyphColor: .white))
        #expect(image.isTemplate)
    }
}
