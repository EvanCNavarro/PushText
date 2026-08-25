# Task 172 - Start and stop cues, matched to Wispr Flow without shipping its audio

Measured 2026-08-25 on macOS 26.6.2.

Bobby: *"When I run Whisper Flow, it triggers a noise ... I want sound to be enabled or optional ...
For now, have the matching one that we have from Whisper Flow."*

---

## 1. What Wispr Flow actually plays

`/Applications/Wispr Flow.app/Contents/Resources/assets/sounds/` holds `dictation-start.wav`,
`dictation-stop.wav` and `paste.wav`, plus versioned sets (`v1`, `v6`, `v11.3`).

Measured with a pure-Python DFT, since this machine's `python3` has no numpy:

```
dictation-start.wav   44100 Hz, 2ch, 180 ms
  dominant Hz by third: [448, 435, 296]
  envelope:             [0.022, 0.227, 0.062, 0.014, 0.008, ...]

dictation-stop.wav    44100 Hz, 2ch, 219 ms
  dominant Hz by third: [323, 296, 296]
  envelope:             [0.036, 0.048, 0.176, 0.018, 0.012, ...]
```

Two short blips whose energy peaks in the first fifth and decays away. **Start is pitched above
stop** - up for "listening", down for "done". That direction is the part carrying meaning, and the
one thing a user would notice instantly if it were reversed.

## 2. Their files are not ours to ship

Those `.wav`s are Wispr Flow's assets and this repository is public; copying them in would be
redistributing another company's audio. So the cues are GENERATED to match the measurements:

| | Wispr Flow | PushText |
|---|---|---|
| start | 180 ms, ~448 Hz decaying toward ~300 | 175 ms at 440 Hz |
| stop | 219 ms, ~323 Hz | 210 ms at 300 Hz |
| envelope | peaks in the first fifth, decays | exponential decay, same shape |

## 3. The test that was green against its own defect

Six tests on the waveform, six plants. Five fired immediately. **The fade-in plant did not.**

`noClickAtEitherEnd` asserted the first sample was ~0. A sine at phase zero begins at value zero
whether or not it is faded in, so deleting the fade-in left the test green - against exactly the
defect it was written for. What a bare sine onset actually has is MAXIMUM SLOPE at t=0, and the step
between consecutive samples is what a speaker reproduces as a click.

Re-asserted on the steepest step across the first 32 samples, the plant fires. A sixth plant also
proved nothing at first because its anchor did not match - a plant that does not apply is not a
passing plant, and it was re-run with a correct anchor.

## 4. Where the cues fire, which matters more than the sound

- **start on `.recording`**, not `.arming`. `.arming` is key-down and can still fail on a missing
  grant; a cue for a dictation that never started is a lie told in sound.
- **stop on `.transcribing`**, not after injection. It marks the thing the USER did, not the thing
  the app finished doing two seconds later.

Three tests with a spy player cover the ordering, the off state, and that flipping the toggle takes
effect on the next dictation rather than the next launch. Two plants, both fire.

## 5. Default ON, and the store comment that predicted it

`soundEnabled` defaults to `true` - the first setting in this app whose default is not `false`.
`SettingsStore` had already been written for that day:

> **That distinction is invisible today** - the only setting defaults to `false`, so both spellings
> behave identically. It is written correctly now because the first setting whose default is `true`
> would otherwise be silently unable to persist an OFF.

Because `load()` uses `object(forKey:) as? Bool` rather than `bool(forKey:)`, switching the cues off
survives a relaunch. Had it used the obvious spelling, the toggle would have looked broken.

## 6. Listened to, because nothing else can verify a sound

`PUSHTEXT_SOUND_PROBE=1` writes both cues as `.wav` through the SAME `DictationTone.samples` and
`SoundFeedback.wav` the app plays - a reimplementation for the probe would be judging a copy:

```
SOUND_PROBE wrote .../cue-start.wav bytes=15478 hz=440 ms=175
SOUND_PROBE wrote .../cue-stop.wav  bytes=18566 hz=300 ms=210
```

Both files were sent to Bobby to compare against Wispr's. Pitch, length and decay are each a
one-line change if the character is wrong.

## 7. A rendering I read wrong, recorded so the next person does not

The menu screenshot appeared to show both toggles OFF while the app had just traced
`cleanup=true sound=true`. That looked like a binding bug and was not one: the probe window is not
the key window, so macOS draws switches in their inactive grey rather than the accent colour. The
knob position is the actual state, and it was on the right in both.

The tell was an earlier capture where cleanup was genuinely off and the knob sat LEFT. Two traces -
at load and at render - were what stopped a non-bug from being "fixed".

## 8. What this does NOT show

Nobody has heard the cues play from the running app on a real dictation; the probe verifies the
BYTES, and the trigger points are covered by a spy rather than by a microphone. Whether they sound
right against Wispr's is Bobby's call, which is why the files were sent rather than described.

`paste.wav` has no equivalent here. Choosing WHICH sound plays is deferred by request - "for now,
have the matching one".
