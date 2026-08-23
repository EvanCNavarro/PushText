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

## 5. What ships

`TranscriptFinisher` and the ordering it enforces (cleanup, then the user's dictionary, then
history). `PushTextApp` does **not** construct a cleanup provider, so behaviour is unchanged and
transcripts still ship as the recognizer produced them.

Enabling it is one line. What has to be true first is section 3: keep the model warm, or accept
~4 s. Tracked in #94.
