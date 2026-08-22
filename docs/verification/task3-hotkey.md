# Task #3 verification — HotkeyMonitor (CGEventTap, held Right Option)

Date: 2026-08-22. Machine: macOS 15.1, Xcode 16.2, Swift 6.0.3.

## Constants, read from the SDK rather than recalled

```
$ grep -nE "NX_DEVICE(L|R)(SHIFT|CTL|ALT|CMD)KEYMASK" \
    $(xcrun --show-sdk-path)/System/Library/Frameworks/IOKit.framework/Versions/A/Headers/hidsystem/IOLLEvent.h
253:#define NX_DEVICELCTLKEYMASK    0x00000001
254:#define NX_DEVICELSHIFTKEYMASK  0x00000002
255:#define NX_DEVICERSHIFTKEYMASK  0x00000004
256:#define NX_DEVICELCMDKEYMASK    0x00000008
257:#define NX_DEVICERCMDKEYMASK    0x00000010
258:#define NX_DEVICELALTKEYMASK    0x00000020
259:#define NX_DEVICERALTKEYMASK    0x00000040
261:#define NX_DEVICERCTLKEYMASK    0x00002000
```

`NX_ALTERNATEMASK` is `0x00080000` — the union bit, set while EITHER Option key is down.

Virtual keycodes from `HIToolbox/Events.h`: `kVK_RightOption = 0x3D`, `kVK_Option = 0x3A`,
`kVK_RightControl = 0x3E`, `kVK_Control = 0x3B`, `kVK_RightCommand = 0x36`, `kVK_Command = 0x37`,
`kVK_ANSI_V = 0x09`.

Worth recording: **right Control is `0x2000`, not `0x2`.** Doubling left Control's `0x1` gives `0x2`,
which is left Shift — a symmetry guess binds the wrong physical key.

## Red-first

`ModifierGate.update`/`isHeld` were stubbed to return `nil`/`false`, then the suite was run:

```
✘ 9 tests, 13 issues — every one "Expectation failed:" with the actual value shown
  e.g. (down → nil) == .pressed
```

Assertions failed, not the harness. Two tests PASSED against the stub, which identified them as
vacuous; `leftOptionNeverTriggersRightBinding` was strengthened to also require the gate to fire for
its own key, so a never-fires implementation can no longer satisfy it.

## Does the suite catch the bug it exists to prevent?

Three defects planted into the implementation, suite re-run each time:

| planted defect | caught |
|---|---|
| `isHeld` reads `NX_ALTERNATEMASK` (the union) instead of the device bit | yes — 4 tests fail |
| right Control's mask guessed by symmetry as `0x2` | yes — 4 issues in one test |
| no change-detection; an edge on every event | yes — 4 tests fail |

Restored: `9 tests passed`.

## The real path — a CGEvent through the real tap

The unit suite proves arithmetic. It says nothing about whether macOS hands this process events.
`HotkeyProbe` (`PUSHTEXT_HOTKEY_PROBE=1`) arms the actual tap and posts a bare modifier through
`CGEvent.post(tap: .cghidEventTap)`, so the event traverses the real tap chain rather than calling
the gate directly.

```
$ PUSHTEXT_HOTKEY_PROBE=1 PUSHTEXT_HOTKEY_PROBE_SYNTHETIC=1 dist/PushText.app/Contents/MacOS/PushText
HOTKEY_PROBE binding=Right Option keyCode=61 deviceMask=0x40
HOTKEY_PROBE trusted=true
HOTKEY_PROBE tap=armed seconds=2.0
HOTKEY_PROBE synthetic=posting driving=Right Option expect=1/1
HOTKEY_PROBE edge=pressed
HOTKEY_PROBE edge=released
HOTKEY_PROBE finished pressed=1 released=1 reEnables=0
```

Negative control — drive LEFT Option, which sets the same union bit, while bound to RIGHT:

```
$ PUSHTEXT_HOTKEY_PROBE=1 PUSHTEXT_HOTKEY_PROBE_SYNTHETIC=other dist/PushText.app/Contents/MacOS/PushText
HOTKEY_PROBE synthetic=posting driving=Left Option expect=0/0
HOTKEY_PROBE finished pressed=0 released=0 reEnables=0
```

A union-mask implementation returns 1/1 here. Side-discrimination therefore holds through the live
tap, not only in unit tests.

## What this did NOT verify

- **No physical keypress was ever observed.** Every edge above came from a synthesised `CGEvent`
  carrying the device bit because this code set it. That real hardware also sets that bit is read
  from `IOLLEvent.h`, not observed — tracked as #19.
- **Secure Input was not tested.** The claim that `flagsChanged` survives it while `keyDown` does not
  comes from docs/research/04 sec 1 and has not been reproduced here — tracked as #20.
- **Tap re-arming was not exercised.** `reEnableCount` stayed 0; neither
  `tapDisabledByTimeout` nor `tapDisabledByUserInput` occurred in a 2-second run, so that branch has
  never executed — tracked as #21.
- The probe ran Accessibility-trusted by inheriting the terminal's grant. A first-run,
  untrusted launch has not been walked (that is #6).
