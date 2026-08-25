# Task 199 - The twenty-minute ceiling, measured instead of reasoned

Measured 2026-08-25 on macOS 26.6.2.

#197 raised the watchdog ceiling from 120 s to 1200 s on the strength of two code READS - the audio
ring is a ~2 s transport window, and `TranscriptFinisher` falls back to raw text. Neither was a run.
The longest capture this app had ever produced was 95.3 s. This is the run.

---

## 1. Method

`say` rendering a numbered script, so truncation would be VISIBLE rather than plausible: if the
transcript stopped at section 40 of 120, the loss is obvious. Two files, driven through
`PUSHTEXT_TRANSCRIBE_PROBE_FILE`:

| file | duration | mode |
|---|---|---|
| `long.aiff` | 2391 s (~40 min) | unpaced - whole file pushed at once |
| `long16.aiff` | 930.6 s (~15.5 min) | `REALTIME=1` - paced at wall-clock speed |

Both matter, and the probe's own documentation says why: *"Without it the whole file is pushed at
once, which is NOT what production does - live capture delivers a buffer every 50 ms - so the paced
run is the one that exercises the analyzer's real timing."*

## 2. Capacity: forty minutes, transcribed whole

```
source=long.aiff buffers=21971 frames=52729461 rate=22050.0 realtime=false
delivered=2391.36s duration=41.60s
begin=80.2ms deliver=233.8ms finalize=41367.0ms total=41681.0ms
exit=0
```

33,640 characters. Section markers from the first to the last, no gap in the middle. **Twice the new
ceiling, with nothing truncated and nothing accumulating.** The #197 reasoning holds, and now it has
a run behind it.

## 3. Fidelity: fifteen minutes at real-time speed

```
source=long16.aiff buffers=8551 frames=20520585 rate=22050.0 realtime=true
delivered=930.64s duration=973.44s
begin=75.6ms deliver=973348.9ms finalize=94.4ms total=973519.0ms
exit=0
```

13,472 characters, **48 of 48 sections**, first to last.

## 4. The finding the unpaced run would have got WRONG

| | unpaced | paced |
|---|---|---|
| finalize | **41,367 ms** | **94.4 ms** |

Had only the unpaced run been done, the conclusion would have been *"a long dictation takes 41
seconds to finalise after you release the key"* - and that is false for real use. Pushing a whole
file at once leaves the analyzer a backlog to chew through at the end; paced delivery does the work
as the audio arrives, so finalisation is **94 ms**.

For the product this is the answer to the question #197 actually raised: a fifteen-minute dictation
returns its text essentially immediately on release. No progress indicator is needed, and the ceiling
does not need lowering to keep the tail responsive.

It is also the second time today that the FAITHFUL harness and the convenient one disagreed in a way
that would have changed a decision.

## 5. What this does NOT show

**The 1200 s ceiling itself is still never exercised.** `TranscriptionProbe` does not touch
`CaptureWatchdog` - grep says zero mentions - so this measures the ENGINE at length and says nothing
about the timer. The watchdog's transcribe-rather-discard behaviour is proven at 0.2 s in
`AppModelTests`, and the constant is asserted separately; reaching 1200 s for real needs a
twenty-minute live capture with a human or a virtual audio device.

That gap is narrower than the one #199 opened - "does anything break at length" is answered - but it
is not zero, and the honest statement is that the ceiling is a number nobody has hit.

Both files were synthesised speech, not a human voice. Word-level accuracy is visibly imperfect
("the quick round forks"), which does not matter for a length measurement and would matter for an
accuracy one.
