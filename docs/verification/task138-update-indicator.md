# Task 138 - The update dot, and how much of it already existed

Measured 2026-08-24 on macOS 26.6.2.

---

## 1. Capability-grep first, and it paid

Bobby asked for TermTile's update dot on three surfaces. Before writing anything, `grep -rn
"attention" ~/Developer/MacFaceKit/Sources`:

```
AttentionDot.swift          the dot itself
IconButton.swift:12         private let attention: Bool
OverflowMenu.swift:46       IconButton(..., attention: actions.contains { $0.attention })
```

**MacFaceKit already rendered all of it**, and `OverflowMenu` already lifts the mark from any
`MenuAction` onto the `...` button. PushText had never passed `attention:`. Two of the three
surfaces were one flag away.

## 2. What genuinely was missing

- **The state that decides when.** `UpdateAvailability` lived in TermTile only.
- **The menu-bar badge.** `TermTileGlyph` composites the dot INTO one `NSImage` rather than layering
  it, with the note that `MenuBarExtra` "can flatten/tint SwiftUI label overlays". A SwiftUI badge
  over the label gets re-tinted to the glyph colour and vanishes.

Both are the "rule for all apps" half, so both went to MacFaceKit 0.5.0 rather than into PushText.

## 3. Why `checking` and `failed` do not mark

Carried over deliberately, because it is a judgement rather than an accident:

- A dot that appears while merely **checking** teaches the user that dots mean nothing.
- A **failed** check is not news anyone can act on - and it is not the same as being up to date,
  which is why they stay two cases. Collapsing them would tell the user they are current when the
  app has no idea. Same shape as a CI summary where zero checks and all-green render identically.

## 4. The probe is passive on purpose

`updater.checkForUpdateInformation()` is Sparkle's non-presenting path. Automatic checks stay off
(`SUEnableAutomaticChecks` false), so nothing opens a dialog on its own - a dictation utility that
interrupts you unprompted is not what was promised. A quiet mark is.

## 5. Battle-tested

MacFaceKit, three plants:

| planted regression | caught by |
| --- | --- |
| light the dot while merely `checking` | "only .available marks attention" |
| leave the badged image a template | "a badged image is not a template" |
| flip the flag but draw no dot | **passed at first - see below** |

PushText, three plants, all caught: mark the row always, never mark the row, drop the accessibility
hint.

## 6. A vacuous test of mine, caught by planting

The badge test compared the plain and badged TIFFs and asserted they differed. It passed on an
implementation that drew **nothing**, because the badged canvas is wider by the inset - the bytes
differ whatever is painted on them. The assertion was measuring the resize.

Rewritten to sample the corner for a warning-coloured pixel, which a resize cannot satisfy. The same
plant now fails it.

## 7. What was seen, and what was not

**Seen:** the `...` button carrying the dot, rendered through `PUSHTEXT_MENU_PROBE_UPDATE=1` and
looked at. MacFaceKit lifted it from the `MenuAction` with no PushText code involved.

**NOT seen at first:** the menu-bar icon. Closing that gap found a real defect - see below.

**Still not seen:** the dropdown row's own mark, which needs the popover open. Covered by
`MacFaceKit`'s `OverflowAttentionTests` and by the indicator suite, but not looked at in place.

## 8. The menu-bar glyph was invisible, and only a render showed it

Rendering the badged image beside the plain one showed a BLACK waveform on a dark background.

Every assertion passed on that version: `isTemplate == false`, and a warning-coloured dot really was
painted. Both true, and the icon unusable.

The cause is the fix for the previous defect. A badged image is deliberately not a template so the
menu bar cannot flatten the dot away - and the same flag stops the menu bar tinting the GLYPH, so the
SF Symbol falls back to its default black. TermTile draws its glyph with an explicit colour taken
from the colour scheme; that step was missing.

Fixed in MacFaceKit 0.5.1: `badged(...)` takes a `glyphColor` and fills the symbol with it, and
PushText passes white or black from `NSApp.effectiveAppearance`. The test samples the LEFT half of
the image - glyph, not dot - and asserts a light pixel exists; planting the missing tint fails it.

That test also CRASHED on its first run: `whiteComponent` throws on a `deviceRGB` colour. Reading the
RGB components instead is something only executing it could have found.

## 9. A difference that turned out to be my own harness

The badged glyph still looked dimmer than the plain one side by side, and the obvious next move was
to change the compositing operation. It would have been wrong. The comparison image composites the
badge at native size and then upscales it, while the plain one is tinted AFTER scaling - so the
badged glyph goes through an extra resample and softens. At native size the assertion requires every
channel above 0.8 and passes.

A `.sourceAtop` -> `.sourceIn` change was written, could not be shown to improve anything, and was
reverted rather than shipped.
