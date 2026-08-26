#!/usr/bin/env bash
# render-icon.sh - render the icon SVG to the PNG the build turns into an .icns (#210).
#
# WHY THIS EXISTS: the render used to be a manual `rsvg-convert` invocation documented only inside a
# comment in the SVG itself. Nothing connected the two files, so editing the source and forgetting to
# re-render would leave the app shipping the OLD icon while the repo showed the new one - a
# divergence with no symptom until someone looked at the Dock.
#
# The chain is: AppIconSource.svg -> AppIcon.png (here) -> AppIcon.icns (build-app.sh) -> the Dock,
# Finder, the Sparkle update dialog, and the identity tile in the menu panel, which all read the
# .icns off the built bundle.
#
#   scripts/render-icon.sh              # render
#   scripts/render-icon.sh --check      # fail if the PNG is out of date, changing nothing
set -euo pipefail

cd "$(dirname "$0")/.."
SRC="Resources/AppIconSource.svg"
OUT="Sources/PushText/Resources/AppIcon.png"

command -v rsvg-convert >/dev/null 2>&1 || {
    echo "render-icon: rsvg-convert not found - brew install librsvg" >&2
    exit 1
}
test -f "$SRC" || { echo "render-icon: missing $SRC" >&2; exit 1; }

if [ "${1:-}" = "--check" ]; then
    TMP="$(mktemp -d)/AppIcon.png"
    rsvg-convert -w 1024 -h 1024 "$SRC" -o "$TMP"
    # Compares the RENDER, not timestamps: a touched file is not a changed icon, and an edited SVG
    # that renders identically is not a problem either.
    if cmp -s "$TMP" "$OUT"; then
        echo "render-icon: $OUT is up to date with $SRC"
        exit 0
    fi
    echo "render-icon: $OUT DOES NOT match $SRC - run scripts/render-icon.sh" >&2
    exit 1
fi

rsvg-convert -w 1024 -h 1024 "$SRC" -o "$OUT"
echo "render-icon: $SRC -> $OUT ($(sips -g pixelWidth -g pixelHeight "$OUT" | tail -2 | tr -d ' \n'))"
