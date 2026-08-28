#!/usr/bin/env bash
# render-icon.sh - render the SVG sources to the assets the app ships (#210, #216).
#
# WHY THIS EXISTS: the renders used to be manual `rsvg-convert` invocations documented only inside a
# comment in the SVG itself. Nothing connected source to output, so editing one and forgetting to
# re-render would leave the app shipping the OLD artwork while the repo showed the new - a divergence
# with no symptom until somebody looked at the Dock or the menu bar.
#
# Three assets, one source each:
#
#   Resources/icons/<variant>.svg  -> Sources/PushText/Resources/AppIcon.png         1024, for the .icns
#   Resources/MenuGlyphIdle.svg    -> Sources/PushText/Resources/MenuGlyphIdle.png   36 = 18pt @2x
#   Resources/MenuGlyphActive.svg  -> Sources/PushText/Resources/MenuGlyphActive.png
#
# ALL PNG, including the menu glyphs, and that is a deliberate trade. A PDF template would stay sharp
# at any scale factor, which is what TermTile ships - but rsvg's PDF output is NOT deterministic
# (measured: two renders of an unchanged SVG differ by 122 bytes), and neither is `sips` when
# rasterising one (measured: the same PDF rasterised twice differs). With no stable comparison, a
# --check over PDFs can only assert the file EXISTS, which passes on a stale asset and is precisely
# the divergence this script was written to catch.
#
# rsvg's PNG output IS byte-stable, so a PNG can be checked properly. A 36px raster is sharp on every
# Retina Mac at the 18pt the menu bar draws; the cost is downsampling on a 1x display.
#
#   scripts/render-icon.sh              # render everything
#   scripts/render-icon.sh --check      # fail if any output is out of date, changing nothing
set -euo pipefail

cd "$(dirname "$0")/.."

command -v rsvg-convert >/dev/null 2>&1 || {
    echo "render-icon: rsvg-convert not found - brew install librsvg" >&2
    exit 1
}

# WHICH APP-ICON DESIGN SHIPS (#228). One line, so going back is one line.
#
#   v1-level-meter  the five-tile waveform, shipped since #210
#   v2-p-mark       the same tiles arranged into a lowercase "p", a truer sibling to TermTile's "T"
#
# Variants live side by side in Resources/icons/ rather than in git history alone, because comparing
# two designs means rendering both, and a design you have to `git show` to look at does not get
# compared.
ICON_VARIANT="${ICON_VARIANT:-v2-p-mark}"

# src|dest|pixels
ASSETS="Resources/icons/$ICON_VARIANT.svg|Sources/PushText/Resources/AppIcon.png|1024
Resources/MenuGlyphIdle.svg|Sources/PushText/Resources/MenuGlyphIdle.png|36
Resources/MenuGlyphActive.svg|Sources/PushText/Resources/MenuGlyphActive.png|36"

CHECK=0
[ "${1:-}" = "--check" ] && CHECK=1

STALE=0
while IFS='|' read -r SRC OUT PX; do
    [ -z "$SRC" ] && continue
    test -f "$SRC" || { echo "render-icon: missing $SRC" >&2; exit 1; }

    if [ "$CHECK" -eq 1 ]; then
        TMP="$(mktemp -d)/out.png"
        rsvg-convert -w "$PX" -h "$PX" "$SRC" -o "$TMP"
        # Compares the RENDER, not timestamps: a touched file is not a changed asset, and an SVG
        # edit that renders identically is not a problem either.
        if cmp -s "$TMP" "$OUT"; then
            echo "render-icon: $OUT is up to date with $SRC"
        else
            echo "render-icon: $OUT DOES NOT match $SRC - run scripts/render-icon.sh" >&2
            STALE=1
        fi
    else
        rsvg-convert -w "$PX" -h "$PX" "$SRC" -o "$OUT"
        echo "render-icon: $SRC -> $OUT (${PX}px)"
    fi
done <<EOF
$ASSETS
EOF

exit $STALE
