import AppKit
import MacFaceKit

/// The menu-bar mark: the app icon's own five tiles, idle and inverted (#216).
///
/// **Why not an SF Symbol.** `waveform` and `waveform.circle.fill` were here first, and they are a
/// different logo - varied wavy strokes, and a circle rather than the icon's squircle. #210 removed
/// the bar under the app icon so every surface would show the same mark; the menu bar was the
/// surface still showing a different one.
///
/// **Why a TEMPLATE image.** A template gives macOS only the alpha channel and lets it tint the
/// glyph for a light or a dark menu bar. The app never picks a colour, so it can never pick the
/// wrong one. That is also why "active" is a knockout rather than a second colour: with only alpha
/// to work with, the difference has to be in SHAPE.
enum MenuBarGlyph {

    /// Which mark to draw. `AppModel` decides; this decides what it looks like.
    enum Kind {
        case idle
        case active

        var resourceName: String {
            switch self {
            case .idle: "MenuGlyphIdle"
            case .active: "MenuGlyphActive"
            }
        }
    }

    /// The size the menu bar draws at. The PNGs are 36px, so they land exactly on 2x.
    static let pointSize = NSSize(width: 18, height: 18)

    /// The glyph, badged with the update dot when one is waiting.
    ///
    /// - Returns: nil when the resource will not load, which is the same contract
    ///   `MacFaceKit.MenuBarBadge` keeps and for the same reason - a menu-bar app with no icon has
    ///   no way to reach its own menu, so the caller needs to fall back rather than get a blank.
    ///
    /// Composited HERE rather than by `MenuBarBadge.badged` because that takes a symbol NAME and
    /// there is no overload for an image; MacFaceKit is a separate package and not ours to change
    /// from this repo. The dot's colour and size still come from its `Tokens`, so the two stay one
    /// vocabulary even though the compositing is duplicated.
    static func image(_ kind: Kind, attention: Bool, glyphColor: NSColor,
                      dotSize: CGFloat = Tokens.attentionDot) -> NSImage? {
        guard let glyph = load(kind) else { return nil }

        guard attention else {
            // Left a template so the menu bar keeps tinting it, exactly as an unbadged icon always
            // has.
            glyph.isTemplate = true
            return glyph
        }

        // Room for the dot at the trailing edge, so it sits beside the mark rather than over it.
        let inset = dotSize * 0.75
        let canvas = NSSize(width: glyph.size.width + inset, height: glyph.size.height)
        let image = NSImage(size: canvas)
        image.lockFocus()
        let glyphRect = NSRect(origin: .zero, size: glyph.size)
        glyph.draw(in: glyphRect, from: NSRect(origin: .zero, size: glyph.size),
                   operation: .sourceOver, fraction: 1)
        // Fill the mark explicitly. A badged image is NOT a template, so the menu bar stops tinting
        // it and the artwork keeps the black it was drawn in - invisible on a dark menu bar.
        // MacFaceKit's comment records that this "passed every assertion and was unusable; only
        // rendering it and looking showed it", which is why the fill is here and not optional.
        //
        // `.sourceAtop` paints only where the glyph is already opaque, so the knockout bars in the
        // active mark stay transparent instead of being filled in.
        glyphColor.setFill()
        glyphRect.fill(using: .sourceAtop)
        NSColor(Tokens.warning).setFill()
        NSBezierPath(ovalIn: NSRect(x: canvas.width - dotSize, y: canvas.height - dotSize,
                                    width: dotSize, height: dotSize)).fill()
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    /// Loads the artwork and sizes it for the menu bar.
    ///
    /// The PNG is 36px and the menu bar wants 18pt: setting `size` is what makes AppKit treat the
    /// file as a 2x representation rather than drawing a 36pt image twice the height of the bar.
    ///
    /// **`Bundle.main`, and `Bundle.module` only in DEBUG (TRAP-4).** SwiftPM's generated
    /// `Bundle.module` looks in exactly two places - a `PushText_PushText.bundle` beside the app,
    /// and an ABSOLUTE PATH INTO THE BUILD DIRECTORY OF THE MACHINE THAT COMPILED IT - and calls
    /// `fatalError` when neither exists. `build-app.sh` ships resources FLATTENED into
    /// `Contents/Resources`, because the alternatives either break `codesign --strict` or are never
    /// looked at, so a packaged app has no such bundle.
    ///
    /// Measured, not argued: the first version of this file used `Bundle.module` unguarded. Built
    /// into a .app, run with the build directory renamed to stand in for any other Mac, it died -
    /// `Trace/BPT trap: 5`, exit 133, "could not load resource bundle". The same app with this
    /// version stayed up. v0.2.0 shipped that crash once already, carrying
    /// `/Users/runner/work/PushText/...` into a release.
    static func load(_ kind: Kind) -> NSImage? {
        var url = Bundle.main.url(forResource: kind.resourceName, withExtension: "png")
        #if DEBUG
        // Only in a debug build, and `test-packaged-app.sh` enforces that: under `swift test` the
        // main bundle is the test runner, so the file is not there and the module bundle IS - the
        // exact reverse of the shipped app.
        if url == nil {
            url = Bundle.module.url(forResource: kind.resourceName, withExtension: "png")
        }
        #endif
        guard let url, let image = NSImage(contentsOf: url) else { return nil }
        image.size = pointSize
        return image
    }
}
