# Task 99 - A hotkey press refused while the pipeline works

**The refusal is now detected, logged and acknowledged.** Verified 2026-08-23 on macOS 26.6.2
through the packaged `.app`.

---

## 1. The issue was wrong about one thing

#99 said "no HUD, no sound, no log line saying the press was refused". The log line existed:
`AppModel.apply` already logged every ignored event.

It logged at **`.debug`**, which `log stream --info` does not show - and `--info` is what every
investigation in this project actually runs. So a swallowed press read as "no press arrived" more
than once, including during #94's latency work and #105's latch investigation.

That is the more interesting failure: not an absent signal, but one emitted at a level nobody
watches. The refusal now logs at `.info`.

## 2. What the user sees, and what they did not

Since #107 the HUD shows a working state throughout `transcribing`/`cleaning`/`injecting`, so
"something is happening" is visible.

What was not visible is that the key they JUST pressed did nothing - and the speech they are about
to give it will not be captured. That is the harm: an utterance is lost, silently.

The HUD now pulses on a refused press. Scale rather than colour, because the pill is already showing
a status; what needs communicating is that a keypress bounced off, which is motion.

## 3. Only the presses that matter

`.recording` also refuses a press - a duplicate key-down from the hardware repeating. Acknowledging
that would flash the HUD throughout every dictation.

`DictationState.isProcessing` is therefore `transcribing || cleaning || injecting` and deliberately
excludes `.recording`. A test asserts a duplicate key-down while recording produces NO
acknowledgement; planting `.recording` into `isProcessing` fails it.

## 4. Real path

Cleanup was switched on **through the new setting** (#103) rather than by editing source, widening
the processing window to seconds:

```
state transcribing -> cleaning
hotkey edge=pressed
hotkey REFUSED in state=cleaning
state cleaning -> injecting
injected chars=55
```

Before this change that press produced `hotkey edge=pressed` followed by nothing - indistinguishable
in the log from a press that started something. A second run hammering the key during the window
logged **4** refusals.

## 5. What is NOT verified

**The pulse has never been seen.** The counter increments on a real refused press (logged above), the
view is bound to it, and planting the binding away fails two tests - but no screenshot caught the
150 ms animation.

Five attempts: four rapid frames during a single refusal, then a hammering run to keep the pulse
near-continuous. A pixel measurer written to compare pill width across frames could not isolate the
pill from the background - it kept reporting the crop width (`first=0`), so its numbers are not
evidence of anything and are not quoted here.

So: the mechanism is proven, the animation is not. Tracked separately rather than described as done.
