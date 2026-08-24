# Task 124 - The truncation guard was dividing by a window it never measured

Measured 2026-08-23 on macOS 26.6.2.

---

## 1. The defect

`AudioProbe` scored completeness as `frames / (secondsRequested * sampleRate)` and failed only below
0.85. The denominator assumed `RunLoop.main.run(until:)` runs for exactly `seconds`. It does not.

Found by accident: three probe runs during #24's verification reported completeness `1.394`, `2.965`,
`0.999` for the same 3-second request. 2.965 is 8.9 seconds of audio inside a nominal 3-second window.

## 2. The mechanism, confirmed by intervening rather than by correlation

A `PUSHTEXT_AUDIO_PROBE_STALL` knob blocks the MAIN run loop for N ms - the same idea as the existing
`PUSHTEXT_HOTKEY_PROBE_STALL`, and the reason it is permanent rather than temporary scaffolding: a
guard you cannot make go red on demand is a guard nobody has tested.

```
control          window requested=3.000 actual=3.008     completeness=1.003 (old maths)
STALL=6000       window requested=3.000 actual=6.219     completeness=2.073 (old maths)
```

So the window really does stretch, and the ratio really does inflate with it.

## 3. Why inflation is the dangerous direction

The guard exists because `monotonic`, `contiguous` and `dropped == 0` all describe only the frames
that DID arrive - every one of them passed on runs that lost 5 of 8 seconds to a device change (#70).
Wall time was chosen as "the one signal a missing frame cannot forge".

The ratio only fails LOW. A stretched denominator therefore does not merely make the number odd - it
can carry a truncated run over the threshold. Demonstrated on the real path, half the audio discarded
inside a stalled window:

```
window requested=3.000 actual=6.218   frames=298496 (half reported)
NEW denominator:  completeness=0.500  complete=false  ->  exit 4
OLD denominator:  149248/(3*48000) = 1.036            ->  would have PASSED
```

That is the failure this guard exists to catch, sailing through the guard.

## 4. The fix

Measure the window with `ContinuousClock` across `run(until:)` and divide by that. Both numbers are
printed, so a stretched window is now visible rather than silently folded into the ratio.

The arithmetic moved to `CaptureCompleteness` in Core, because the defect was in the maths and no
amount of running the probe would have shown it - the probe and the wrong denominator agreed with
each other. A zero or negative window scores 0 rather than dividing: for a truncation guard, failing
closed is the only safe direction.

## 5. Verified both ways

```
control          window actual=3.009   completeness=1.000  exit 0
STALL=6000       window actual=6.218   completeness=1.000  exit 0
30% of frames    completeness=0.300  capture=truncated     exit 4
50% + STALL      completeness=0.500  capture=truncated     exit 4
```

The stalled run scoring 1.000 is the point: the window was genuinely 6.2 seconds long and 6.2 seconds
of audio genuinely arrived.
