# The mark became a letter (#228)

Bobby: *"maybe the logo could have the first line be full length height long so then the rest is
hanging off that pole like a 'p' letter so it looks like a p just like the termtile logo looks like
a t."*

## My first reading was wrong, and his sketch corrected it

I rebuilt the mark as a stem plus a "bowl" - three top-aligned tiles - and threw the waveform away.
Rendered beside two other arrangements it was the best of a bad set: a centred arch read as a
waveform standing BESIDE a tall bar, a decaying staircase read as a signal dying, and the bowl read
as a bar chart with a tall first bar.

His sketch changes ONE thing. Column one keeps its top at 427 and runs to 950 instead of 597;
columns two to five are v1 exactly. Measured off his image against the v1 geometry, bars 2-5 matched
within a few pixels - the waveform was never meant to move.

## Why 950, and not the 985 the sketch showed

The squircle's bottom-left corner has radius 205 centred on (269, 755), so beneath that column the
boundary runs from **y=952 at x=212** to **y=960 at x>=269**. A stem drawn to 985 is sliced at an
angle by that curve. Rendered, it reads as a mistake rather than a deliberate bleed. 950 is the
longest descender whose rounded cap still clears the corner.

## The menu bar: redraw, do not scale

The glyph draws the same mark, and the naive move is to scale the icon into the 18pt box. That means
fitting a mark now 698 units tall where a 520-unit mark used to sit, so every tile shrinks from
**2.29pt to 1.95pt** - measured, and visibly thinner in the bar. That cost is what made the earlier
p-mark look unusable at menu-bar size, and it was the scaling, not the descender.

The glyph was never obliged to be a shrunk copy. Moving the waveform **up 1.2pt** frees exactly the
room the stem needs to drop below it, and every tile keeps its full width. The descender costs
nothing at 18pt once it is drawn for 18pt - which is what turned "p in the Dock only" into "p
everywhere".

## Verified

- **The letterform, in alpha rather than by eye.** At row 32 of 36 the stem is opaque (1.00) and the
  tallest tile is transparent (0.00). Both halves are needed: opacity alone passes on a mark with no
  descender, transparency alone passes on an empty image.
- **Planted**: the stem shortened to match the other tiles. Caught by that test and only that test.
- **The whole chain**: SVG -> PNG -> `.icns`, unpacked from the BUILT bundle and looked at.
- **All four menu states** rendered as the app composites them - idle and active, each plain and
  badged. The descender is visible in every one, including inside the active knockout.

## Versioning

`Resources/icons/` holds both designs; `ICON_VARIANT` in `scripts/render-icon.sh` selects one.
v1-level-meter is one line away if this ever needs to come back, and it is kept as a file rather than
only in git history because a design you have to `git show` to look at does not get compared.
