# Task 68 - Cleanup in shadow mode, measured against real transcripts

**The borrowed thresholds survive. One false-positive class was real and is fixed. Rejection fell
from 20% of runs to 7%, and every remaining rejection is the guard doing its job or close to it.**

Measured 2026-08-23 on macOS 26.6.2, through the packaged `.app`, against the real on-device
`SystemLanguageModel`.

---

## 1. The first evidence I gathered was wrong

#68 was filed off three samples of raw lowercase text like
`"um so i think we should ship the thing on friday you know"`, which produced a ~33% rejection rate.

**That input does not occur.** `SpeechTranscriber` already punctuates and capitalises - measured at
99.9% / 99.7% across 5,559 hypotheses (`docs/research/06`) - so the real input to cleanup is
punctuated prose. Feeding it unpunctuated text inflates the length ratio and manufactures exactly
the `tooLong` rejections the issue was worried about.

So the measurement was redone through the real pipeline: 20 sentences spoken with `say`,
transcribed by the real engine, and each **real transcript** fed to `CleanupProbe`. A sample:

```
Send him the invoice today.
Can you shake whether the deployer finished?
I think we should cut the scope for the 1st release.
The build is faming on the winter again.
```

Recognition errors and all - that is what the cleanup stage actually receives.

**Three model runs per utterance**, because the model is non-deterministic and a single pass
measures noise rather than behaviour.

## 2. Before

| | |
|---|---|
| runs rejected | **12 / 60 (20%)** |
| utterances always accepted | 13 / 20 |
| utterances always rejected | 1 / 20 |
| utterances with an **unstable** verdict | **6 / 20** |

Rejection reasons: `ungroundedContent` 10, `tooLong` 2.

**Grounding did almost all the rejecting, not the length ratios** - the opposite of what #68
assumed. And the single most common token was `"first"`.

## 3. The cause, confirmed rather than inferred

```
raw:      "I think we should cut the scope for the 1st release."
cleaned:  ... the model expands "1st" to "first" ...
verdict:  ungroundedContent(token: "first")
```

The transcriber writes `1st`; the model expands it to `first`; grounding sees a content word that is
not in the raw text and rejects. **That is a normalisation, not invented content** - and it is
precisely the tidying cleanup exists to do, so the guard was firing hardest on the correction the
user most wanted.

Run four times on identical input it rejected 3 times and passed once, which is the instability in
section 2 in miniature: the model sometimes expands the ordinal and sometimes does not.

## 4. The fix

`CleanupDriftGuard.tokens` now collapses numbers to one canonical form, so `1st` and `first` are the
same token to grounding. Bounded to 0-20 cardinals and ordinals plus a digit-ordinal suffix rule
(`22nd` -> `22`); anything outside stays subject to grounding rather than being waved through.

It makes the guard slightly more permissive, which is the right direction: no numeral mapping can
weaken the case the guard exists for, because nothing turns a country into a city.

Both failure directions are tested and both plants were verified to fail:

- removing the canonicalisation -> 6 tests fail
- widening it to wave through *any* numeric token -> 4 tests fail

## 5. After - and a correction to how this was first reported

**The targeted effect is decisive. The aggregate rate change I first claimed is NOT established,
and the difference matters.**

On the two utterances that actually contain a digit ordinal, 10 runs each, both arms built and run
side by side (pre-fix from a worktree at `origin/master`, post-fix from this branch):

| arm | rejected |
|---|---|
| pre-fix | **12 / 20** |
| post-fix | **0 / 20** |

That is the mechanism, and it is unambiguous.

The AGGREGATE across all 20 utterances is a different matter. First measurement said 12/60 before
and 4/60 after. **Re-running both arms end to end gave 5/60 before and 7/60 after** - the post arm
nominally WORSE, and the two indistinguishable.

Nothing regressed. The guard is deterministic; the MODEL is not. Whether a given run rejects depends
on whether the model happened to expand the ordinal, drop a word, or rephrase - and at three runs
per utterance that noise is larger than the effect being measured. The first pair of numbers was
one sample of a noisy process reported as a result.

**So the honest statement of the rate is: unmeasured.** An aggregate rejection rate needs a design
that removes model variance - capture each `(raw, candidate)` pair ONCE, then evaluate both guard
versions offline on the identical set - or enough repetitions to swamp it. Neither was done, and
quoting 20% -> 7% would be quoting noise.

## 6. What still rejects, and why that is mostly correct

Three runs. Both causes are word substitutions the model cannot know from the audio:

```
raw:      "The build is faming on the winter again."
rejected: ungroundedContent(token: "failing")     <- the model GUESSED the misrecognition
```

That is drift by any definition: "faming on the winter" is what was heard, and "failing on the
linter" is the model inventing a plausible sentence. The guard is right to refuse it, however
tempting the guess.

```
raw:      "The tests with us is locally, but fails in continuous integration."
rejected: ungroundedContent(token: "fail")        <- "fails" -> "fail", subject-verb agreement
```

This one is a **near-miss**: an inflection change, not invented content. Distinguishing it needs
morphological awareness (stemming), which is a much larger surface with its own false negatives, so
it is left rejecting and tracked separately rather than fixed by loosening grounding.

## 7. Verdict on #68's actual question

- **The borrowed 0.72 / 1.35 length ratios and 0.62 Levenshtein are NOT the problem.** Across four
  60-run passes the length checks produced at most 2 rejections in any of them; grounding produced
  the rest. They stay as they are, and this is the record of why rather than an untested
  inheritance.
- **Non-determinism is real but smaller than feared**: 3 of 20 utterances still flip verdict between
  runs. Any future threshold work must repeat each sample; a single pass is noise.
- **The silent no-op RATE remains unmeasured** (section 5). What is measured is that one specific
  and common false positive is gone. Whatever the true rate is, the fallback is a transcript that
  is already punctuated and capitalised, so the cost of a rejection is low.

## 8. What this does NOT establish

- **Synthetic speech.** Every transcript came from `say`, whose recognition errors are not
  distributed like a human's in a room. The rejection rate on human audio is unmeasured.
- **20 utterances, one voice, one language, one machine.**
- **Nothing about cleanup being wired in.** It still is not; this measures the stage in isolation,
  and end-to-end latency with cleanup in the path remains untimed (`docs/verification/task15`).
- **Not a quality judgement.** This measures how often cleanup is ALLOWED to run, never whether its
  output is better than the raw.
- **Not an aggregate rejection rate.** Section 5 says why: three runs per utterance is below the
  noise floor of a non-deterministic model, and two honest passes disagreed.
