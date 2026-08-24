# Task 24 - Making the interleaved branch reachable, and reading the layout instead of guessing it

Measured 2026-08-23 on macOS 26.6.2.

---

## 1. The gap

`AVAudioEngineCapture`'s sink block chose between two copies:

```swift
if channels == 1 || buffers.count > 1 {
    // mono, or non-interleaved: buffer 0 IS channel 0
} else {
    // interleaved in one buffer - take channel 0, sample by sample
}
```

The else-branch needs `buffers.count == 1 && channels > 1`. Every input device on this machine
reports **1 channel** - re-measured today rather than cited:

```
MacBook Pro Microphone           ch=1  rate=96000/88200/48000/44100
Evan's iPhone 14 Pro Microphone  ch=1  rate=48000
```

So the branch could not run here, and waiting for hardware that may never arrive is not a plan.

## 2. Two problems, not one

**Reachability.** The logic was welded inside a realtime callback, so the only way to execute it was
to own the hardware. Extracting the decision and the copy into pure functions in Core makes both
runnable today. `AudioBufferLayoutTests` drives interleaved stereo and interleaved 5.1 with no audio
device involved.

**Correctness.** Extraction exposed a second defect the original branch had. `channels == 1 ||
buffers.count > 1` describes layout by INFERENCE, and it is wrong for a real shape: 4 channels
delivered as **2 buffers of 2**. That reads as "non-interleaved" and strides by 1, which would
interleave two channels into the ring as if they were one.

The fix is to stop inferring. `AudioBuffer.mNumberChannels` states how many channels are packed into
*that* buffer, which is exactly the stride, and it is right for all three shapes.

## 3. The field was measured before being relied on

Reading a field the code has never read is the same class of assumption the issue complains about,
so it was checked with temporary instrumentation on the real capture path:

```
AUDIO_PROBE LAYOUT bufferCount=1 bufferChannels=1 formatChannels=1     (2 runs)
```

The field is populated and agrees with the format. **What that does NOT show:** that it is correct
for a layout no device here produces. Mono is the only layout available on this machine, so what is
verified is that the field is FILLED IN, not that it reports interleaving correctly. The
instrumentation was removed afterwards.

## 4. Battle-tested

Five plants against the extracted logic, each confirmed detected and reverted:

| planted regression | caught by |
| --- | --- |
| stride always 1 | interleaved stereo and 5.1 stride assertions |
| ignore the buffer count / infer from format | the layout table |
| ignore the stride inside the ring | values come back `[0, 0, 1, -1, …]` instead of `[0, 1, 2, …]` |
| off by one channel | values come back negated - channel 1's marker |
| ignore the ring's free space | a full ring accepts 8 instead of 3 and the contents wrap |

Channel 1 carries the NEGATED frame index in the fixtures, so reading the wrong channel or drifting
by a sample shows up in the VALUES. A test that only counted frames would pass on a copy that
returned the right number of wrong samples.

## 5. The real path still works

Mono capture through the rewired sink block, 3 runs:

```
buffers=60 frames=144384 sampleRate=48000.0 dropped=0
timestampsMonotonic=true contiguous=true
completeness=1.003 complete=true   peak=0.00968 rms=0.00254 silent=false   exit 0
```

## 6. What is still unobserved

No device on this machine delivers a buffer with `mNumberChannels > 1`, so the interleaved path has
still never executed against real audio. What changed is that it is no longer *unexecutable*: the
logic is covered, the layout question is now read from the buffer rather than inferred, and a machine
with a stereo interface would exercise it without any further work.
