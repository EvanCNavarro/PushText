# Task 107 - The HUD during processing, and cancel on the real path

**Both controls are replaced by spinners while the pipeline works, and cancel is now proven against
a real capture.** Verified 2026-08-23 on macOS 26.6.2 through the packaged `.app`.

---

## 1. Why BOTH controls go, not just confirm

The request was to turn the confirm control into a spinner and keep cancel live. The second half
rests on a premise the machine contradicts:

```swift
case (.arming, .cancelRequested), (.recording, .cancelRequested):
    return .to(.idle)
```

`cancelRequested` is accepted from `.arming` and `.recording` only. `.working` covers
`transcribing`, `cleaning` and `injecting`, and in all three the event is unhandled. Leaving cancel
on screen during processing would have replaced one dead button with another - the exact defect the
spinner exists to remove.

So the pill shows a spinner on each side. Whether cancel SHOULD be honourable during processing is a
real product question, tracked separately rather than decided here.

## 2. Rendered verification, and what the rasteriser could not show

`ImageRenderer` snapshots (`PUSHTEXT_SNAPSHOT_DIR`) confirm the LAYOUT: the pill keeps its size, the
controls keep their positions, and the waveform sits flat between them.

They do **not** confirm the spinner. `ImageRenderer` cannot rasterise an indeterminate
`ProgressView` and draws an orange placeholder glyph instead. Recorded because the snapshot looks
like a rendering of the feature and is not one.

The spinner was therefore verified in the RUNNING app: a real dictation, screenshotted repeatedly
after key release, with cleanup temporarily enabled to widen the `.working` window from ~200 ms to
613 ms. Two frames landed - one mid-crossfade with the controls fading out, one showing both
spinners with the flat waveform between them.

## 3. Cancel, driven on the real path

Cancel can only be raised by clicking the HUD, so a synthetic mouse click was posted at the
control's screen position while a real capture was running.

```
19:00:34.932  hotkey edge=pressed
19:00:35.107  capture started            state arming -> recording
19:00:38.625  state recording -> idle          <- the click
19:00:38.628  cancelled: capture closed, nothing injected
19:00:42.917  hotkey edge=released             <- from idle, correctly unhandled
```

The document was empty afterwards. No `transcribing`, no `injected chars`, and the key release that
arrived four seconds later changed nothing.

This is the `.idle where previousWasActive` branch, which has existed for cancellation since #46 and
had never executed against a real capture.

## 4. The log line is new, and it is the point

Before this, a cancel appeared in the log as `recording -> idle` and nothing else - indistinguishable
from an utterance that failed silently. "The microphone closed" was a claim no log line could
support: `closeMicrophone()` logged nothing, so the only available evidence was that the branch
calling it existed.

`cancelled: capture closed, nothing injected` makes it observable. Same reasoning as #99: a silent
outcome and a broken one look identical to whoever reads the log next.
