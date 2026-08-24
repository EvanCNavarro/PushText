# Task 128 - The hotkey as a recorder, and what happened to "Ready"

Measured 2026-08-24 on macOS 26.6.2.

---

## 1. This does not overrule #104 - it satisfies its constraint

`docs/verification/task104-hotkey-picker.md` considered TermTile's `HotKeyRecorder` and rejected it.
The reason was specific:

> #104 proposed porting TermTile's `HotKeyRecorder`, an `NSViewRepresentable` that captures
> **arbitrary key+modifier chords** ... offering arbitrary combos would quietly trade away a
> capability the app deliberately has.

The capability is that a **bare** modifier keeps working under Secure Input, where `flagsChanged`
still flows and `keyDown` does not. That argument is against chords, not against recording.

This recorder captures **only** `HotkeyBinding.selectable` - the same five bare modifiers the picker
offered. Anything else beeps and is not stored. The domain constraint is unchanged; only the gesture
changed, from reading five names to pressing the key you mean.

It also cannot reuse TermTile's capture code, for the same reason: a bare modifier produces no
`keyDown` at all. TermTile reads `keyDown` and `performKeyEquivalent`; this reads `flagsChanged`.
The drawing, the focus dance and the Esc handling ARE TermTile's.

## 2. A defect designed out before it shipped

The event tap is **global**. It does not care that a settings field has focus. So pressing Right
Option to rebind would also have started a dictation - the user recording their own act of changing
the setting, with the HUD appearing over the menu they were using.

The recorder therefore announces capture in both directions, and the composition root suspends the
tap:

```swift
model.preferences.onRecordingChange = { [controller] isRecording in
    if isRecording { controller.suspend() } else { controller.resume() }
}
```

`suspend()` is a real teardown, not a flag. A flag would be consulted by the tap callback, which
runs on the tap thread - and the edge it would have to drop is the very keypress being recorded.

`HotkeyRecorderViewTests` asserts BOTH signals, because announcing only the first would leave the
hotkey dead until relaunch.

## 3. "Ready" was the wrong row, and deleting it was the wrong fix

Bobby asked whether the State row earns its place. It did not, in the common case: you cannot be
mid-dictation and clicking the menu bar - except in the latched mode - so the row read `Ready` every
time anyone looked at it.

Deleting it was checked before being ruled out, and it fails:

```
$ grep -rn "statusText\|DictationFailure" Sources/PushText/*.swift | grep -v Presentation
Sources/PushText/MenuContent.swift:67:  LabeledLine(label: "State", value: model.statusText)
```

`MenuContent` is the **only** surface in the app that shows a `DictationFailure`. `HUDPhase` has
`resting / recording / working / inserting` and no failure case at all. Deleting the row would have
silently removed the only place "Preparing model...", "Permission needed", "Didn't catch that",
"Transcription failed", "Couldn't insert text" and "Cancelled" can appear.

So the row is hidden while idle and shown otherwise. `activityText` returns nil for `.idle` only,
and a test drives all eleven other states to prove none of them lost its message.

## 4. ImageRenderer cannot draw this, measured

The snapshot suite was the obvious place to check the look. It cannot do it: `ImageRenderer` renders
an `NSViewRepresentable` as the same orange placeholder it gives an indeterminate `ProgressView`.

That is an observation, not a recollection - the PNG was written and looked at, and the recorder's
field came out as a solid orange bar with a "prohibited" glyph. The snapshot case was **removed**
rather than kept, because a test whose output is a placeholder reads as a rendering to whoever opens
it next.

Replaced by `PUSHTEXT_MENU_PROBE=1`, which hosts the REAL `MenuContent` with the REAL model in an
ordinary window, where AppKit draws itself and `screencapture -l<windowID>` can take it.

## 5. What rendering found that reading did not

The first capture showed the field sitting visibly BELOW its own label. `RecorderLine` had copied
`alignment: .firstTextBaseline` from the sibling rows, and an `NSView` has no text baseline for
SwiftUI to align to. Changed to `.center`; the second capture shows label and field centred on each
other.

Nothing in the code review would have caught that. It is the reason UI changes need a render.

## 6. Battle-tested

`HotkeyBinding.pressed` - three plants, each caught by the test that should:

| planted regression | caught by |
| --- | --- |
| ignore direction, capture on release too | "the same key going up is not a capture" |
| test "any flags set" rather than THIS key's bit | "another key's bit does not count as a press" |
| accept any key, not just bindable ones | "a key the app cannot bind is refused" |

`HotkeyRecorderView` - three more:

| planted regression | caught by |
| --- | --- |
| listen even when not recording | "a key pressed before clicking is ignored" |
| stop announcing recording | all three signal assertions |
| store a fallback instead of refusing | "an unbindable key is refused and recording continues" |

`activityText` - both directions:

| planted regression | caught by |
| --- | --- |
| never hide the row | "idle reports no activity" |
| always hide the row | "every non-idle state still reports activity" |

## 7. What this did NOT verify

The probe window is a bare SPM binary, so it shows a generic icon and "Version dev (0)" - bundle
facts, not view facts, and unrelated to what is being judged here.

**No key has been pressed at the recorder by a human.** The capture path is driven by synthesized
`NSEvent`s in tests, which exercise the view's own logic but not the delivery of a real
`flagsChanged` to a first responder inside a `MenuBarExtra` popover. That is the one step left, and
it needs a person at the keyboard.
