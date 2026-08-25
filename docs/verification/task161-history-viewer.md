# Task 161 - History becomes a viewer, and rendering finds four things reading did not

Measured 2026-08-24 on macOS 26.6.2.

---

## 1. What was there

`Open History File` handed `history.jsonl` to whatever plain-text editor resolved (#154). That was
a fix for a real dead end - the file previously had no handler at all - but it gave the user the
FORMAT rather than their content: one JSON object per line, ISO-8601 timestamps, no way to find
anything.

The dictionary got a real editor in #156. History is the surface with more content in it and did
not.

## 2. What the model decides

The rules with right and wrong answers live in `HistoryViewerModel`, not in the view:

| Question | Answer | Why |
|---|---|---|
| Which end of the file to open on | Newest first | The file is appended to, so it is oldest-first. Opening in file order lands on the user's oldest dictation and buries today's under the 500 the store keeps. |
| A query of spaces | Shows everything | It is what a trackpad and a stray thumb produce. Treating it as a search empties the window and reads as "your history is gone". |
| What gets searched | `text` only | Searching the record's storage would let "2026" match every dictation from this year while matching nothing anyone said. |
| Nothing found vs nothing recorded | Two different sentences | Only one of them means their history was deleted. |

All six claims were established by planting, one plant per claim. Five fired immediately.

**The sixth did not, and that is the useful one.** `searchDoesNotMatchTheEncoding` originally
searched for `1970` and `T00:`. A plant that searched the ENTIRE record rather than its text sailed
straight through it - neither string appears in a record's description, so the test was green
against the exact regression it was written to catch. Rewritten with `2023`, `durationSeconds` and
`+0000`, which appear in some serialisation of the record and in none of its text, the plant fires.
The test was fixed; the code was already right.

## 3. What RENDERING found, and reading did not

`PUSHTEXT_MENU_PROBE_HISTORY=populated|empty|nomatch` opens the viewer on known records so all three
states can be captured. On a fresh install the real store is in the third, so rendering against it
would mean the state with all the layout in it never gets looked at.

Four defects, all invisible in source and all obvious in a screenshot:

1. **A search field over a history with nothing in it.** Nothing to search, and the field sat
   directly above the sentence explaining there was nothing there.
2. **"0 dictations" underneath "No dictations recorded yet."** The same fact twice, and the
   sentence says it better. This is the same class as #156's editor repeating its own window title.
3. **Two arrows on Open File.** `arrow.up.forward.app` drew an arrow glyph in front of the trailing
   arrow `LinkButton` already draws as its external affordance. Changed to `doc.text`.
4. **Open File offered for a file that does not exist.** `clear()` REMOVES the file, so after a
   Delete History the button pointed at nothing.

Fixes 1, 2 and 4 are one rule - `hasHistory`, which is deliberately NOT the same as "anything is
visible". A search that found nothing must keep its field, because that field is how the user undoes
the query that emptied the list.

Both are now covered by tests written from what the screenshots showed.

## 4. What this does NOT show

The window is opened by a probe, not by clicking `View History` in the menu. The menu action is
wired to `showHistory()` and that wiring is not covered by any automated check - the same gap
`docs/verification/task158-delete-history.md` records for Delete History, and for the same reason:
these actions are closures inside a `MenuAction` array.

Copy-to-pasteboard was exercised by hand, not by a test. `NSPasteboard.general` is process-global,
and a test that writes to it clobbers whatever the user has on their clipboard - which this session
already did once, to their Trash, with a test that used the production closure.
