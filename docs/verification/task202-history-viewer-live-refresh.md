# The history window refreshing while it is open (#202)

Bobby opened Dictation History, recorded a new dictation, and it never appeared. His screenshot
showed the window reading **22 dictations** with the newest at 5:20 PM while the menu's LAST
TRANSCRIPT read "Testing." - a dictation that existed and was not in the list.

## The defect, and the comment sitting on top of it

`HistoryViewerModel` held `private let records`, loaded once in `init`. `HistoryViewerWindow.show()`
carried this:

> Re-read on every open. History grows while the window is closed, and a viewer showing a stale copy
> of a file the app is actively appending to is worse than no viewer.

The hazard was named correctly and then half-closed. REOPENING re-read; the window staying open -
which is what a person actually does while dictating - was left in exactly the state the comment
described.

## A second defect the first fix would have introduced

`Row.id` was the index into the DISPLAY order, which is newest-first. `TranscriptRow` keys its
`@State copied` off that id, so prepending a record renumbers every row: a copy checkmark would jump
to whatever transcript had taken that position. Numbering now counts from the oldest record, which
does not move when a dictation arrives.

## What the probe found that 435 green tests did not

The first design polled the file once a second. Every model test passed. On the real path the window
did not change: **before.png and after.png were byte-identical, SHA-256 `4a95271546fbcb17...` both.**

Instrumenting the tick showed the timer firing ZERO times, while the arm site reported
`main=true sameRunLoop=true mode=kCFRunLoopDefaultMode`. The first explanation reached for was App
Nap. `sample` said otherwise:

```
__44-[SPUStandardUpdaterController startUpdater]_block_invoke  (in Sparkle) + 356
  -[NSAlert runModal]  (in AppKit) + 196
```

The main thread was parked in a MODAL run loop. Sparkle cannot check for updates from an unbundled
SPM binary and says so with an alert; a modal run loop starves default-mode timers *and* the main
dispatch queue, so `Timer` and `DispatchQueue.main.asyncAfter` failed identically and the window
stopped redrawing. Nothing was wrong with the timer, and the App Nap explanation was wrong - it is
recorded here because it was written into two code comments before the stack was read.

Two consequences:

- `ProbeActivation.isProbeProcess` now keeps Sparkle out of any probe process. Every render probe in
  this repo was screenshotting an app whose main thread was blocked; they got away with it because
  they only ever needed one static frame.
- The refresh is a NOTIFICATION, not a poll. `JSONLHistoryStore` posts `.historyDidChange` on append
  and on clear, and the open window re-reads. This was chosen on its merits - instant, free when
  nobody is dictating, no timer alive for a window open for hours - not because polling was proven
  broken in production. It was not.

## Measured, on the real path

`PUSHTEXT_MENU_PROBE_HISTORY=live` opens the viewer on the real store; `PUSHTEXT_HISTORY_PROBE_APPEND`
writes one dictation THROUGH `JSONLHistoryStore.append` two seconds later, so the chain under test is
append -> notification -> listener -> refresh -> redraw. `PUSHTEXT_HISTORY_FILE` keeps all of it off
Bobby's own history.

```
window=8315
BEFORE captured with 2 records on disk
in-app append reported: yes  (file now 3 records)
AFTER captured
before=4a95271546fbcb17 after=f03f27bb91e71ee9
VERDICT: window changed
```

Read off the two frames rather than the hash: the third dictation appears at the top of the list and
the footer goes from **2 dictations** to **3 dictations**, with nothing touching the window.

The probe fails CLOSED. When the in-app append did not happen it printed `THE PROBE ITSELF NEVER
APPENDED - verdict is inconclusive, not negative` and exited 1, rather than reporting an unchanged
window as a failed fix.

## What this does and does not cover

- Covered: any change PushText itself makes - a dictation completing, and Delete History emptying an
  open window.
- NOT covered by the notification: someone editing `history.jsonl` in another application. Nothing
  posts for that. `windowDidBecomeKey` re-reads, so it is picked up when the user returns to the
  window, which is when they would look anyway.
- Still not proven by `swift test`: that `TranscriptFinisher` calls `append` after a real dictation.
  That is pre-existing behaviour with its own tests, and the probe starts one step downstream of it.

## Tests, each made to fail on purpose

Four defects were planted in the model and each was caught by the test written for it, with the
failure text naming the right value:

| Planted | Caught by |
|---|---|
| `refresh()` does nothing | new dictation, and cleared history |
| `refresh()` clears the user's query | keeps what the user typed |
| reload on every tick, ignoring the stamp | an unchanged file is not re-read (`loads 4 == 1`) |
| ids numbered from the newest end | a transcript keeps its id (`idBefore 0 == idAfter 1`) |

The id plant reproduces the pre-change numbering exactly, which is what shows that test
discriminates against the old behaviour rather than merely passing on the new one.

`HistoryStoreReadingTests` exists because of a near-miss: `HistoryReading` carries a default
`changeStamp()` returning nil for fixtures, and a real store whose concrete method failed to bind as
the witness would silently take it - comparing nil to nil forever and never re-reading, which is
identical to having no fix at all and invisible to every test that supplies its own double.

The notification test first counted **four posts for one append**: suites run in parallel and the
broadcast carried no sender. The notification now identifies its store.
