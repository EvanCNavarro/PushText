# Issue 4 verification — AudioCapture (AVAudioSinkNode)

Date: 2026-08-22. Machine: macOS 15.1, Xcode 16.2, Swift 6.0.3.

## Why the sink node, read from the SDK rather than recalled

`AVAudioNode.h` on `installTapOnBus:bufferSize:format:block:`, describing `bufferSize`:

> the requested size of the incoming buffers in sample frames. **Supported range is [100, 400] ms.**

My research note had called this a "100-400 ms latency floor". The header is narrower and more
precise: it is a constraint on buffer SIZE, which makes 100 ms the best delivery granularity a tap
can offer — pure added latency in a push-to-talk loop. `AVAudioSinkNode` delivers what the hardware
produces instead.

Two more constraints from `AVAudioSinkNode.h`, both load-bearing:

> the receiver block **will be called on the realtime thread** and it is the client's responsibility
> to handle it in a thread-safe manner and to **not make any blocking calls**.

> AVAudioSinkNode is restricted to be used in the input chain and **does not support format
> conversion**.

Allocation and locking are both blocking calls, which is why `AudioRingBuffer` exists.

## AudioRingBuffer — red first

Stubbed to return `0`/`[]`, then the suite run: 8 tests, every failure an `Expectation failed` with
the actual value (`→ 0`, `→ []`). Assertions failing, not the harness.

Four defects were then planted:

| planted | caught |
|---|---|
| overwrite-on-full instead of dropping | yes — 5 issues |
| off-by-one in the write wrap | yes — 3 issues |
| read ignores available frames | yes — 9 issues, and it tripped the 30s watchdog rather than hanging |
| `writeIndex` store weakened `.releasing` → `.relaxed` | **NO — all 8 passed** |

That last row is the honest limit. The suite catches torn logic; it is not sensitive enough to prove
memory ordering. Correctness there rests on the acquire/release pairing argument in the source, not
on a green run, and a future edit that weakens it will not be caught by these tests.

The concurrency test uses `DispatchQueue`, not `Task`, deliberately: the real producer is a C
callback on the audio IO thread, not a Swift concurrency task. 200,000 frames through a real
producer/consumer pair, asserting both that every frame returns exactly once and that the ramp comes
back in order — a count-only assertion would pass on a buffer returning the right number of wrong
samples.

## The real path — actual microphone audio

```
$ PUSHTEXT_AUDIO_PROBE=1 PUSHTEXT_AUDIO_PROBE_SECONDS=4 dist/PushText.app/Contents/MacOS/PushText
AUDIO_PROBE micAuthorized=true
AUDIO_PROBE capture=started seconds=4.0
AUDIO_PROBE buffers=80 frames=192000 sampleRate=48000.0 dropped=0
AUDIO_PROBE timestampsMonotonic=true contiguous=true
AUDIO_PROBE peak=0.00457 rms=0.00024 silent=false
AUDIO_PROBE finished
```

192,000 frames / 48,000 Hz = **exactly 4.0 s**. Nothing was dropped, and `silent=false` means real
room noise arrived rather than a zero-filled buffer — a dead capture path that returned the right
frame count would still show `peak=0`.

Timestamps are monotonic and contiguous **by construction**: `startTime` is derived from a running
frame count, never from a host clock. Non-monotonic `bufferStartTime` is one of the three suspected
causes of FB22149971 (docs/research/01), so it is asserted at the source rather than discovered on
Tahoe.

Both assertions were planted against:

| planted | monotonic | contiguous |
|---|---|---|
| random `startTime` | **false** | false |
| one-frame gap between buffers | true | **false** |

They discriminate independently — this is two checks, not one reported twice.

`scripts/test-packaged-app.sh` now asserts all of it, conditional on the microphone grant so a CI
runner cannot make the gate permanently red. A planted dead capture path (sink block discards its
samples) fails it; restoring passes.

## The signing script was broken, and the failure was silent-ish

`scripts/setup-dev-signing.sh` — inherited from TermTile — could not import its own certificate:

```
security: SecKeychainItemImport: MAC verification failed during PKCS12 import (wrong password?)
```

Measured on this machine (OpenSSL 3.6.3):

| PKCS#12 export | result |
|---|---|
| default (AES-256-CBC keys, SHA-256 MAC) | MAC verification failed |
| `-legacy` (3DES keys, **RC2 certs**) | MAC verification failed — modern macOS rejects RC2 |
| **3DES for both bags + SHA-1 MAC + non-empty password** | `1 identity imported.` |

Then a second, separate bug: the script verified success with `security find-identity **-v**`, which
lists only TRUSTED identities. A self-signed cert is never trusted (`CSSMERR_TP_NOT_TRUSTED`), so a
working identity looked absent. `codesign` uses it perfectly well — measured, `Authority=PushText Dev
Signing`, exit 0. `build-app.sh` had the same `-v` in its auto-detection, which is why it had been
silently falling back to ad-hoc signing and resetting every TCC grant on each build.

Both now check the real post-condition: presence without `-v`, plus an actual test signature.

## What this did NOT verify

- **Memory ordering**, as above — argued, not measured.
- **Device changes mid-capture** (AirPods connecting, mic unplugged) were not exercised. Tracked.
- **Interleaved stereo input** — the branch handling it exists but this machine's input is
  non-interleaved, so it never executed. Tracked.
- The engine is stopped on `stop()`, but that the orange microphone indicator actually extinguishes
  was not observed — it is a claim about UI, checked only against `AVAudioEngine.h`.
