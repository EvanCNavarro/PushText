# Task 105 - Double-press latching, driven on the real event tap

**Latching never worked, and the cause was a race lost by about 4 milliseconds.** Fixed by deciding
tap-versus-dictation from the press DURATION rather than from which state won the race.

Measured 2026-08-23 on macOS 26.6.2, through the packaged `.app`, with synthetic right-Option events
carrying the real device bit.

---

## 1. Before

```
17:34:52.413  hotkey edge=pressed              state idle -> arming
17:34:52.483  capture started        (+70 ms)  state arming -> recording
17:34:52.487  hotkey edge=released   (+74 ms)  state recording -> transcribing
17:34:52.676  hotkey edge=pressed              <- the double press
17:34:52.677  state transcribing -> failed(noSpeechDetected)
```

The machine already carried the right rule:

```swift
// Released during arming: too short to be speech. Not a failure worth reporting.
case (.arming, .hotkeyReleased):
    return .idle
```

It never fired. Capture starts ~70 ms after `arming`; a tap releases ~74 ms after the press. The
machine had already moved to `.recording`, so the release took `(.recording, .hotkeyReleased) ->
.transcribing` and the tap became a 74 ms utterance. The second press then arrived while
`.transcribing`, where `.hotkeyDoublePressed` is unhandled - one millisecond before the `.failed`
transition that would have accepted it.

Across 6 attempts at two tap lengths, the latch never engaged on the first tap, and the first
utterance of every run was lost.

## 2. The fix

`PressPatternRecognizer` already computed `wasTap` to arm the double-press window, then threw it
away and returned a plain `.hotkeyReleased`. It now returns `.hotkeyTapReleased` instead, and the
machine transitions `(.arming, .hotkeyTapReleased)` and `(.recording, .hotkeyTapReleased)` to
`.idle`.

That is the same judgement the arming rule already made, applied where it actually bites. The
outcome no longer depends on a 4 ms margin.

## 3. After

Three latched dictations, speech spoken with the key RELEASED, one press to end:

```
state idle -> arming
state arming -> recording
state recording -> idle                <- the tap aborts cleanly
state idle -> arming
state arming -> recording
state recording -> transcribing
transcript chars=29
state cleaning -> injecting
injected chars=29
state injecting -> idle
```

3 of 3 attempts latched and injected exactly once. **Zero `failed(noSpeechDetected)` states**, against
one per attempt before.

## 4. What this does NOT change, and why

A tap still opens the microphone for ~70 ms before aborting - `arming -> recording -> idle` is
visible above. Removing that would mean delaying capture until the tap window (300 ms) expires,
which would add 300 ms to the start of every hold-to-talk dictation. Paying 300 ms on every real
dictation to avoid a 70 ms microphone open on every stray tap is the wrong trade, so capture stays
optimistic. No follow-up needed.

A press shorter than `tapMaximumDuration` (300 ms) now aborts rather than transcribing. Previously
it reached `.transcribing` and came back `failed(noSpeechDetected)`, so the user saw an error where
they now see nothing happen - which is what the machine's own comment already called correct.

## 5. Why the existing suite did not catch it

`PressPatternRecognizer` is pure, correct, and well tested; it emitted `.hotkeyDoublePressed` exactly
as specified. The bug was that the MACHINE was no longer in a state that accepts it.

The unit test for latching (`doublePressLatches`) passes on the broken code, because it never
delivers `audioStarted` between the press and the release - so the machine is still `.arming` when
the tap is released, the old rule handles it, and the race the real tap loses never happens in the
test. The new test delivers `audioStarted` on purpose, and asserts the precondition
`state == .recording` before releasing.
