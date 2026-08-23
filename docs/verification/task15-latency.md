# Task 15 - Latency, measured

**Release-to-text is dominated by one term: `finishUtterance`. It is 47-210 ms depending on how
long you spoke, and it grows far slower than the utterance does.**

Measured 2026-08-22 on this machine - macOS 26.6.2, Xcode 26.6, Apple silicon - through the
packaged `.app`, not `swift run`. #15 exists because no published `SpeechAnalyzer` figure exists
anywhere: we cite our own numbers or none.

---

## 1. What was measured, and why that is the right thing

Push-to-talk hides almost all of its own cost. Transcription streams **while the user is still
speaking**, so the only part they experience is the tail: what happens after they let go of the
key. Anything measured before that point is free.

So the number is `finalize` - wall clock inside `AppleSpeechEngine.finishUtterance()` - with audio
delivered at **realtime pace**, because unpaced delivery would let the analyzer run ahead of a
speaker who does not exist and shrink the tail into something no user will ever see.

`TranscriptionProbe` now reports four phases. Timing is `ContinuousClock`, which does not jump if
the wall clock is adjusted mid-run.

| phase | what it covers | who waits for it |
|---|---|---|
| `begin` | `beginUtterance` - transcriber construction, asset check, analyzer start | the user, at press |
| `deliver` | appending every buffer | nobody - overlaps speech |
| `finalize` | `finishUtterance` | **the user, at release** |
| `total` | all three | - |

## 2. The instrument was checked before its numbers were used

`deliver` exists to check the clock, not to report anything. Under realtime pacing it must land near
the audio duration; unpaced it must collapse. On the same 2.03 s clip:

```
paced:    deliver=2173.3ms
unpaced:  deliver=3.1ms
```

It measures elapsed time. Had `deliver` come out near zero while paced, every other number on this
page would have been arithmetic rather than measurement.

## 3. Results - 5 runs at each of three lengths

Generated with `say`, spanning the edges: a one-line command, a two-sentence thought, and a long
unbroken monologue.

| utterance | audio | n | `finalize` min | median | max | per second of audio |
|---|---|---|---|---|---|---|
| short | 2.03 s | 5 | 47.4 ms | **49.4 ms** | 50.4 ms | 24.3 ms/s |
| medium | 9.97 s | 5 | 115.8 ms | **120.8 ms** | 127.1 ms | 12.1 ms/s |
| long | 46.25 s | 5 | 177.1 ms | **205.4 ms** | 210.4 ms | 4.4 ms/s |

**It is strongly sub-linear.** A 23x longer utterance costs 4.2x more finalize time. Whatever
`finishUtterance` does, it is not reprocessing the audio - the per-second cost falls by 5.5x from
the short clip to the long one. The practical reading: dictating a paragraph is not meaningfully
worse than dictating a sentence.

Variance is small - the widest spread is 33 ms, on the long clip.

`begin` is flat at **115-155 ms (median 123.6)** across all 15 runs, independent of utterance
length, which is what a fixed setup cost should look like. It lands at PRESS, where the user is
about to start speaking anyway. **Caveat: every run here had the model already installed.** On a
machine where it is not, `beginUtterance` blocks on a download instead - that is #36, and these
numbers say nothing about it.

## 4. The other terms are small, and one of them is not what it looks like

Pasteboard work, measured through `InjectionProbe` in clipboard-only mode (3 runs each at 27 and
310 characters):

```
snapshot=1.47-2.74ms   stage=0.42-1.31ms   restore=0.53-2.56ms
```

Flat with text length - 310 characters cost no more than 27. Call it **2-3 ms** between a finished
transcript and the Command-V.

**The injector's 120 ms `pasteSettleDelay` is NOT user-visible latency.** It is waited *after* the
key is posted, so the text has already appeared; the wait exists so the clipboard is not restored
out from under an app that has not read it yet (#27). Counting it as latency would overstate the
number the user feels by more than double.

## 5. What this does NOT establish

- **Not the end-to-end app number.** This measures the engine and the pasteboard, not mic teardown,
  the state machine, or the HUD. The only end-to-end datum this project has is **221 ms** on a
  2.43 s utterance, from #42 - subtracted by hand from two os_log timestamps, n=1. Against a 49 ms
  finalize, that leaves roughly 170 ms unaccounted for. `AppModel` now emits
  `releaseToText=<n>ms` directly, so real dictations produce the figure instead of requiring
  arithmetic on a log.

  **SAMPLED 2026-08-23**, two real dictations driven end to end - synthetic Right Option, speech
  played aloud into the microphone, text landing in TextEdit:

  ```
  released 06:25:26.147 -> injected 06:25:26.399    252 ms (from timestamps)
  injected chars=40 releaseToText=275ms             275 ms (logged directly)
  ```

  Consistent with #42's 221 ms, and roughly 5x the 49 ms engine finalize for a short utterance. The
  gap is mic teardown, the state machine and the HUD, and it is now measured rather than inferred.

  The first of those two runs is also why the log line reads `privacy: .public`: it originally
  printed `releaseToText=<private>ms`, because os_log redacts interpolated strings by default while
  the numeric `chars=` beside it needed no annotation. An instrument added to be read, that could
  not be read.
- **Nothing about cleanup.** `FoundationModelsCleanup` is written and NOT wired into the live
  pipeline, so it costs zero today. Wiring it in adds a model call between finalize and injection,
  and that has not been timed.
- **Nothing about a cold model.** See #36.
- **One machine.** Apple silicon, idle, mains power. Nothing here speaks to thermal throttling, a
  busy machine, or different hardware.
- **Synthetic speech.** `say` output is cleaner than a human in a room; it should not affect
  finalize timing, but it is not human audio and this was not tested against any.

## 6. Reproducing

```sh
say -o clip.wav --data-format=LEF32@48000 "..."
PUSHTEXT_TRANSCRIBE_PROBE=1 \
  PUSHTEXT_TRANSCRIBE_PROBE_REALTIME=1 \
  PUSHTEXT_TRANSCRIBE_PROBE_FILE="$PWD/clip.wav" \
  dist/PushText.app/Contents/MacOS/PushText
```

Drop `PUSHTEXT_TRANSCRIBE_PROBE_REALTIME=1` to see the instrument check in section 2 go the other
way.
