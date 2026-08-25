# Task 167 - Fuzzy transcript search, and a highlight whose contrast was measured

Measured 2026-08-25 on macOS 26.6.2.

---

## 1. Why word-level and not the obvious algorithm

The reflex answer to "fuzzy search" is a subsequence match, the way a file finder works. It is wrong
for prose, in two ways that only show up once you try it:

- `btf` would match "**B**ook a **t**able **f**or four". Every long transcript matches nearly every
  short query, so the filter stops filtering.
- The highlight would be scattered single characters across a sentence. Unreadable, and useless as
  the thing that tells you WHY a result is a result.

People search their dictation history for WORDS they said. So the matcher works on words:

| Rule | Why |
|---|---|
| A query word matches a transcript word by substring, or within an edit distance | "invoce" is the dictation you half-remember, typed the way you remember it |
| Budget: 1 edit for 4-6 characters, 2 for 7+ | Scales with the word; a long word tolerates more |
| Words under 4 characters are matched EXACTLY | At three characters "car" is one edit from "cat", "cot", "can" and "bar". Fuzzing them turns search into noise |
| Every query word must match something (AND) | Typing a second word has to NARROW the list. A search that widens as you type cannot be used to find anything |
| Case and diacritics folded | Someone searching for what they said types "cafe"; the transcript may say "Café" |
| Punctuation is not part of a word | "invoice," matches `invoice`, and the highlight covers the word rather than the comma |

Nine tests, nine plants, one per rule.

**Eight fired on the first attempt. One did not, and it is the useful one.** The
ordered-and-disjoint test searched a SINGLE word, and passed with sorting and merging both removed -
one token's hits come back in document order already, so there was nothing to sort and nothing to
merge. It was green against the exact defect it existed to catch. Rewritten with two tokens, the
later word typed FIRST and a second token landing on a word the first already hit, the plant fires.

That is the second time in two days a plant has caught a test rather than a bug.

## 2. The highlight, with numbers

Bobby asked for the update indicator's orange - `Tokens.warning`, `#F0A245` - as a soft background,
and for the text itself to be "the best accessibility and pattern for that".

Composited and measured rather than eyeballed:

```
  warning #F0A245 on Tokens.row:  7.91:1   (orange TEXT, if it had been used that way)
  text on row, unhighlighted:    15.02:1

  body text over a warning-tinted highlight:
    alpha 0.20 -> bg rgb(71, 56, 39)   text 10.15:1
    alpha 0.25 -> bg rgb(82, 63, 41)   text  8.99:1   <- chosen
    alpha 0.35 -> bg rgb(103, 76, 45)  text  7.14:1
    alpha 0.45 -> bg rgb(124, 89, 49)  text  5.68:1
```

**0.25.** Body text sits at 8.99:1 - past WCAG AAA for body text - and the wash is still clearly a
wash rather than a block.

**The text stays near-white.** Turning the matched words orange was the obvious move and the worse
one: orange on an orange-tinted background loses most of that headroom, and orange already means
"attention" everywhere else in this app.

**Two cues, not one.** The matched words also go semibold. Colour alone must not carry meaning
(WCAG 1.4.1), and a menu-bar utility may well be read through a colour filter or on a badly
calibrated external display.

**Same hue as the update dot, deliberately.** Both marks mean "the thing you are looking for is
here". A second accent colour would be a second vocabulary.

## 3. What rendering showed

`PUSHTEXT_MENU_PROBE_HISTORY=match|fuzzy` opens the viewer already searching.

- **fuzzy**: typed `invoce`, and the highlight lands on **invoice** - the word matched, not the word
  typed. That distinction is the one a fuzzy search can get wrong invisibly, and a screenshot is
  where it becomes obvious.
- **match**: `invoice project`, both words marked in the same transcript, and the comma after
  "project" correctly outside the wash.

**The first `match` probe found a bug in my own probe, not in the app.** `invoice release` matched
nothing - and it was right to: the two words are in different dictations, and the query is an AND.
The screenshot said "No dictation matches that search", which is the correct answer to a question I
had asked badly.

## 4. What this does NOT show

Results stay in newest-first order rather than being ranked by match quality. That is a choice, not
an oversight: this is a chronological record, and re-ordering the list on every keystroke is
disorienting. If ranking is wanted it should be its own change with its own reasoning.

The highlight was looked at on this display only, in dark appearance. The tokens define one palette,
so there is no light-mode variant to check.

## 5. Still open from the update indicator arc (#138)

Bobby asked whether that arc ever finished. It did: the menu-bar icon, the `...` button and the
dropdown row are all wired, and #138 is closed.

Two of the three were rendered and looked at. **The dropdown row's own mark still has not been**,
because the popover only exists once the `...` is clicked and `OverflowMenu` keeps `open` as private
`@State`. An attempt to drive it with `cliclick` moved the cursor but posted no click - the
controlling process does not appear to hold Accessibility permission - and it was abandoned rather
than pursued. It remains covered by `OverflowAttentionTests` and unverified by eye, exactly as
`task138-update-indicator.md` already records.
