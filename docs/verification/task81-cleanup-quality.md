# Task 81 - Is cleanup worth putting on the dictation path?

**No, on this evidence. R2 stands and cleanup stays off.** It changes 4 transcripts in 20, the
useful part of what it changes is ordinal expansion that needs no model, it costs ~305 ms warm and
**6.8 s cold**, and in one of four cases it made a misrecognition read more plausibly - which is the
exact harm `PLAN.md` R2 was written about.

Measured 2026-08-23 on macOS 26.6.2 through the packaged `.app`, real on-device `SystemLanguageModel`.

---

## 1. The question R2 actually poses

`PLAN.md:253`:

> | R2 | Cleanup degrades good ASR | Apple: every LLM config worsened 2.2% baseline | Drift guard
> sec 2.6; **cleanup off by default until measured** |

"Until measured" is a QUALITY condition. #68 measured how often the drift guard *allows* cleanup to
run and said so explicitly - *"never whether its output is better than the raw"* - so it could not
settle this.

## 2. Method

The 20 real `SpeechTranscriber` transcripts from #68 (sentences spoken with `say`, transcribed by
the real engine), each fed to `CleanupProbe`. Judged against the ORIGINAL SPOKEN TEXT, not against
the raw transcript - "better" is meaningless without ground truth, and a cleanup that makes a
misrecognition more fluent scores well against the raw while being worse for the user.

## 3. Cleanup does nothing to 16 of 20

That is the headline and it is not a defect: `SpeechTranscriber` already punctuates and capitalises
at 99.9% / 99.7% (`docs/research/06`). There is very little left to tidy, so most of the time the
model returns the input unchanged and the stage is pure cost.

## 4. The four it did change

| # | spoken | raw | cleaned | verdict |
|---|---|---|---|---|
| 3 | "...for the first release." | "...for the **1st** release." | "...for the **first** release." | **better** - matches what was said |
| 19 | "...on the first launch." | "...on the **1st** launch." | "...on the **first** launch." | **better** - matches what was said |
| 11 | "...to the design **doc** when..." | "...to the design **like** when..." | "...to the design when..." | mixed - drops a spurious word, does not recover "doc" |
| 18 | "**How many users** signed up last month." | "I'll imagine he was **a** signed up last month." | "I'll imagine he was signed up last month." | **worse** - see below |

**Utterance 18 is R2 in miniature.** The transcript is a total misrecognition. Cleanup did not fix
it - it cannot, it never heard the audio - it fixed the GRAMMAR, turning obviously-broken text into
a fluent sentence that is still wrong. Broken text announces itself; fluent nonsense does not. The
user is now likelier to paste it without noticing.

**And the two clear wins are ordinal expansion**, which is a deterministic string transformation. A
lookup table does `1st -> first` in microseconds with no model, no variance and no chance of
inventing anything - a strictly better trade than a language model for the same result.

## 5. Latency: the disqualifier, independent of quality

In-process, timed around `clean()` alone rather than around the process:

```
run 1: 6841 ms     <- cold
run 2:  561 ms
run 3:  305 ms
run 4:  304 ms
run 5:  305 ms
run 6:  313 ms
```

Against the measured finalize times (`docs/verification/task15-latency.md`: 49 / 121 / 205 ms median
for 2 / 10 / 46 s of speech), adding cleanup means:

| | release-to-text now | with cleanup, warm | with cleanup, cold |
|---|---|---|---|
| short utterance | 49 ms | ~355 ms | **~6.9 s** |

**The cold number is the one that matters.** PushText is used intermittently - that is what a
dictation utility IS - so the model will frequently be cold, and a 6.9 s wait after releasing the
key is indistinguishable from the app being broken. It is the same defect #36 just removed from
`beginUtterance`, reintroduced at the other end of the pipeline.

An earlier estimate of 431-811 ms was process-inclusive and warm; it understated the cold case by an
order of magnitude. Timing the process instead of the call is what hid it.

## 6. Verdict

**Cleanup stays off.** R2 is confirmed rather than lifted:

- value is small and rare - 4 changes in 20, of which one is harmful
- the real wins are ordinal expansion, obtainable deterministically for free
- the cost is +305 ms always and +6.8 s on the first use after idle

`FoundationModelsCleanup` stays in the tree, tested and unwired, which is now a recorded decision
rather than an unexplained gap. #18 (per-app formatting) was going to build on cleanup and should be
re-scoped or closed on the strength of this.

## 7. What this does NOT establish

- **SYNTHETIC SPEECH, and this is the limit that could overturn the verdict.** Every transcript came
  from `say`, which produces fluent, already-well-formed speech. Cleanup's advertised value is
  removing filler and disfluency - "um", "you know", false starts, restarts - and `say` emits none
  of it. On genuinely messy human dictation the change rate could be far higher than 4/20 and the
  balance could flip. **A rerun on 20 real human utterances is the one thing that would change this
  answer**, and it is why the verdict is "on this evidence" rather than "settled".
- **One judge, no blinding.** I compared cleaned to spoken and scored it myself.
- **Nothing about a different prompt.** `FoundationModelsCleanup.defaultInstructions` was not varied;
  a prompt that explicitly refused to touch content words might avoid utterance 18 entirely.
- **Cold latency has n=2, not n=5.** 6841 ms in-process here, and 4241 ms process-inclusive in an
  earlier batch - two independent first-calls-after-idle, agreeing on the ORDER (seconds, not
  hundreds of milliseconds) rather than on a figure. The verdict leans on that order of magnitude,
  so it is worth saying plainly that the precise number is not established. The warm figure has n=5
  and is tight (304-313 ms after the first two).
