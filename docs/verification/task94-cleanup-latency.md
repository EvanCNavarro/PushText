# Task 94 - Wiring cleanup, measured

**Cleanup works, the drift guard works, and cleanup still must not ship on by default: it costs
~4.0 seconds of release-to-text, a 20x regression on the only interaction the app has.**

Measured 2026-08-23 on macOS 26.6.2, through the packaged `.app`, against the real on-device
`SystemLanguageModel` and the real `SpeechTranscriber`.

---

## 1. The measurement

Same four phrases, same session, same machine, spoken by `say -r 175` at output volume 65, each
dictation separated by 22 s so no keypress lands while the previous one is still cleaning. The only
difference between the arms is whether `PushTextApp` constructs a `FoundationModelsCleanup`.

| phrase | without cleanup | with cleanup |
| --- | --- | --- |
| "Send him the invoice today" | 275 ms | 4176 ms |
| "I think we should ship the update on Friday and tell the team about it" | 169 ms | 4289 ms |
| "Meeting at three" | 222 ms | 4113 ms |
| "The quarterly numbers came in higher than we expected" | 158 ms | 4149 ms |

Mean 206 ms against 4182 ms. Every sample in the cleanup arm is within 176 ms of every other, so
this is not one slow outlier - it is the cost of the stage.

`releaseToText` is measured from the hotkey release to the text being injected. It is the number the
user experiences as "how long after I let go does my text appear".

## 2. The 22-second gap is not padding, it is a second finding

The first attempt spaced dictations 8 s apart. The log shows a `hotkey edge=pressed` arriving while
the machine was still in `cleaning`, and that press was **swallowed** - an entire utterance was lost
because the previous dictation had not finished polishing.

So the cost is not only waiting. At ~4 s per dictation, a user speaking at a normal pace loses
utterances, and nothing tells them why.

## 3. What the on-device model actually costs

`CleanupProbe`, driving the same model directly, is far faster once the system model is warm:

```
CLEANUP_PROBE raw="Send him the invoice today"
CLEANUP_PROBE cleaned="Send him the invoice today."
CLEANUP_PROBE changed=true rejection=none
CLEANUP_PROBE cleanMillis=259
```

Across probe runs: 9818, 6780, 6780, 3880, 350, 259 ms. The spread is warm-vs-cold, not input
length. The app's steady ~4.15 s therefore looks like each dictation paying a partial re-warm,
because a backgrounded menu-bar utility dictating once every 20 s never keeps the model hot.

**This is the number to attack.** If cleanup can be kept warm, the stage costs ~300 ms and the
argument changes completely. That is not a thing this task measured, and it is not assumed here.

## 4. A hallucination that was NOT cleanup's

The first run pasted `Send Emily an invoice today.` for a phrase spoken as "Send him the invoice
today". That looks exactly like the failure the drift guard exists to prevent, and it is not.

Reconstructed from the character counts in the log (`transcript chars=25`, `injected chars=28`) and
then confirmed by driving the real model:

```
CLEANUP_PROBE raw="Send Emily invoice today."
CLEANUP_PROBE cleaned="Send Emily an invoice today."
CLEANUP_PROBE changed=true rejection=none
```

`SpeechTranscriber` misheard "him the" as "Emily" and produced `Send Emily invoice today.` (25
characters). Cleanup then added the article "an" - a **function word**, which the grounding check
permits by design - giving 28. Both components behaved correctly.

The guard was checked directly against the pair it was accused of missing, and it rejects it:

```
VERDICT: rejected(ungroundedContent(token: "emily"))
RAW TOKENS:   ["send", "him", "an", "invoice", "today"]
CLEAN TOKENS: ["send", "emily", "an", "invoice", "today"]
```

That verdict is what proves cleanup could not have introduced the name: had it done so, the raw text
would not have contained "emily" and the guard would have refused the candidate. The name was in the
transcript before cleanup ever saw it.

Recorded because the wrong version of this story - "the LLM invented a name" - is far more memorable
than the right one, and would have sent the next reader to fix the wrong component.

## 4b. Prewarming: it works, and it lands 43% of the time

`LanguageModelSession.prewarm()` is now called at key-down (`.arming`), so the warm-up overlaps the
user's speech instead of their wait. Re-measured across 21 dictations through the packaged app.

| arm | n | mean | median | min | max |
| --- | --- | --- | --- | --- | --- |
| no cleanup | 4 | 206 ms | 196 ms | 158 | 275 |
| cleanup, no prewarm | 4 | 4182 ms | 4162 ms | 4113 | 4289 |
| cleanup + prewarm | 21 | 2529 ms | 3590 ms | 452 | 7564 |

**The mean is the wrong summary - the distribution is bimodal**, which is why the median is worse
than the mean:

- **fast mode**, n=9, mean **624 ms**: 452, 463, 507, 581, 582, 603, 756, 829, 846
- **slow mode**, n=12, mean **3957 ms**: 1857, 3590, 3613, 3637, 3644, 3656, 3673, 3683, 3804,
  3855, 4913, 7564

The slow mode's mean (3957 ms) is the unwarmed cost (4182 ms) within noise. So prewarm does not
shave time off a cold start - it either completes before the transcript arrives, giving ~624 ms
against the probe's 259 ms warm figure, or it contributes nothing. **Fast share: 43%.**

### The likely cause, named before it was measured

Prewarming is documented as not guaranteeing asset loading **while the app is backgrounded**.
PushText is an `LSUIElement` menu-bar app, so backgrounded is not an edge case here - it is the only
state the app is ever in. This was written down as a risk before the measurement and the measurement
is consistent with it. INFERRED: nothing here attributes a single slow sample to a refused prewarm.

### What was ruled out

Utterance length does not explain the split. One clean run had 5 s and 4 s holds slow (3683,
3637 ms) with 8 s and 7 s holds fast (582, 463 ms), which looks decisive - and an earlier run
contradicts it outright, with a 5 s hold at 756 ms and a 7 s hold at 3590 ms.

A dedicated hold-duration sweep (3/5/7/9/11/13 s, same phrase) failed to control its own variable:
transcript lengths came back 17, 58, 59, 16, 83 and 40 characters for what should have been one
constant phrase, because ambient audio entered the capture. Those six samples are included in the
totals above but cannot answer the question they were designed for.

### Measurement hygiene

Two of the four runs were contaminated by the machine's owner dictating concurrently - visible as
more `hotkey edge=pressed` lines than the harness issued (5 and 6 against an expected 4). Runs are
now checked with a press count. The 21 samples include those runs; the press-count check is what
makes that disclosable rather than invisible.

## 5. What ships

`TranscriptFinisher` and the ordering it enforces (cleanup, then the user's dictionary, then
history), plus the key-down prewarm. `PushTextApp` still does **not** construct a cleanup provider,
so behaviour is unchanged and transcripts ship as the recognizer produced them.

Enabling it is one line. What has to be true first is section 4b: make the prewarm land more than
43% of the time, or accept that most dictations cost ~4 s. Tracked in #94.
