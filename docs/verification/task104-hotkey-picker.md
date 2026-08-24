# Task 104 - Choosing the push-to-talk key

**A picker over `HotkeyBinding.selectable`, not a combo recorder** - and the event tap re-registers
live. Verified 2026-08-23 on macOS 26.6.2 through the packaged `.app`.

---

## 1. The design question was already answered in the repo

#104 proposed porting TermTile's `HotKeyRecorder`, an `NSViewRepresentable` that captures arbitrary
key+modifier chords, and listed "bare modifiers, ordinary combos, or both?" as unresolved.

`PLAN.md` 2.2 had already decided it:

- `RegisterEventHotKey` **cannot express a bare modifier at all**, and its header says right-side
  modifiers are "Not supported on Mac OS X". Chords and bare modifiers are different mechanisms.
- **"Secure Input filters `keyDown`/`keyUp` but `flagsChanged` keeps flowing."** A bare-modifier
  hotkey still dictates inside a password field, where a chord dies silently.

So offering arbitrary combos would quietly trade away a capability the app deliberately has. The
answer is to let the user choose WHICH bare modifier.

`HotkeyBinding.selectable` already existed for precisely this, with a comment reading "The bindings
offered in settings" - the domain model was built for the feature years before the UI.

## 2. What was missing

Nothing in the model. The gaps were:

- `MenuContent.swift:68` displayed `LabeledLine(label: "Hotkey", value: "Right Option")` - a
  **hardcoded string** that would have lied the moment the binding differed.
- `CGEventTapHotkeyMonitor` takes its binding at construction, and `PushTextApp` is a `struct App`,
  which cannot mutate itself from the escaping closure a settings change arrives on.

`HotkeyController` owns the monitor so the tap can be town down and rebuilt. It stops the old tap
BEFORE creating the new one: two live taps on different modifiers would both feed the same state
machine, and the second key would look like it was starting utterances the first never finished.

## 3. Driven on the real path

Selected "Right Command" from the menu picker:

```
hotkey tap armed for Right Command
$ defaults read dev.ecn.apps.pushtext hotkeyKeyCode
54                                   # 0x36, kVK_RightCommand
```

Then held each key in turn with a synthetic bare modifier carrying the correct device bit:

| held key | result |
| --- | --- |
| Right Command (the new binding) | full cycle - `arming -> recording -> transcribing -> cleaning -> injecting -> idle`, `injected chars=41` |
| Right Option (the old binding) | **no `hotkey edge` at all** |

The second row is the one that matters. Without it, "the new key works" is compatible with both keys
working, which would mean the tap was never re-pointed - only added to.

## 4. What this run did NOT show

The injected text did not land in the TextEdit window the harness had focused, though the log records
`injected chars=41`. That is a focus artifact of the harness rather than a pipeline failure - the
full state cycle completed - but it means this particular run proves the HOTKEY, not the paste
target. Injection into a real app is covered separately by `task27-injection-across-apps.md`.

Left Option, Right Control and Right Shift were not driven; only Right Command was. The remaining
three share the same code path and differ only in their device mask, which is unit-tested, but
"unit-tested and shares a path" is an argument, not an observation.
