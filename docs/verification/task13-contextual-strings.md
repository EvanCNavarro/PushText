# Task 13 - SPIKE: does `contextualStrings` bias `SpeechTranscriber`?

**Verdict: NO.** `AnalysisContext.contextualStrings` has no observable effect on `SpeechTranscriber`
output. The custom dictionary (#9) is a post-pass and must stay one.

Measured 2026-08-22 on macOS 26.6.2 / Xcode 26.6 / SDK `macosx26.5`.

---

## 1. What the research predicted

`docs/research/01` §1.6 says to treat custom vocabulary on `SpeechTranscriber` as **"UNVERIFIED and
probably absent"**, on two independent grounds:

- a forum responder states `AnalysisContext` contextual-vocabulary biasing works with
  `DictationTranscriber` but *not* `SpeechTranscriber` [forum thread 818005]
- Argmax independently reports SpeechAnalyzer *"lacks the Custom Vocabulary feature"* of the
  predecessor API

Both are REPORTS. This executed it.

## 2. The A/B

Everything held constant except the context: same audio buffers, same `SpeechTranscriber` preset
(`.progressiveTranscription`), same locale, same chunking, same analyzer construction. The only
difference is one line:

```swift
context.contextualStrings[.general] = ["PushText", "Invela", "Kubernetes"]
```

Audio is a fixed WAV with known ground truth, so both arms see identical input:

```
say -o sample.wav --data-format=LEF32@48000 \
  "Open PushText and check the Invela dashboard on Kubernetes."
```

The three bias words were chosen to be things a general vocabulary will not contain: a camel-case
product name, a coined company name, and a technical term.

## 3. Result

```
VERDICT=PLAIN  text="Open, push, text, and check, and rail a dashboard on Cubanies."
VERDICT=BIASED text="Open, push, text, and check, and rail a dashboard on Cubanies."
VERDICT=IDENTICAL=true
VERDICT=BIAS_WORDS_PRESENT=[]
```

Identical on 3 of 3 runs.

**The test conditions were ideal for detecting an effect.** The recognizer mangled all three target
words without the bias - "push, text" for PushText, "and rail a" for Invela, "Cubanies" for
Kubernetes. If biasing did anything at all, these are exactly the words it would have fixed, and
there was maximum room to improve. It changed nothing.

## 4. Consequence

**#9's custom dictionary stays a post-pass**, which is how it was built: `CustomDictionary` rewrites
recognized text after the fact rather than steering the recognizer. That decision was made on the
research's prediction and is now made on a measurement.

Nothing needs to change in the shipped code. The value of this spike is that the question is
CLOSED - the next person to notice `contextualStrings` in the API and wonder whether it would remove
the need for a post-pass has an answer, and the reproduction to check it against.

## 5. What this does NOT establish

- **Nothing about `DictationTranscriber`.** The forum report says biasing works there, and that was
  not tested - PushText uses `SpeechTranscriber` and switching modules for vocabulary alone would
  trade a known, working streaming path for an unknown one.
- **Nothing about the 100-phrase cap** the documentation mentions. Three words produced no effect,
  so the cap was never approached and its behaviour is irrelevant here.
- **Nothing about a future OS.** This is a runtime behaviour on 26.6.2, not an API contract. Re-run
  the spike after a major OS update rather than assuming the answer holds.
- **Nothing about tags other than `.general`.** `ContextualStringsTag` is `RawRepresentable`, so
  other tag values are constructible, but `.general` is the only one the SDK names.
