# The menu-bar mark, sized against TermTile (#231)

Bobby, with the two apps side by side in his menu bar: *"the push text logo looks too large compared
to the termtile one -- i'd say grab that navbarmenu icon and start from that one."*

## Measured from the reference, not the screenshot

`~/Developer/termtile/Resources/TermTileMenuGlyph.svg` is on this machine, so the comparison is
against the real file:

| | TermTile | PushText before | PushText after |
|---|---|---|---|
| mark width | 14 | 16 | **14** |
| mark height | 12 | 16.5 | **12** |
| tile width | 2 | 2.286 | **2** |
| corner radius | 1 | 0.8 | **1** |
| pitch | 3 | 3.43 | **3** |

The width was nearly right. The **height was 38% over**, which is what read as oversized.

## The grid was never wrong

Both marks descend from the same five-column icon grid. Set the tile width to TermTile's 2 and our
columns land exactly on its pitch of 3, at x = 2/5/8/11/14, making the mark exactly 14 wide. Nothing
had to be re-spaced; only the vertical extent changed.

The shape is still ours: the icon's waveform (350/520/350/170) with column one carried into a
descender, scaled by 12/698 so it spans TermTile's y 3..15. Column one bottoms at 15.00 while the
tallest of the others stops at 11.94 - the descender survives the shrink, which is the point.

## The active state had to shrink too

It filled the whole 18pt box, which was defensible beside a 16.5-tall idle mark and absurd beside a
12-tall one: the listening state would have been twice the resting weight, trading one oversized icon
for another. It is now 14x14, inset by 2, with the mark knocked out at 0.7.

## Verified

- **Rendered beside TermTile's own glyph** at 18pt and magnified. Same footprint, same weight.
- **All four menu states** rendered as the app composites them - idle and active, plain and badged.
- **Two plants, two catches**:

| Planted | Caught by |
|---|---|
| stem shortened to match the other tiles | "the stem descends below every other tile" |
| active squircle grown back to the full 18pt box | "the active mark is a filled squircle with the bars knocked out" |

The second assertion is new: the very corner of the active glyph must now be TRANSPARENT, because
the squircle no longer reaches it. Without that, a full-box squircle could creep back unnoticed.

## Scope

The app icon is untouched. This was a menu-bar problem, and the icon is seen at a size where the
taller mark is correct.
