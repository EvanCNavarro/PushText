# Task 197 - A dictation past 120 seconds was destroyed, not transcribed

Measured 2026-08-25 on macOS 26.6.2.

Bobby: *"i just recorded for a long time and it seems like it just died out? and i lost all of that
information i was talking on."*

---

## 1. What happened, read off the code

`CaptureWatchdog.maximumDuration` was **120 seconds**. On expiry:

```
(.recording, .watchdogExpired) -> .failed(.cancelled)     DictationState.swift
case .failed: ... Task { await self.teardown() }          AppModel.swift
func teardown() { ... await feed.cancel(token) }          AppModel+Teardown.swift
```

`feed.cancel(token)` abandons the utterance. Nothing is transcribed, nothing reaches history.
**Everything spoken was discarded by a timer.**

It was worse than an accident: a test ASSERTED it.
`watchdogClosesStuckCapture` expected `.failed(.cancelled)`, so the data loss was pinned in place by
the suite. A second test in `AppModelTests` did the same. Both had to be rewritten before the bug
could be fixed, which is the tell that the behaviour was chosen rather than overlooked.

## 2. Could the lost dictation be recovered? No, and here is what was checked

- **Audio never touches disk.** It lives in an in-memory ring; `feed.cancel` released it.
- **`history.jsonl` ends at 20:26:11** with a 95.3 s entry - the one visible in his screenshot. It
  survived because it was UNDER the ceiling. Nothing after it: no transcript was ever produced.
- **No temp audio artifacts** attributable to PushText under `/private/var/folders`.
- **Nothing in the unified log**: the app's `info` entries are not persisted, and no `error` was
  recorded for the cancelled utterance.

Unrecoverable. Stated plainly rather than softened, because the honest answer to "can you get it
back" is no.

## 3. Two defects, and the second is the real one

**The ceiling.** 120 s under a comment reading *"Generous on purpose: it exists to stop a stuck
microphone, not to cut off a long sentence."* Two minutes is not generous for a mode this app
advertises as *"Hands-free, press again to end"*.

**The response.** Even at a correct ceiling, a watchdog for a STUCK MICROPHONE should close the
microphone and KEEP what it heard. Cancelling is what a user asks for by cancelling; a timer expiring
is not a request to destroy work.

## 4. What actually constrains duration - checked, not assumed

Before raising the ceiling, the things that could break at twenty minutes:

| candidate | finding |
|---|---|
| audio ring buffer | ~2 s TRANSPORT window at 48 kHz, drained every 50 ms - length does not accumulate |
| on-device cleanup | `TranscriptFinisher` returns the RAW transcript on every cleanup failure path, so a transcript too long for the model loses its polish and never its words |

Nothing structural wanted 120. The only cost of a longer window is how long a genuinely stuck
microphone stays open - and since expiry now transcribes rather than discards, that trade is far
cheaper than when the number was chosen.

Set to **1200 s (20 minutes)**, matching what Wispr Flow allows, which is the comparison the user
actually makes.

## 5. The user is told

`.arming` still cancels: the microphone never opened, so there is nothing to keep, and transcribing
an empty capture would inject an empty string over whatever they were doing.

When the ceiling ends a capture, the transcript card now says so, and that message WINS over a
capture-health warning - being cut off explains a transcript that stops mid-sentence, and a
dropped-frame count does not. The words being kept is half the fix; saying why they stop is the other
half, because "it just died out" was a description of silence, not of a crash.

## 6. Three plants, all caught

| plant | result |
|---|---|
| revert to `.failed(.cancelled)` on expiry | **2 tests FAIL** |
| put the ceiling back to 120 s | **FAIL** |
| make `.arming` transcribe instead of cancel | **FAIL** |

The ceiling has its own assertion so that lowering it is a deliberate act with a failing test
attached, rather than a quiet edit to a constant - which is exactly how it reached production at 120.

## 7. What this does NOT show

No twenty-minute dictation has been run end to end. The reasoning above establishes that nothing in
the pipeline ACCUMULATES with length, but the longest capture actually observed in `history.jsonl` is
95 seconds. A real long-form run would be the measurement, and it has not been taken.
