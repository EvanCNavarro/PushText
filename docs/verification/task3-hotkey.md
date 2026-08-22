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

## Fault injection — forcing the branches that never run

### Tap re-arm (#21)

`CGEventTapHotkeyMonitor.stallInCallback` sleeps inside the tap callback so the OS disables the tap
and delivers `kCGEventTapDisabledByTimeout`, which is otherwise unreachable — the OS decides when it
fires, and it never fires in normal use.

First attempt used a `.listenOnly` tap, chosen so a slow callback could not delay real input:

```
HOTKEY_PROBE stall=2.0 tapOptions=listenOnly
HOTKEY_PROBE finished pressed=1 released=1 reEnables=0
```

**Hypothesis disproved.** A listen-only tap is never disabled — nothing waits on it, so there is no
timeout to breach. Reaching the branch costs a real, brief, system-wide input stall; there is no safe
shortcut (TRAP-8). Retried on a `.defaultTap`:

```
HOTKEY_PROBE stall=1.5 tapOptions=defaultTap
HOTKEY_PROBE edge=pressed
HOTKEY_PROBE finished pressed=1 released=0 reEnables=1
```

The branch executed — **and exposed a live bug**. `released=0`: the key release was lost.
`ModifierGate` stayed latched down, meaning the microphone open with nothing but a watchdog to close
it.

**That first write-up was wrong, and re-sampling is what caught it.** The `reEnables=1` above came
from a single run. Re-run n=3 at stall 1.5s and n=3 at 3.0s: **0 of 6 reproduced it**, and all six
still showed `released=0`. A later batch gave 2 of 5. So the OS disable is intermittent; the dropped
release is not.

Tracing the resynchronise path showed why no state-based recovery can work:

```
HOTKEY_TRACE watchdog start interval=0.25
HOTKEY_TRACE resync live=0x20080040 mask=0x40 gateDown=true heldNow=true
HOTKEY_TRACE resync live=0x20080040 mask=0x40 gateDown=true heldNow=true
   ... every 250ms, unchanged ...
HOTKEY_PROBE finished pressed=1 released=0 reEnables=0
```

`CGEventSource.flagsState` keeps reporting the right-Option bit SET. A `.defaultTap` sits ahead of
the system's own event processing, so swallowing the key-up stops **macOS itself** from updating
modifier state. The event stream and the live flag state are both wrong, in agreement — there is
nothing to resynchronise against.

A 250 ms `flagsState` poll was built to fix this, measured across 5 runs, shown to change nothing
(recovery correlated with `reEnables=1` exactly, never with the poll), and **removed**. Unproven code
is worse than none.

What landed instead:

- `resynchronise()` after a tap re-arm — correct for the intermittent disable case, kept, but not the
  primary protection.
- **`AppModel.maximumCaptureDuration`** — a time-based force-close driving
  `DictationMachine.watchdogExpired`. Elapsed time is the one signal a dropped event cannot corrupt.
  Four tests; both planted defects (never-arms, never-fires) caught.

### Making the disable branch deterministic (#22)

Two hypotheses died before the answer appeared.

Raising event pressure — a 12-event burst during the stall — reached the branch in **0 of 5** runs.
(`pressed=1` across all 12 pairs also confirms the system stays latched after the first down.)

I then designed a `CGEvent.tapIsEnabled` health-poll timer, on the assumption that the disable
notification might never arrive. The red-first run — fault injection with **no poll** — recovered
**3/3** already:

```
HOTKEY_PROBE killtap=killed enabled=false
HOTKEY_PROBE killtap=after  enabled=true reEnables=1 reason=4294967295
```

`4294967295` is `kCGEventTapDisabledByUserInput`. Disabling your own tap makes the OS deliver the
notification to your callback, so the existing branch was reachable all along — what was missing was
a trigger, not a second mechanism. The health poll was **not built**.

Deterministic at **5/5**. Now a permanent gate in `test-packaged-app.sh`, which asserts
`enabled=true` rather than `reEnables` — a planted no-op re-arm still reports `reEnables=1` while the
tap stays dead, so the counter cannot tell recovery from a corpse (TRAP-11).

### Secure Input (#20)

docs/research/04 sec 1 claims `flagsChanged` keeps flowing while Secure Input is active, unlike
`keyDown`/`keyUp` — the strongest argument for binding a bare modifier instead of a chord. Rather
than wait for a password field, the probe enables Secure Input itself.

The control is the load-bearing part: if `IsSecureEventInputEnabled()` were false the run would prove
nothing, so it is asserted and printed rather than assumed.

```
HOTKEY_PROBE secure=before enabled=false
HOTKEY_PROBE secure=enabled status=0 confirmed=true
HOTKEY_PROBE edge=pressed
HOTKEY_PROBE edge=released
HOTKEY_PROBE secure=result pressed=1 released=1
HOTKEY_PROBE secure=after enabled=false
```

Edges arrive while Secure Input is confirmed active. The claim is reproduced on this machine.
Secure Input is torn down in a `defer`, and `ioreg` afterwards shows no process holding it.

## Hardware confirmation (#19)

Every edge up to this point came from a synthesised `CGEvent` carrying the device bit *because this
code set it*. Posted events enter at `.cghidEventTap`, the same level as hardware, which makes them a
close proxy — but a proxy. The claim that real hardware sets the same bit was READ from
`IOLLEvent.h`, not observed.

Bobby pressed the physical Right Option key with the probe listening:

```
HOTKEY_PROBE binding=Right Option keyCode=61 deviceMask=0x40
HOTKEY_PROBE trusted=true
HOTKEY_PROBE tap=armed seconds=20.0
HOTKEY_PROBE hold and release Right Option to produce edges
HOTKEY_PROBE edge=pressed
HOTKEY_PROBE edge=released
HOTKEY_PROBE edge=pressed
HOTKEY_PROBE finished pressed=2 released=1 reEnables=0
```

`ModifierGate` consults **only** `flags & 0x40`. No synthetic event was posted in this run. Real
hardware therefore sets `NX_DEVICERALTKEYMASK`, and the last inference in the hotkey path is gone.

Kept rather than tidied away: `pressed=2 released=1` — one press has no matching release inside the
20-second window. That is consistent with the key still being held when the window closed, but the
balancing release was not observed. Two later runs recorded 0 edges because no key was pressed
during them; they are not counter-evidence.

## What this did NOT verify

- ~~No physical keypress was ever observed~~ — **closed, see below.**
- **`tapDisabledByUserInput` specifically was never seen.** The re-arm branch is proven via
  `tapDisabledByTimeout`; both disable reasons take the identical code path, so this is covered by
  construction rather than by observation.
- The probe ran Accessibility-trusted by inheriting the terminal's grant. A first-run,
  untrusted launch has not been walked (that is #6).
