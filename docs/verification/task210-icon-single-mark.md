# One mark, everywhere (#210)

Bobby: *"for the icon remove the bottom line and then recenter the icon and then make that the
consistently clean one."*

## What was inconsistent

The app draws itself in three places. Only one of them had a line under the bars:

| surface | what it draws | had the line? |
|---|---|---|
| menu bar | SF Symbol `waveform` (`AppModel.menuBarSymbol`) | no |
| HUD | 13 procedural capsules (`DictationHUD.swift`) | no |
| app icon | 5 tiles **plus a 602px bar** | **yes** |

The bar was meant to read as the line of text PushText inserts. It reads as an underline.

## Recentring was not optional

The bars had been balanced against the LINE rather than the squircle - the SVG's own comment said so:
"tallest bar top (161) to text-line bottom (863) leaves 97px of squircle above and below". Their
centre was **y=421**; the squircle centres on **512**. Deleting the line alone would leave the mark
sitting 91px high.

All five bars moved down 91. The mark now spans 252..772, leaving 188px of squircle above and below.

## Nothing else needed changing

Verified by reading the chain rather than assuming it: one source, one raster, everything derived.

```
Resources/AppIconSource.svg
  -> Sources/PushText/Resources/AppIcon.png   (scripts/render-icon.sh)
  -> AppIcon.icns                             (build-app.sh, sips + iconutil)
  -> Dock, Finder, the Sparkle update dialog, and the menu panel's identity tile
```

The identity tile in the menu panel takes no code change: `AppIconView` falls back to
`NSApplication.shared.applicationIconImage`, which is the `.icns`. The menu-bar icon and the HUD are
untouched because they never had the line.

Confirmed end to end by unpacking the built bundle's `AppIcon.icns` with `iconutil -c iconset` and
looking at `icon_512x512.png` - bars only, centred.

## The gap that made this possible

**There was no script rendering the SVG to the PNG.** The step existed only as a sentence inside the
SVG. Editing the source and forgetting to re-render would have shipped the old icon while the repo
showed the new one, with no symptom until someone looked at the Dock.

`scripts/render-icon.sh` now does the render, and `--check` compares the RENDER rather than
timestamps or bytes - a touched file is not a changed icon, and an SVG edit that renders identically
is not a problem.

Battle-tested in both directions:

- against the pre-change PNG: `DOES NOT match ... run scripts/render-icon.sh`, exit 1
- after rendering: `is up to date`, exit 0
- with the tallest bar moved 40px in the SVG: exit 1
- restored: exit 0

The first plant was a bad one - an XML comment appended after `</svg>`, which renders identically and
correctly did NOT trip the check. A plant has to change the thing being measured.

`.engine/checks/icon-render-current.sh` delegates to that script so there is one definition of
"current", and CI installs librsvg to run it.
