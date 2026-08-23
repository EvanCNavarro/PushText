# Spike 13 — does `contextualStrings` bias `SpeechTranscriber`?

Reproduction for `docs/verification/task13-contextual-strings.md`. **Answer: no.**

An A/B that holds everything constant except one line — `context.contextualStrings[.general]` —
and prints whether the two transcripts differ.

```sh
say -o sample.wav --data-format=LEF32@48000 \
  "Open PushText and check the Invela dashboard on Kubernetes."
swift run spike13 both
```

Arms: `plain` · `biased` · `both` (default). Second argument overrides the audio path.

Requires macOS 26 and the en-US speech assets. Lives outside the package on purpose: it is
evidence, not shipped code, and `docs/research/01` §1.6 is the claim it tests.
