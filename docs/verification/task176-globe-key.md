# Task 176 - The Globe key was refused on a comment that misread our own research

Measured 2026-08-25 on macOS 26.6.2.

Bobby, after the hotkey recorder appeared broken:

> I was using the bottom left function globe thing, but I use that anyways right now for Whisper
> Flow ... So I don't understand what the problem is.

---

## 1. Nothing was broken in the recorder

`HotkeyRecorderViewTests` passed throughout, and driving the recorder inside a real window showed
the whole gesture working: one `makeNSView`, `mouseDown` setting `recording = true`, the view
becoming first responder, and `flagsChanged` arriving with `recording=true`.

The recorder refused the key because `HotkeyBinding.selectable` listed five keys - Right
Option/Command/Control/Shift and Left Option - and Globe was not among them. `pressed()` returned
nil and the view beeped.

**The UI never said which keys were allowed**, so a refusal was indistinguishable from a dead field.
That is the whole user-visible bug.

## 2. The comment that caused it

`ModifierGate.swift` carried:

> Fn is deliberately absent: it does not exist on non-Apple keyboards, and its system action cannot
> be suppressed - `TextInputSwitcher.app` handles the Globe key through `_CGSSetSymbolicHotKey` and
> never enters the event-tap chain at all, so an event tap cannot swallow it.

`docs/research/04` says two separate things, and the comment fused them into one wrong thing:

| | research says |
|---|---|
| **Detect** Fn/Globe | YES - `CGEvent.tapCreate` sees it via `.maskSecondaryFn` (0x800000); `sebsto/wispr`'s Fn tap works |
| **Suppress** it | NO - WindowServer runs the Globe action ahead of every tap |

"Cannot be swallowed" means cannot be SUPPRESSED. The comment read it as cannot be SEEN, and its own
recommendation was *"Fn/Globe offered as an opt-in that warns about the Globe conflict. Do NOT
default to Fn."* "Not the default" had become "not available".

This is the repo's own rule turned on its head - `AGENTS.md` says prefer a measurement to a
citation, and here a citation was not merely preferred over a measurement, it was misquoted.

## 3. Measured, on the real tap

The hotkey probe hardcoded Right Option, so it could not watch this. It takes a binding now:

```
$ PUSHTEXT_HOTKEY_PROBE=1 PUSHTEXT_HOTKEY_PROBE_KEY=globe <app-binary>
HOTKEY_PROBE binding=Globe (fn) keyCode=63 deviceMask=0x800000
HOTKEY_PROBE tap=armed seconds=7.0
HOTKEY_PROBE edge=pressed
HOTKEY_PROBE edge=released
HOTKEY_PROBE finished pressed=1 released=1 reEnables=0
```

with a real `flagsChanged` carrying `maskSecondaryFn`, posted from a separate process. **The tap sees
Globe.**

## 4. What changed

- Globe is selectable, and so are Left Command, Left Control and Left Shift. The five-key list was
  arbitrary; both sides of every held modifier are offered now.
- Globe is matched by its FLAG when the keycode does not match, because `sebsto/wispr` records that
  Apple Silicon may report a keycode other than 63 for it. Safe only because this path sees
  `flagsChanged` alone - the Fn bit is also set on F-keys and arrows, which arrive as `keyDown`.
- Globe is NOT the default. Apple maps it to a vendor-specific HID usage, so a non-Apple keyboard
  emits no `maskSecondaryFn` and defaulting to it would hand those users a dead app with no error.
- A notice appears when Globe is bound and macOS has an action on it. On this machine
  `com.apple.HIToolbox AppleFnUsageType = 3` - Start Dictation - so binding Globe here would start
  Apple's dictation on top of ours, every time.

Five plants on the bindings, four on the conflict reader; all fire.

## 5. Read the setting, never write it

`TISUpdateFnUsageType` would let the app set "Do Nothing" itself, and `OpenWhispr`, `Mojito`,
`inputalk` and `Keyboop` all do exactly that. `Keyboop`'s own source names the hazard: `kill -9`
cannot be intercepted, so a crash leaves the user's Globe key **permanently dead, even after the app
is uninstalled**. An uninstall-proof injury to someone's machine through unversionable private SPI.

Detect and ask. `GlobeKeySetting` reads through `CFPreferencesCopyAppValue` and returns
`.startDictation` on this Mac, matching `defaults read` exactly.

An ABSENT value is treated as a conflict, not as clear: absent means the factory default, and on a
Mac with a Globe key the factory default is not "Do Nothing". Reading absence as harmless would
silence the warning on precisely the machines that need it.

## 6. What this does NOT show

The probe posted a synthetic `CGEvent`. A HARDWARE Globe press travels the same tap, but WindowServer
acts on it first - that is the conflict the notice exists for, and confirming the physical key drives
a dictation end to end needs a person pressing it.

## 7. A test that had to move with the feature

`unbindableKeyIsRefused` used Left Command as its example of a rejected key. Left Command is now
bindable, so the test began asserting the opposite of the feature and failed - correctly. It uses
Caps Lock now, which latches rather than being held and so cannot express push-to-talk.

## 8. Damage done while investigating, and repaired

An instrumented probe run drove the recorder against the REAL user defaults and persisted its
synthetic capture, changing Bobby's hotkey from Right Option to Right Command. Found by rendering
the menu and reading "Right Command" where Globe was expected; restored to 61 and verified.

The packaged smoke isolates `HOME`; that ad-hoc run did not. A probe that can write user state has
to be run with an isolated home, every time.
