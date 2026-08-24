# Task 115 - Seeing the refused-press pulse

**The pulse is rendered and attributable.** Verified 2026-08-23 on macOS 26.6.2 through the
packaged `.app`.

---

## 1. Why it took a probe seam

The pulse lasts 150 ms and `screencapture` takes ~200-300 ms, so frames straddle the animation
rather than landing inside it. #99 tried five times and never caught it.

`PUSHTEXT_HUD_PROBE_PULSE_MS` raises the hold. The pulse still runs the real `onChange` ->
`withAnimation` -> `scaleEffect` path; only the hold differs, so this verifies the production
animation rather than a forced flag. `PUSHTEXT_HUD_PROBE_REFUSE=1` triggers one refusal.

## 2. Three instruments, two of which were wrong

**Width measurement (from #99) - discarded.** It scanned one row for bright pixels and reported the
CROP bounds every time (`first=0`), so it agreed with any hypothesis. Not fixed, replaced.

**Whole-screen diff - wrong.** Comparing two full screenshots showed 35989 changed pixels across the
entire crop. That was the terminal window churning BEHIND the HUD. A diff of the screen cannot
isolate a window that is not opaque over static content.

**Window-only diff - correct.** `screencapture -l<windowID>` captures the HUD panel alone, with no
background. Window ids come from `CGWindowListCopyWindowInfo`.

The differ was battle-tested before use: identical images give `changed=0`, two different icons give
`changed=8954`. A measurer that cannot return zero is not a measurer.

## 3. The control that nearly wasn't run

The first window-only comparison gave `changed=3821` with the refusal on - and it would have been
reported as proof.

Running the SAME capture with the refusal OFF gave **`changed=2254`**. The HUD is not static shortly
after `show()`; the entry transition is still settling. A non-zero diff there proves nothing, and the
pulse would have been "verified" by an artifact.

Capturing later, once the transition has settled, the no-refusal control gives **`changed=0`**.

## 4. Result

Both frames from ONE launch, in the settled window, captured as the HUD window alone:

| comparison | changed pixels |
| --- | --- |
| control, same times, NO refusal | **0** |
| identical image against itself | 0 |
| pulsed vs settled, refusal ON | **12334**, bbox (34,0)-(445,105) |

The only difference between the two runs is the refusal, and the control establishes that the HUD is
otherwise static across those timings. So the 12334 changed pixels are the pulse.

Visually confirmed as well: the pulsed frame's pill is plainly larger, its edges nearer the window
bounds.

## 5. What this still does not show

The pulse's MOTION was not captured frame by frame - only its held state against its resting state.
A scale that snapped instantly rather than springing would produce the same two frames. Verifying
the easing would need video capture, and nothing here attempts it.
