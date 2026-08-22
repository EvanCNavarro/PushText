# Spike 11 - streaming transcription go/no-go

Standalone SwiftPM executable. **Not part of the PushText build** - the root `Package.swift` does
not reference it, and `swift build` at the repo root ignores it. It is kept so the #11 verdict can
be re-run rather than re-derived.

Findings: `docs/verification/task11-streaming-spike.md`.

## Run it

```sh
cd docs/verification/spikes/11-streaming
say -o sample.wav --data-format=LEF32@48000 \
  "The quick brown fox jumps over the lazy dog. Push text turns speech into text on device."
swift build

./.build/debug/spike11 env                 # model inventory, no audio
./.build/debug/spike11 batch 4096          # control: analyzeSequence(_:)
./.build/debug/spike11 streaming 4096      # the call under test: start(inputSequence:)
./.build/debug/spike11 streaming-badformat # planted failure, expect SIGTRAP (exit 133)
```

`argv[2]` is frames per buffer, `argv[3]` an audio path. Every arm prints one `VERDICT=` line -
except `streaming-badformat`, which cannot, because it traps inside Speech.framework (#32).

Requires `swift-tools-version:6.2` or later for `.macOS(.v26)` - see #16.
