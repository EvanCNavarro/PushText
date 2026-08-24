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

## 4c. Attribution: the prewarm always runs, and the model call is binary

#94's trigger asked for one slow dictation to be attributed, because "prewarm never ran" and
"prewarm ran and the model was cold anyway" are different bugs. `clean` now records `wasWarm` and
the milliseconds spent inside the model call alone, logged per dictation.

12 dictations, two batches of six, machine quiet (press count checked against the harness both
times).

| warm | model call | release-to-text |
| --- | --- | --- |
| true | 277 ms | 545 ms |
| true | 422 ms | 590 ms |
| true | 3426 ms | 3648 ms |
| true | 3515 ms | 3678 ms |
| true | 269 ms | 1384 ms |
| true | 304 ms | 524 ms |
| true | 3559 ms | 3813 ms |
| true | 400 ms | 573 ms |
| true | 3421 ms | 3637 ms |
| true | 3530 ms | 3712 ms |
| true | 263 ms | 440 ms |
| true | 3513 ms | 3727 ms |

**`warm=true` on 12 of 12.** The key-down prewarm completes every time.

**The model call is binary, not variable:**

- resident: n=6, mean **322 ms**, range 263-422
- not resident: n=6, mean **3494 ms**, range 3421-3559 - a spread of just **138 ms**

The difference is a near-constant **3172 ms**. A cost that reproducible is a discrete step - loading
model assets - not contention or thermal variation. It lands on **50%** of dictations.

### What this disproves

The previous section blamed backgrounding: prewarming is documented as not guaranteeing asset
loading while an app is backgrounded, and this app is backgrounded permanently. That was recorded as
INFERRED, and it is now **wrong**. The prewarm is not being refused; it runs, a warmed session
exists, and the assets still are not resident when the transcript arrives.

### A limit of this instrument, stated plainly

`wasWarm` reports that a session built at key-down was still available - **not** that the model's
assets were loaded. `prewarm()` returns immediately, so `warm=true` and "cold model" are compatible
states, which is exactly what these 12 samples show. Anyone reading this field later should not
treat it as a residency signal.

### What the API allows next

`LanguageModelSession(model:tools:transcript:)` exists, so a session can be constructed with a given
transcript. That matters because this implementation discards the session after each utterance to
stop one dictation's context leaking into the next - and if residency is tied to a live session,
those two goals looked mutually exclusive. With that initialiser they are not. Whether residency is
tied to a live session at all is UNTESTED and is #94's next step.

## 4d. Residency: three arms, one answer

#94's last open question was whether the ~3.5 s model call could be made to go away. Two levers were
named in its trigger. Both were run, six dictations each, same phrases, same 22 s spacing, same
session, cleanup enabled through the setting.

| arm | n | mean | median | fast (<1 s) | values |
| --- | --- | --- | --- | --- | --- |
| A - session spent per utterance (shipping) | 6 | 3744 ms | 3491 ms | **0/6** | 3416, 3466, 3476, 3506, 3534, 5065 |
| B - one session held across utterances | 6 | 4496 ms | 3958 ms | **0/6** | 3776, 3856, 3865, 4050, 4308, 7124 |
| C - `prewarm(promptPrefix:)` | 6 | 2432 ms | 3488 ms | 2/6 | 213, 328, 3465, 3512, 3523, 3549 |

**B is disproved.** Holding a session is not merely no better, it is worse - and it costs context
growth, since `LanguageModelSession` carries its transcript. Model residency is not tied to a live
session.

**C is not evidence.** Two fast samples out of six looks encouraging until it is compared to the
variance the UNMODIFIED path already shows.

### The observation that settles it

The same shipping configuration measured **6/12 fast (50%)** in an earlier session and **0/6 fast**
in arm A today.

That between-session swing is larger than any between-arm difference measured today. Whatever
governs whether the assets are resident is not something this process sets - not the session, not
the prewarm shape. Arm C's 2/6 sits inside that spread.

The slow mode itself is remarkably tight in every arm: 3416-3549 in A, 3465-3549 in C. A cost that
reproducible is a discrete load step, not contention.

### Neither seam was kept

Both experiment flags were removed. A disproved flag left in shipping code invites the next reader to
try it again, and the measurements live here instead. Re-adding either is about ten lines, and this
section says exactly what they were.

## 5. What ships

`TranscriptFinisher` and the ordering it enforces (cleanup, then the user's dictionary, then
history), plus the key-down prewarm. `PushTextApp` still does **not** construct a cleanup provider,
so behaviour is unchanged and transcripts ship as the recognizer produced them.

Cleanup is now a user-facing toggle, default off, with the cost stated in the menu (#103). Section 4d
records why it is not on by default: the asset load cannot be prevented from inside this process.
