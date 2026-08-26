# The menu bar shows the app's own mark (#216)

Bobby, with a screenshot of the menu-bar icon beside the app icon:

> what about making the perfect svg to match the icon for the navbar transparent and then inversion
> icon when it's active

## What was wrong

The menu bar drew SF Symbol `waveform`, which is a different logo from the app icon - varied wavy
strokes rather than five tiles on a fixed pitch. #210 removed the bar under the app icon so every
surface would show the same mark; this was the surface still showing a different one. The active
state was `waveform.circle.fill`, a filled circle, where the icon uses a squircle.

## The two marks

Both are the app icon's own geometry, scaled. `AppIconSource.svg` draws tiles 86 wide on a 129 pitch,
heights 170/350/520/350/170, spanning 602x520 on a 1024 canvas.

- **Idle**: scaled by 16/602 to 2.286 wide on a 3.43 pitch, centred in an 18x18 box.
- **Active**: the same tiles at 12 wide, knocked out of a filled squircle whose corner ratio is the
  icon's own 205/896 = 0.2288.

**Inversion rather than a colour, because both ship as TEMPLATE images.** A template hands macOS only
the alpha channel and lets it tint for a light or dark menu bar, so the app never picks a colour and
can never pick the wrong one - which is also why "active" cannot BE a colour. The difference has to
be in shape.

## PNG, not PDF, and the measurement that decided it

TermTile ships its menu glyph as a PDF, and vector is the better artwork: sharp at any scale factor.
It was rejected here because it cannot be CHECKED.

- `rsvg-convert -f pdf` is not deterministic: two renders of an unchanged SVG differ by **122 bytes**.
- Rasterising a PDF with `sips` is not deterministic either: the same PDF rasterised twice differs.

With no stable comparison, a `--check` over PDFs can only assert the file exists - which passes on a
stale asset, and that silent divergence is the entire reason `scripts/render-icon.sh` was written
(#210). rsvg's PNG output IS byte-stable, so the glyphs are 36px PNGs (18pt at 2x) and the existing
byte comparison covers all three assets. The cost is downsampling on a 1x display.

## The badge had to be composited locally

`MacFaceKit.MenuBarBadge.badged()` takes a symbol NAME and has no image overload, and MacFaceKit is a
separate package pinned at 0.5.1 - not ours to change from this repo. `MenuBarGlyph` does the same
compositing over the app's artwork, taking the dot's colour and size from MacFaceKit's `Tokens` so
the vocabulary stays shared even though the loop is duplicated.

Its comment carries a trap worth repeating: a badged image is NOT a template, so the menu bar stops
tinting it and the artwork keeps the black it was drawn in - invisible on a dark menu bar. That
version "passed every assertion and was unusable; only rendering it and looking showed it." The
explicit `glyphColor` fill is what prevents it, and `.sourceAtop` is what keeps the knockout bars
transparent rather than filling them in.

## Verified

**Rendered, all four states** - idle and active, each plain and badged, composited exactly as the
menu bar receives them. The idle mark tints white on a dark bar; the active mark shows the bar
through its knockouts; the dot sits beside the mark in both.

**Alpha, not appearance** - `MenuBarGlyphTests` reads the raster directly and asserts the swap: dead
centre is opaque in the idle mark and transparent in the active one, and the gap between two bars is
the reverse. Two marks could differ in every byte and still both read as bars; this is what says the
inversion is real.

Both plants were caught:

| Planted | Caught by |
|---|---|
| active mark rendered as a solid squircle, no knockout | "filled squircle with the bars knocked out", and "idle and active disagree" |
| `load()` forgets to set the 18pt size | "both marks are in the bundle and sized for the menu bar" |

## What is NOT verified

**A photograph of the new glyph in the live menu bar.** A probe build under its own bundle id was
launched and the menu bar captured, but its status item landed in the hidden overflow of Bobby's
menu-bar manager and never appeared. What was confirmed is the artwork and the compositing - the
exact `NSImage` the label receives - not macOS drawing it in the bar. The mechanism there is
unchanged from the SF Symbol path it replaces, and the fallback to `Image(systemName: "waveform")`
remains for artwork that will not load.
