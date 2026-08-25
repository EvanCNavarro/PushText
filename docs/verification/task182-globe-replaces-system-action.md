# Task 182 - Globe replaces macOS dictation instead of firing beside it

Measured 2026-08-25 on macOS 26.6.2.

Bobby: *"with whispr flow it like overrides the default dictation with the double press globe thing,
why doesn't our app do that instead of like happening with it ... for the globe specific case"*.

---

## 1. My first hypothesis was wrong, and checking it cost one command

I expected Wispr Flow to disable the system setting through the private
`TISUpdateFnUsageType` SPI - the mechanism `docs/research/04` records four shipping apps using.

```
$ nm -u "Wispr Flow" + every .node / .dylib | grep -i "FnUsageType|SymbolicHotKey|SetEventCapture"
(no hits)
$ defaults read com.apple.HIToolbox AppleFnUsageType
3            # Start Dictation - unchanged, while Wispr is running
```

**No private SPI, and the preference is untouched.** Had I filed the "it uses the SPI" explanation
without running `nm`, the fix would have been a dangerous one - that SPI is the one that leaves a
user's Globe key permanently dead after a `kill -9`.

## 2. What Wispr actually does

Its own configuration:

```
prefs.user.shortcuts = {"53": "dismiss", "63": "ptt", "49+63": "popo", "59+63": "lens"}
```

Keycode **63 is Globe**, bound as push-to-talk through an ordinary event tap. Exactly what PushText
does since #176.

## 3. So the difference was one line

`CGEventTapHotkeyMonitor` was already created as `.defaultTap`, which CAN suppress, and then:

```swift
// Always pass the event through untouched. See the class comment.
return Unmanaged.passUnretained(event)
```

The class comment had anticipated this precise need:

> The tap is created as `.defaultTap` rather than `.listenOnly` - it passes every event through
> untouched today, but `.listenOnly` cannot ever suppress, and changing tap type later means [...]

A decision made earlier for a reason that only became load-bearing now.

## 4. Globe only, and the exclusion is the safety

| binding | consumed? | why |
|---|---|---|
| Globe | **yes** | once it is the dictation key it has no other job; its system action is purely in the way |
| Right/Left Shift | no | consuming it stops the user typing capitals |
| Right/Left Command, Control, Option | no | consuming it breaks every shortcut using that modifier |

The release is consumed too. Letting the up-edge through leaves macOS seeing the bare Globe
transition its own action watches for, so suppressing only the press would swallow half a gesture and
still fire the thing being avoided.

## 5. Measured on the real tap, both directions

```
binding=Globe (fn) keyCode=63 deviceMask=0x800000
finished consumed=2 pressed=1 released=1 reEnables=0     <- swallowed, and still acted on

binding=Right Option keyCode=61 deviceMask=0x40
finished consumed=0 pressed=0 released=0 reEnables=0     <- Globe pressed, nothing swallowed
```

`consumedCount` exists because a suppressed event leaves **no other trace by construction** - there
is nothing downstream to observe, so the count is the only way to tell suppression from silence.

Three plants on the policy: suppress-everything, suppress-nothing, and ignore-which-key-was-pressed
all fail the suite.

## 6. What this does NOT show

**Whether swallowing at the tap defeats the WindowServer-run Globe action on a HARDWARE press.**
The probe posts a synthetic `CGEvent`; a real key travels the same tap, but `docs/research/04`
claims WindowServer acts first and cannot be beaten.

Two things weigh against that claim: it is the same document that produced the wrong conclusion in
#176 by conflating "cannot suppress" with "cannot see", and Wispr Flow achieves this on this machine
with no more machinery than a consuming tap. Neither settles it. **One hardware press does**, and
until then the in-app notice about "Press 🌐 key to" stays, because it is the honest fallback if
suppression does not win.
