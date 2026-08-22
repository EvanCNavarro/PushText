# 04 — macOS Plumbing for a System-Wide Push-to-Talk Dictation App

**Target:** macOS 26 "Tahoe", Swift 6, SwiftUI `MenuBarExtra`, built with SPM (no `.xcodeproj`).
**Research date:** 2026-08-22.
**Verification machine:** macOS **Sequoia 15.1** (build 24B83), Xcode 16.2, Swift 6.0.3, MacOSX15.2.sdk, Apple Silicon (T6000).

> **Read this first — the verification contract (Tenet 1 + 2).**
> Every claim below is tagged:
> - `[RUN-VERIFIED 15.1]` — I compiled and ran code on this machine and pasted the output. It is true on Sequoia 15.1. **It says nothing about Tahoe.**
> - `[SDK-VERIFIED 15.2]` — read verbatim out of the MacOSX15.2.sdk headers on disk.
> - `[SOURCE]` — read verbatim out of a cited primary source (Apple docs/forums, or real shipping open-source code).
> - `[UNVERIFIED]` — reported by a secondary source, or Tahoe-specific and therefore un-runnable here. Treat as a hypothesis with a test attached.
>
> **What this whole document could not see:** I do not have macOS 26. Nothing here is a Tahoe *behavioral* result. Every Tahoe claim is documentation-derived or inferred from a shipping app that declares `platforms: [.macOS(.v26)]`. The single highest-risk assumption in the whole report is that the `x-apple.systempreferences:` anchors and the `.cgSessionEventTap` Fn-suppression behavior are unchanged in 26.x. Both have a stated first-boot test in §9.
>
> No UI automation, focus stealing, mouse movement, keystroke synthesis, or `CGEvent` posting was performed at any point. All probes were read-only.

---

## 0. Executive recommendation (the two decisions that matter)

**Hotkey: right-side modifier held (Right-Option or Right-Command) via a `CGEvent` event tap on `.flagsChanged`, with Fn/Globe offered as an opt-in that warns about the Globe conflict. Do NOT default to Fn.**

**Injection: `NSPasteboard` + synthetic ⌘V, with change-count-guarded restore. Do NOT build on `AXUIElement` text setting.**

Both decision tables are in §1.6 and §3.6. The rest of the document is the evidence.

---

## 1. Global push-to-talk hotkey

### 1.1 The four candidate mechanisms, and what each actually costs

| Mechanism | TCC permission | Can see bare modifiers? | Can see Fn/Globe? | Can distinguish L/R? | Can suppress the key? |
|---|---|---|---|---|---|
| `NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged)` | **Accessibility** (`kTCCServiceAccessibility`) | Yes | Yes (`.function` flag) | Yes (via `keyCode` on the event) | **No — observe-only by design** |
| `CGEvent.tapCreate(… .defaultTap)` | **Accessibility** in practice; Input Monitoring for `.listenOnly` | Yes | Yes (`.maskSecondaryFn`) | Yes (`keyCode` + device-dependent flag bits) | **Yes** (return `nil` from callback) |
| Carbon `RegisterEventHotKey` | **None** | **No** | **No** | No | Yes (implicitly) |
| `CGRequestListenEventAccess` / `CGPreflightListenEventAccess` | — (these are *permission* calls, not a monitoring mechanism) | n/a | n/a | n/a | n/a |

The fourth item in the brief is a category error worth naming explicitly: `CGPreflightListenEventAccess()` / `CGRequestListenEventAccess()` are **not a way to detect keys**. They are the check-and-prompt pair for the **Input Monitoring** (`kTCCServiceListenEvent`) TCC service, introduced in macOS 10.15, and you call them *before* creating a listen-only tap. `[SDK-VERIFIED 15.2]`:

```c
// MacOSX15.2.sdk/…/CoreGraphics.framework/Headers/CGEvent.h
CG_EXTERN bool CGPreflightListenEventAccess(void) API_AVAILABLE(macos(10.15));   // :399
CG_EXTERN bool CGRequestListenEventAccess(void)  API_AVAILABLE(macos(10.15));   // :402
CG_EXTERN bool CGPreflightPostEventAccess(void)  API_AVAILABLE(macos(10.15));   // :405
CG_EXTERN bool CGRequestPostEventAccess(void)    API_AVAILABLE(macos(10.15));   // :408
```

Note the **fourth** function, which the brief did not mention and which you will need: `CGPreflightPostEventAccess` gates *posting* synthetic events — i.e. the ⌘V injection in §3. Listen and Post are separate privileges.

`[RUN-VERIFIED 15.1]` — all four preflights, plus the IOKit and AVFoundation equivalents, compiled and ran read-only (no prompts triggered, `kAXTrustedCheckOptionPrompt` deliberately not used):

```
macOS: Version 15.1 (Build 24B83)
CGPreflightListenEventAccess() = true
CGPreflightPostEventAccess()   = true
AXIsProcessTrusted()           = true
IOHIDCheckAccess(listen)       = 0   (0=granted,1=denied,2=unknown)
IOHIDCheckAccess(post)         = 0
AVCaptureDevice.authorizationStatus(.audio) = 3  (0=notDetermined,1=restricted,2=denied,3=authorized)
IsSecureEventInputEnabled() = false
```

**Blind spot on that run (Tenet 1):** those `true`/granted values are the *inherited terminal's* TCC grants, not a fresh app's. They prove the APIs exist, link, and return without prompting. They prove **nothing** about what an unsigned first-launch `mumbler.app` will see — that will be `false`/denied until granted. The value of this run is API existence and call-shape, not the verdict.

### 1.2 The permission split — verified from the system, not from a blog

This is the part every article gets slightly wrong, so I read it off the OS. `[RUN-VERIFIED 15.1]` — the System Settings privacy pane ships an authoritative anchor→TCC-service table on disk:

```
/System/Library/ExtensionKit/Extensions/SecurityPrivacyExtension.appex
  bundle id: com.apple.settings.PrivacySecurity.extension
  Contents/Resources/TCCServiceList.plist
```

Relevant rows, verbatim from `plutil -p`:

```
11 => { "revealElementKeyName" => "Privacy_SpeechRecognition"
        "serviceName" => "SPEECH_RECOGNITION"
        "tcc" => "kTCCServiceSpeechRecognition" }

16 => { "serviceClass" => "TCCServiceAccessibility" }

17 => { "requiresAdmin" => 1
        "revealElementKeyName" => "Privacy_ListenEvent"
        "serviceIcon-shared" => "com.apple.graphic-icon.input-monitoring"
        "serviceName" => "LISTEN_EVENT"
        "supportsAddDeleteAction" => 1
        "tcc" => "kTCCServiceListenEvent" }
```

Three findings from that, none of which I found stated correctly anywhere online:

1. **Input Monitoring is `requiresAdmin => 1`. Accessibility is not.** Toggling Input Monitoring makes the user authenticate. Accessibility does not. That is a real onboarding-friction difference and it argues for the Accessibility-based path.
2. **There is no `kTCCServicePostEvent` row.** PostEvent has no pane of its own; it is surfaced under Accessibility in the UI. So `CGPreflightPostEventAccess()` and `AXIsProcessTrusted()` are gated by the same visible toggle, but they are *distinct* TCC services under the hood — which is exactly why an app can be "in the Accessibility list" and still fail to post events after a re-sign.
3. `Privacy_ListenEvent` and `Privacy_SpeechRecognition` both exist as anchors on 15.1 — see §4.3 for what that means for deep links.

The commonly cited split — `NSEvent` global monitors need **Accessibility**, `CGEventTap` needs **Input Monitoring** — is a historical simplification. In practice a `.defaultTap` (one that can *modify or suppress* events) is gated by Accessibility, while `.listenOnly` is gated by Input Monitoring. Shipping code confirms the former: `sebsto/wispr` logs `"CGEvent.tapCreate returned nil (missing Accessibility permission?)"` on failure and its `PermissionManager` checks **only** `AXIsProcessTrusted()` — it never calls `CGPreflightListenEventAccess` at all, and its Fn event tap works. `[SOURCE]`

**Consequence for mumbler: request Accessibility only.** You need it anyway for ⌘V posting. Adding an Input Monitoring request adds an admin-authentication step for zero capability gain.

### 1.3 Fn/Globe: the flag, the keycode, and why the keycode is a trap

`[SDK-VERIFIED 15.2]` — the Fn bit is the same value in three namespaces:

```c
// IOKit.framework/Headers/hidsystem/IOLLEvent.h:248
#define NX_SECONDARYFNMASK  0x00800000
// CoreGraphics.framework/Headers/CGEventTypes.h:92
kCGEventFlagMaskSecondaryFn = NX_SECONDARYFNMASK,
```

`[RUN-VERIFIED 15.1]`:

```
NSEvent.ModifierFlags.function.rawValue = 0x800000
kCGEventFlagMaskSecondaryFn             = 0x800000
kVK_Function = 63
```

So `NSEvent.ModifierFlags.function` and `CGEventFlags.maskSecondaryFn` are **bit-identical** — `0x800000`. You can move between the AppKit and CoreGraphics worlds without a translation table.

**Detect Fn by the FLAG *and* gate on keycode 63 — neither alone is correct.** Both halves of the folklore are wrong, and I found the counter-evidence for each.

*Flag alone is not sufficient.* `[SDK-VERIFIED 15.2]`, `AppKit/Headers/NSEvent.h:171`, verbatim — and read the comment carefully:

```objc
NSEventModifierFlagFunction = 1 << 23, // Set if any function key is pressed.
```

**"Any function key"** — arrow keys, Home/End/PageUp/PageDown and F1–F20 all set this bit on a laptop keyboard. Testing `flags.contains(.function)` in isolation gives false positives. VoiceInk handles this by *stripping* `.function` from the flags whenever the keycode is an F-key, precisely because macOS sets `SecondaryFn` on F1–F20 events on laptops `[SOURCE]` <https://github.com/Beingpax/VoiceInk/blob/main/VoiceInk/Shortcuts/Shortcut.swift>.

*Keycode alone is not sufficient either.* `sebsto/wispr` ships a comment saying Apple Silicon Macs may report a keycode other than 63 in `flagsChanged` for the Globe key `[SOURCE]`.

**The resolution:** a `flagsChanged`-only mask already filters out most of the false-positive space (F-keys and arrows arrive as `keyDown`, not `flagsChanged`). Then use the *flag* to determine down/up state and the *keycode* as the identity gate, and bail out if any other modifier is set. That is what the most rigorous of the surveyed apps does — `slovo` unit-tests exactly `.flagsChanged(keyCode: 63, flags: [.secondaryFn])` → `.start(suppress: true)` `[SOURCE]` <https://github.com/Akurganow/slovo>. Reference implementation from `sebsto/wispr` `[SOURCE]`, which uses the flag and the other-modifier guard (add the keycode gate yourself):

```swift
/// Detects the Fn/Globe key by monitoring the `maskSecondaryFn` flag rather
/// than relying on the keycode, because Apple Silicon Macs may report a
/// keycode other than 63 in flagsChanged events for the Globe key.
private func handleFnFlagsChanged(flags: CGEventFlags) -> Bool {
    // Pass through if other modifiers are held (Fn+Cmd, Fn+Opt, etc.)
    let otherModifiers: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
    if !flags.intersection(otherModifiers).isEmpty { return false }

    let isFnDown = flags.contains(.maskSecondaryFn)
    if isFnDown && !self.fnIsDown {
        self.fnIsDown = true
        onHotkeyDown?()
        return true   // consume — suppress emoji picker
    } else if !isFnDown && self.fnIsDown {
        self.fnIsDown = false
        onHotkeyUp?()
        return true   // consume
    }
    return false
}
```
— <https://github.com/sebsto/wispr/blob/main/Sources/WisprApp/Services/HotkeyMonitor.swift>

**The hardware reason Fn is weird, and why it dies on third-party keyboards.** Apple's own keyboards map Globe to a **vendor-specific HID usage** — page `0xFF`, usage `0x03` — not a standard keyboard usage. Apple does not expose globe-as-modifier through standard USB peripherals, so a non-Apple keyboard's "Fn" key does **not** produce `maskSecondaryFn` at all. `[UNVERIFIED — secondary source]` <https://github.com/keyboardio/Chrysalis/issues/1310>. An Apple developer-forum thread separately records the mismatch: `.maskSecondaryFn` corresponds to `0xFF0100000030` while the IOHID usage ID for the real hardware Fn (Globe) key is `0xFF00000003`, and reports it as **FB15532267** `[SOURCE]` <https://developer.apple.com/forums/thread/766200>. That thread is about *synthesizing* Fn (which does not work); *detecting* it via the flag does work. Do not conflate the two.

> **Product consequence:** if you ship Fn as the default binding, every user on a Keychron / Logitech / HHKB silently has a dead app, with no error to show them. That alone disqualifies Fn as a default.

### 1.4 Left vs right modifier disambiguation — the exact bits

`[SDK-VERIFIED 15.2]`, `IOKit.framework/Headers/hidsystem/IOLLEvent.h:253-261`, verbatim:

```c
/* device-dependent (really?) */
#define NX_DEVICELCTLKEYMASK    0x00000001
#define NX_DEVICELSHIFTKEYMASK  0x00000002
#define NX_DEVICERSHIFTKEYMASK  0x00000004
#define NX_DEVICELCMDKEYMASK    0x00000008
#define NX_DEVICERCMDKEYMASK    0x00000010
#define NX_DEVICELALTKEYMASK    0x00000020
#define NX_DEVICERALTKEYMASK    0x00000040
#define NX_DEVICERCTLKEYMASK    0x00002000
```

(The `(really?)` is Apple's comment, not mine. Note `NX_DEVICERCTLKEYMASK` is `0x2000`, far from its siblings — it was bolted on later, and `NX_DEVICELCTLKEYMASK` is `0x1`. There is no symmetry to pattern-match; use the constants.)

`[RUN-VERIFIED 15.1]` — the virtual keycodes, printed from `Carbon.HIToolbox`:

```
kVK_Control=59  kVK_RightControl=62
kVK_Command=55  kVK_RightCommand=54
kVK_Shift=56    kVK_RightShift=60
kVK_Option=58   kVK_RightOption=61
kVK_Function=63
```

This confirms the brief's numbers exactly: **Control 59 (L) vs 62 (R)**, and **Command 55 (L) vs 54 (R)** — note Command is the one pair where the *right* key has the *lower* number, which is a classic off-by-one bug source.

**Two independent ways to disambiguate, and which to use:**

- **Preferred — the `keyCode` on the `flagsChanged` event.** A `.flagsChanged` event carries the keycode of the modifier that actually changed. `62` means Right-Control changed state; combine with `flags.contains(.maskControl)` to know whether it went down or up. This is unambiguous and needs no private bit knowledge.
- **Secondary — the device-dependent bits above.** `flags.rawValue & NX_DEVICERCTLKEYMASK != 0` tells you Right-Control is *currently held*. Useful for a state resync (e.g. after wake, or after a missed key-up), not as the primary edge detector.

Use both: keycode for the edge, device bits for the periodic "is it actually still down?" reconciliation. A stuck-key bug in a push-to-talk app means a hot mic, which is the worst failure this app has.

### 1.5 Carbon `RegisterEventHotKey` — why it cannot do push-to-talk

Three disqualifying facts, in order of severity:

0. **It cannot bind a right-side modifier at all — Apple says so in the header.** `[SDK-VERIFIED 15.2]`, `Carbon/HIToolbox/Events.h:117-130`, verbatim:
```c
  rightShiftKeyBit    = 13,   /* right shift key down? Not supported on Mac OS X.*/
  rightOptionKeyBit   = 14,   /* right Option key down? Not supported on Mac OS X.*/
  rightControlKeyBit  = 15    /* right Control key down? Not supported on Mac OS X.*/
  ...
  rightControlKey     = 1 << rightControlKeyBit /* Not supported on Mac OS X.*/
```
Carbon has only four undifferentiated modifiers. Right-Control is not expressible, full stop.
1. **It cannot bind a bare modifier at all.** It takes a keycode *plus* modifiers; there is no "just Right-Control" registration. Confirmed by the shipping app that tried: *"The standard Carbon RegisterEventHotKey API that Wispr uses for modifier+key combos does not support the bare Fn key. So v1.6 introduces a dual-backend architecture: Carbon for standard shortcuts, and a CGEventTap for the Fn key specifically."* `[SOURCE]` <https://stormacq.com/2026/03/30/one-month-of-wispr-from-first-release-to-cli/>
2. **macOS 15 broke option/shift-only registrations on purpose.** An Apple Frameworks Engineer, verbatim: *"This was an intentional change in macOS Sequoia to limit the ability of key-logging malware to observe keys in other applications. The issue of concern was that shift+option can be used to generate alternate characters in passwords, such as Ø (shift-option-O)."* Error: **-9868 (`eventInternalErr`)**. Policy: **at least one modifier that is not shift or option**. Partially relaxed again in 15.2 Beta 2. `[SOURCE]` <https://developer.apple.com/forums/thread/763878> and <https://github.com/feedback-assistant/reports/issues/552>
3. **It gives you press/release but not hold semantics you control.** It *does* deliver `kEventHotKeyReleased` (wispr uses it), so hold-to-talk is technically possible for a chord — but you are then holding e.g. ⌃⌥Space for the whole utterance, which is a worse ergonomic than one thumb key.

The one thing Carbon has that nothing else does: **it needs no TCC permission whatsoever.** That is genuinely valuable and is why you should keep it as a *secondary* backend for users who refuse to grant Accessibility — they get a chord hotkey and no push-to-talk. Real code for the Carbon path (`[SOURCE]`, `sebsto/wispr`, `HotkeyMonitor.swift`):

```swift
var eventTypes = [
    EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
    EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
]
let selfPtr = Unmanaged.passUnretained(self).toOpaque()
let callback: EventHandlerUPP = { nextHandler, event, userData in
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    return Unmanaged<HotkeyMonitor>.fromOpaque(userData).takeUnretainedValue().handleCarbonEvent(event)
}
var handlerRef: EventHandlerRef?
InstallEventHandler(GetApplicationEventTarget(), callback, eventTypes.count, &eventTypes, selfPtr, &handlerRef)
var hotKeyRef: EventHotKeyRef?
RegisterEventHotKey(keyCode, modifiers, Self.hotkeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
```

### 1.6 DECISION TABLE — hotkey

| | `NSEvent` global monitor | **`CGEvent` tap (`.defaultTap`)** | Carbon `RegisterEventHotKey` |
|---|---|---|---|
| Permission | Accessibility | Accessibility | **none** |
| Admin auth required | no | no | no |
| Bare held modifier | ✅ | ✅ | ❌ |
| Fn/Globe | ✅ detect | ✅ detect | ❌ |
| Right-Control alone | ✅ | ✅ | ❌ |
| Can suppress the key | ❌ | ✅ | n/a |
| Survives Sequoia's modifier clampdown | ✅ | ✅ | ⚠️ -9868 |
| Dies under Secure Input | keyed: yes · **bare modifier: NO** | keyed: yes · **bare modifier: NO** | ❌ (survives) |
| Can be silently disabled by the system | no | **yes** — needs a watchdog | no |
| Sandbox-compatible | ❌ | ❌ (Accessibility is barred in the sandbox) | ✅ |

**PICK: `CGEvent.tapCreate` with `.defaultTap` on `.cgSessionEventTap`, `.headInsertEventTap`, mask `1 << CGEventType.flagsChanged.rawValue`.**

**Reason:** it is the only mechanism that satisfies the two hard requirements simultaneously — *bare held modifier* and *suppress the keystroke so the host app never sees a stray modifier*. `NSEvent`'s global monitor matches it on detection but is observe-only by design, so the modifier leaks through to the focused app. Carbon cannot express the binding at all.

**Default binding: Right-Option (`kVK_RightOption` = 61) or Right-Command (54).** Not Fn — Fn is dead on third-party keyboards (§1.3) and fights the OS (§2). Not Right-Control — it is genuinely used (⌃-click, Emacs bindings, and it is the *other* half of the double-Control dictation shortcut). Right-Option is the least-claimed thumb-reachable key on an Apple keyboard, and being right-side-specific means Left-Option keeps working for `å ß ∂ ƒ` and everything else. Offer Fn and Right-Control as opt-ins with a warning sheet.

**Two things you must build alongside the tap, not later:**

1. **A tap watchdog.** The system disables taps that are slow (`.tapDisabledByTimeout`) or when the user does certain things (`.tapDisabledByUserInput`), and a non-nil tap is not a healthy tap. `[SOURCE]` <https://danielraffel.me/til/2026/02/19/cgevent-taps-and-code-signing-the-silent-disable-race/> recommends polling `CGEvent.tapIsEnabled(tap:)` and re-enabling. wispr does it inside the callback with a bounded retry (3 attempts, then unregister and surface the failure) `[SOURCE]`:

```swift
if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
    monitor.tapReEnableAttempts += 1
    if monitor.tapReEnableAttempts <= monitor.maxTapReEnableAttempts {
        if case .fnEventTap(let port, _) = monitor.activeBackend { CGEvent.tapEnable(tap: port, enable: true) }
    } else {
        monitor.unregister()   // give up loudly rather than pretend
    }
    return false
}
```

2. **Re-register on wake.** Taps and hotkeys die across sleep. wispr observes `NSWorkspace.didWakeNotification` and calls `verifyRegistration()` (which round-trips an unregister/register) `[SOURCE]`. Without this, the app is silently deaf every morning.

**Swift 6 concurrency note, and it is not a footnote.** The `CGEventTapCallBack` is a C function pointer — it captures nothing and `CGEvent` is not `Sendable`. The pattern that actually compiles under `.swiftLanguageMode(.v6)` is to extract the values you need *before* crossing into actor isolation, then `MainActor.assumeIsolated` (valid because the run-loop source is on `CFRunLoopGetMain()`) `[SOURCE]`:

```swift
let callback: CGEventTapCallBack = { proxy, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let flags = event.flags                              // extract BEFORE isolation
    let passthrough = Unmanaged.passUnretained(event)
    let consumed: Bool = MainActor.assumeIsolated {
        let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
        return monitor.handleFnFlagsChanged(flags: flags)
    }
    return consumed ? nil : passthrough                   // nil == swallow the event
}
```

**Latency warning:** do not be tempted into `.listenOnly` to get Input Monitoring instead of Accessibility. Listen-only taps are reported to lag *"on the order of a significant fraction of a second"* `[UNVERIFIED — secondary]`, which is fatal for push-to-talk. And `.listenOnly` cannot suppress the key anyway.

---

## 2. The Fn/Globe conflict, in detail

### 2.1 What the system does with Fn

System Settings ▸ Keyboard ▸ **"Press 🌐 key to:"** offers *Change Input Source / Show Emoji & Symbols / Start Dictation / Do Nothing*. On a Mac with a Globe key the factory default is not "Do Nothing", so a bare Fn press already means something to the OS before your app ever sees it.

### 2.2 Can you suppress it? — **No.** And I found the mechanism.

`[RUN-VERIFIED 15.1]` — the Globe action is implemented by a userspace agent, `/System/Library/CoreServices/TextInputSwitcher.app`, and I read its binary on this machine. Its log strings:

```
Globe key is dispatched.
Globe key is discarded.
Globe key triggered Emoji.
Globe key triggered HUD.
Globe key skipped show HUD which is visible.
%s: Globe key moved HUD selection to next item.
```

Its undefined-symbol imports (`nm -u`) include `_TISGetFnUsageType`, `_CGSSetSymbolicHotKey`, `_CGSGetSymbolicHotKeyValue`, `_CGSIsSymbolicHotKeyEnabled`, `_CGSSetEventCapture`, `_CGSRegisterNotifyProc`.

**And the count of `CGEventTapCreate` imports is `0`.**

That is the whole answer. `TextInputSwitcher` is not in the event-tap chain at all. WindowServer detects the Globe press through its **symbolic hot key** machinery and notifies the agent out-of-band. You are not racing another tap that you could beat by inserting at the head — you are downstream of a mechanism that never enters the tap chain.

**Corroboration, three ways:**
1. The contradiction inside `sebsto/wispr`: its callback returns `nil` with `// consume — suppress emoji picker`, yet its release notes still tell users *"set that option to 'Do Nothing'"* `[SOURCE]` <https://stormacq.com/2026/03/30/one-month-of-wispr-from-first-release-to-cli/>. Consumption does not win.
2. `OpenWhispr` ships this comment and, tellingly, does not even *try* to tap Fn — it uses an observe-only `NSEvent` global monitor for Fn and reserves its `.defaultTap` for mouse buttons `[SOURCE]` <https://github.com/OpenWhispr/openwhispr>:
> *"macOS runs the standalone Globe action (emoji viewer, input-source switch, dictation) from WindowServer ahead of every event tap, so a listener cannot consume the key — the only way to stop it firing alongside an OpenWhispr Globe hotkey is to hold AppleFnUsageType at 'Do Nothing' while we own the key."*
3. Every tool built specifically around the Globe key instructs the user to set "Do Nothing": `Serpentiel/betterglobekey`, and Raycast's own docs `[SOURCE]` <https://manual.raycast.com/ai/dictation>: *"set it to Do Nothing so the system doesn't intercept the press first."*

### 2.2b The private SPI escape hatch — and why not to take it

`[RUN-VERIFIED 15.1]` — the setting lives at `com.apple.HIToolbox` / `AppleFnUsageType` (on this machine: `3`). The mapping, from three concurring sources `[SOURCE]` <https://macos-defaults.com/keyboard/applefnusagetype.html>, <https://github.com/nix-darwin/nix-darwin>:

| Value | Behavior |
|---|---|
| 0 | Do Nothing |
| 1 | Change Input Source |
| 2 | Show Emoji & Symbols |
| 3 | Start Dictation |

`[RUN-VERIFIED 15.1]` — `TISGetFnUsageType` and `TISUpdateFnUsageType` **are exported** from `Carbon.tbd`/`HIToolbox.tbd`, but `grep -rn "FnUsageType"` across `Carbon.framework/**/Headers/` returns **nothing**. Exported and undeclared ⇒ **private SPI**. Writing the preference directly with `defaults`/`CFPreferencesSetValue` does not take effect until restart/login; `TISUpdateFnUsageType` is what System Settings itself calls, and it applies live.

Several shipping apps do exactly this — `OpenWhispr`, `Mojito`, `inputalk`, `Keyboop` — dlopening Carbon, saving the prior value, setting `0` while they own the key, and restoring on exit. **Do not copy them.** `Keyboop`'s own source comment names the hazard: `kill -9` cannot be intercepted, so a crash leaves the user's Globe key **permanently dead, even after your app is uninstalled**. That is an unrecoverable, uninstall-proof injury to someone's machine, caused by a private SPI you cannot version-check. It is also App Store disqualifying.

**The correct design is detect-and-ask.** Read the setting non-destructively and warn only when it actually bites. `slovo` has the cleanest implementation `[SOURCE]` <https://github.com/Akurganow/slovo>:

```swift
public struct SystemFnKeyAssignmentReader: FnKeyAssignmentReading {
    public var isFnKeySystemAssigned: Bool {
        // The "Press 🌐 key to" choice lives in another application's preference
        // domain, so CFPreferences is the way in — this app's UserDefaults cannot
        // see it.
        let usageType = CFPreferencesCopyAppValue("AppleFnUsageType" as CFString,
                                                  "com.apple.HIToolbox" as CFString) as? Int
        return FnKeyAssignment.isAssigned(usageType: usageType)
    }
}
// `0` is the explicit "Do Nothing" setting and `nil` means the preference was
// unreadable; both must read as unassigned so a conflict is never invented.
public static func isAssigned(usageType: Int?) -> Bool { (usageType ?? 0) != 0 }
```
surfaced as a menu item only when `hotkeys.usesFnKey && isFnKeySystemAssigned`:
> *"fn also triggers a macOS action — set 'Press 🌐 key to' to 'Do Nothing' in System Settings ▸ Keyboard"*

Note the `nil → unassigned` decision. That is Tenet 8 in code: an unreadable preference produces an honest silence, not a fabricated warning.

### 2.3 The second-order breakage nobody warns about

Swallowing bare-modifier `flagsChanged` events breaks the **system's own** double-tap shortcuts, because those are modifier-only sequences that AppKit/the OS detects by watching the same stream. Documented in the wild in kitty: *"The local flagsChanged event monitor … consumes bare modifier sequences before macOS can detect the double-press. The double-Fn/Globe dictation shortcut is a modifier-only sequence handled by macOS, so swallowing those flagsChanged events prevents AppKit from detecting the shortcut."* `[SOURCE]` <https://github.com/kovidgoyal/kitty/issues/9661> and the double-Control variant <https://github.com/kovidgoyal/kitty/issues/10119>.

**Consequence for mumbler:** if you bind Right-Control and consume it, you kill the user's double-Control system dictation. If you bind Fn and consume it, you kill double-Fn. **Only consume the events for the key you are actually bound to, only while no other modifier is held, and consider not consuming at all for a right-side modifier** — a stray Right-Option keypress does nothing harmful in most apps, whereas a swallowed one breaks other things. Test both before shipping.

### 2.4 What the commercial apps actually do — and the headline finding

I surveyed six shipping dictation apps' own documentation. **All six default to or prominently support bare Fn. Not one of them tells the user to set "Press 🌐 key to → Do Nothing."** The only vendor that documents the step is Raycast, which is not a dictation app.

| App | Default macOS hotkey | Fn supported | Documents the Globe conflict |
|---|---|---|---|
| **Wispr Flow** | **Fn** (falls back to `⌃⌥` "if no Apple Fn key is detected at first run"); `Fn+Space` hands-free, `Fn+⌃` command mode | ✅ | ❌ |
| **superwhisper** | not stated `[UNVERIFIED]` — docs say *"Single modifier keys (like Left Command, Right Command, or Fn key) can be used independently"*; changelog v1.15.3 (2023-10-25) says *"Remove Fn from keyboard shortcuts"* with no recorded re-add | ✅ (per docs) | ❌ |
| **VoiceInk** | not stated; supports Right Option, Left Option, Right Command, Right Control, Left Control, Right Shift, Fn | ✅ — issue #158 closed 2026-03-19 *"fully supported as a push-to-talk/toggle hotkey **with debounce handling**"* | ❌ (`grep -ri globe` over the full clone: only SF Symbol icon uses) |
| **MacWhisper** | Fn or right ⌘ | ✅ | ⚠️ closest of the six — v13.6 changelog: *"Added extra guidance to the dictation settings if you chose the Fn key without setting it up correctly in macOS settings"* |
| **Aqua Voice** | **Fn** ("Show Recommended" → Fn) | ✅ | ❌ |
| **Willow** | **Fn**, double-tap for hands-free | ✅ | ❌ — and its docs claim Fn *"typically isn't tied to any other actions"*, which is **false** on a stock Mac |
| *(Raycast, for contrast)* | multi-modifier or single-tap modifier | — | ✅ *"set it to Do Nothing so the system doesn't intercept the press first"* |

`[SOURCE]` <https://docs.wisprflow.ai/articles/2612050838-supported-unsupported-keyboard-hotkey-shortcuts>, <https://superwhisper.com/docs/get-started/settings-shortcuts>, <https://tryvoiceink.com/docs/shortcuts>, <https://github.com/Beingpax/VoiceInk/issues/158>, <https://docs.macwhisper.com/article/14-how-to-use-the-dictation-feature>, <https://aquavoice.com/info/faq>, <https://help.willowvoice.com/en/articles/10876257-hotkey-settings>, <https://manual.raycast.com/ai/dictation>

**Note the word "debounce" in VoiceInk's issue close.** That is the tell for the real Fn failure mode — see below.

### 2.4b What users actually report breaking

- **Emoji picker fires — and disabling it still does not fix the app.** VoiceInk #158, 2026-02-12: *"hitting the fn key launches the emoji window on mac and even after I disable that in keyboard settings it doesn't seem to be able to trigger voiceink."* `[SOURCE]` <https://github.com/Beingpax/VoiceInk/issues/158>. Setting "Do Nothing" is **necessary but not sufficient**; that comment was never answered in-thread.
- **The stuck-modifier catastrophe.** Apple Developer Forums, Jan 2026 `[SOURCE]` <https://developer.apple.com/forums/thread/814074>: *"when many keyboard events are happening… in quick succession (<250ms), the enable dictation popup or the function button emojis popup appear for seemingly no reason."* The reporter names the mechanism himself: *"dictation and emojis can pop up using fn + d and fn + e respectfully."* **A push-to-talk app that holds Fn turns every subsequent D and E the user types into a system popup.** This is the single most damaging Fn failure mode and it is why VoiceInk needed "debounce handling."
- **Random emoji popups in the wild** — HN: *"Randomly opens emoji keyboard on me"*; *"I never noticed the Globe before, and now I know why the emoji keyboard sometimes pops up."* `[SOURCE]` <https://news.ycombinator.com/item?id=47311647>
- **Fn is absent on non-Apple keyboards** — vendor-confirmed by Wispr Flow: *"The Apple Fn key is a hardware-level signal unique to Apple-built keyboards."* Mechanism: fn is Usage Page `0xFF` (AppleVendor Top Case), Usage `0x03` (KeyboardFn), and requires VID `0x05AC`. `[SOURCE]` <https://mjtsai.com/blog/2023/11/20/the-hidden-secrets-of-the-fn-key/>, <https://developer.apple.com/forums/thread/705832>. Karabiner-Elements must accept **two different vendor pages** because different Apple keyboards report Fn differently — `apple_vendor_top_case` (0x00ff) usage `keyboard_fn` (0x0003) *and* `apple_vendor_keyboard` (0xff01) usage `function` (0x0003) `[SOURCE]` <https://github.com/pqrs-org/Karabiner-Elements/blob/main/src/share/event_tap_utility.hpp>.
  - Wispr's docs say built-in only; aresluna.org says Apple's external Magic Keyboard works too. **These conflict and neither was tested.** `[UNVERIFIED]`
- **Double-tap collision.** Apple's own setting says *"Start Dictation: Starts dictation when you press the key twice."* Willow and Wispr both use double-tap-of-hotkey for hands-free mode. On a stock Mac these double-fire. `[UNVERIFIED — inferred from two documented behaviors; no user report found demonstrating it.]`

### 2.5 Known conflicting third-party apps

Karabiner-Elements is the single most common conflict (it remaps Fn at the HID layer, below you); BetterTouchTool and Rectangle Pro also claim it. `[UNVERIFIED — secondary]` If the tap sees no Fn events at all, a Karabiner check is the first diagnostic to run.

---

## 3. Text injection into the frontmost app

### 3.1 (a) AXUIElement — `kAXFocusedUIElement` + set `kAXSelectedText`

**Verdict: do not build on it.** It fails on exactly the apps a dictation user lives in.

- **Silent no-op failures.** `AXUIElementSetAttributeValue` can return **success while doing nothing** — reported for Google Docs, VS Code, and even Apple's own Pages. And you cannot detect this by reading back: `kAXSelectedTextAttribute` is an empty string both before and after when nothing is selected, regardless of success. There is no reliable verification. `[UNVERIFIED — secondary, but multiply corroborated]`
- **Electron needs an out-of-band unlock.** Electron apps (Slack, Discord, VS Code, Obsidian) do not expose an accessibility tree until an assistive app sets the `AXManualAccessibility` attribute on their application element. `[SOURCE]` <https://www.electronjs.org/docs/latest/tutorial/accessibility/>. And that attribute frequently returns `kAXErrorAttributeUnsupported` in practice. `[SOURCE]` <https://github.com/electron/electron/issues/37465>. Even when the tree appears, there is no usable cursor selection from Electron.
- **Electron's selection ranges are wrong even when present** — lines starting with whitespace select the wrong character range; selecting to end-of-line captures the following line break. `[SOURCE]` <https://github.com/electron/electron/issues/36337>
- **It is barred by the App Sandbox.** This is the killer if you ever want notarized/App Store distribution. `sebsto/wispr` states it in a code comment as its stated reason for not using AX at all `[SOURCE]`:

> *"The app runs under the App Sandbox (required for notarized/Developer ID and App Store distribution), which prohibits using the Accessibility API (`AXUIElement`) to read or control other apps' UI. Clipboard + ⌘V (via `CGEvent`, which uses the separate PostEvent privilege) is therefore the only viable way to insert text at the cursor in an arbitrary third-party app."*

**Where AX *is* worth using:** read-only context, not writing. `kAXFocusedUIElement` + `kAXRole` tells you whether focus is in a text field at all (so you can refuse to fire and avoid dumping a paragraph into a game), and `kAXTitle`/bundle id tells you which app you are in (so you can special-case Terminal). Use it as a sensor, never as an actuator.

### 3.2 (b) NSPasteboard + synthetic ⌘V — the one that works

This is what every serious app does. Real, complete, production implementation `[SOURCE]` — `sebsto/wispr`, `Sources/WisprApp/Services/TextInsertionService.swift`:

```swift
private static func postCommandV() -> Bool {
    guard let keyDownEvent = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: true)  // V
    else { return false }
    keyDownEvent.flags = .maskCommand
    guard let keyUpEvent = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: false)
    else { return false }
    keyUpEvent.flags = .maskCommand
    keyDownEvent.post(tap: .cghidEventTap)
    keyUpEvent.post(tap: .cghidEventTap)
    return true
}
```

Note `.cghidEventTap` — post at the **HID** level, not the session level, so the event enters the stream as if from hardware and every app (including ones with their own session taps) sees it.

**Reliability:** near-universal. Every app that supports ⌘V supports this, which is every app. Native, Electron, Chrome/Safari web fields, Terminal/iTerm — all fine. Terminal is the one place to be careful: ⌘V is right, but if the user is in a vim insert-mode-less context or a TUI with bracketed paste off, a multi-line paste can execute lines. Consider stripping trailing newlines when the frontmost app is a terminal.

**Speed for a 500-char paragraph:** effectively instant — one pasteboard write plus two event posts, independent of length. This is the decisive advantage over per-character injection.

**Clipboard clobbering — do it right or not at all.** The naive "save string, paste, restore string" loses rich content and races the user. The correct algorithm, from shipping code `[SOURCE]`:

1. Save **all types**, as `Data`, not just `.string`:
```swift
private func saveCurrentPasteboardContents(_ pasteboard: any TextPasteboard) -> [NSPasteboard.PasteboardType: Data] {
    var contents: [NSPasteboard.PasteboardType: Data] = [:]
    for type in pasteboard.types ?? [] {
        if let data = pasteboard.data(forType: type) { contents[type] = data }
    }
    return contents
}
```
2. **Only capture the original if a restore is not already pending** — otherwise a second dictation within the window captures *your own transcription* as "the original".
3. Snapshot `pasteboard.changeCount` **after** staging your text and **before** posting ⌘V.
4. Restore after a delay, **guarded by that change count** — if the user copied something in the meantime, leave it alone:
```swift
guard pasteboard.changeCount == expectedChangeCount else {
    Log.textInsertion.debug("Clipboard changed since paste — skipping restore to preserve user's copy")
    return
}
pasteboard.clearContents()
for (type, data) in contents { pasteboard.setData(data, forType: type) }
```
5. If the original was empty, `clearContents()` and stop — do not let the transcription linger.

wispr uses a **2-second** restore delay, cancelling and rescheduling on each new insertion. `[SOURCE]`

**The timing hazard is real:** there is a race between the pasteboard write landing and the target app servicing the ⌘V, and separately between the paste landing and any auto-Enter you send. Claude Code itself has an open bug from exactly this shape — *"[BUG] Paste race condition: Enter sends message before clipboard content is inserted"* `[SOURCE]` <https://github.com/anthropics/claude-code/issues/28137>. If you implement "auto-send Enter for chat apps", it must wait on evidence the paste landed, not on a fixed sleep.

**One more macOS-15.4+ landmine, and it points the wrong way for you.** `NSPasteboard.accessBehavior` and a **"Paste from Other Apps"** privacy pane make *programmatic reads* of the general pasteboard prompt the user. `[SOURCE]` <https://developer.apple.com/documentation/appkit/nspasteboard/accessbehavior-swift.enum>, <https://mjtsai.com/blog/2025/05/12/pasteboard-privacy-preview-in-macos-15-4/>. `[RUN-VERIFIED 15.1]` the pane's anchor already exists on this machine (`Privacy_Pasteboard`, `PrivacyPasteboardService` in `TCCServiceList.plist`), though `NSPasteboard.accessBehavior` is **not** in the 15.2 SDK headers — it postdates them. As of Sept 2025 the enforcement was reported still off-by-default in macOS 26 unless you opt in with `defaults write <bundle-id> EnablePasteboardPrivacyDeveloperPreview -bool yes`. `[UNVERIFIED — Tahoe]`

> **This is the biggest forward risk in the whole injection design, and it is worth stating plainly: writing the pasteboard is unaffected. Reading it to save-and-restore the user's clipboard is exactly the operation Apple is adding a prompt to.** Mitigation: use the new `detect…` methods (which inspect types without reading, and do not prompt) to decide whether a restore is even needed, and ship a preference for "don't touch my clipboard" that skips save/restore entirely. Test this on 26.x with the developer-preview default turned **on** — that is the future, and you want to find out now, not when Apple flips the switch.

### 3.3 (c) `CGEvent.keyboardSetUnicodeString` — character injection

**Verdict: keep as a narrow fallback, never as the primary.**

Works by creating a keyboard event and overriding its Unicode payload, so it can type arbitrary text with no clipboard involvement — which is genuinely attractive for privacy. But:

- **Some frameworks ignore it.** Apple's own header notes that application frameworks may ignore the Unicode string and re-translate from the virtual keycode and modifier state instead. `[SOURCE]` <https://developer.apple.com/documentation/coregraphics/cgevent/1456028-keyboardsetunicodestring>
- **It is slow and needs chunking.** Practical implementations send ~20 characters per event with 2–4 ms between chunks. For 500 characters that is ≥25 chunks and ~50–100 ms *minimum*, versus one paste. `[UNVERIFIED — secondary]`
- **It drops text in modern terminals.** Silently, when the kitty keyboard protocol is active. `[UNVERIFIED — secondary]` <https://github.com/stablyai/orca/issues/6513>
- Dead-key and input-source state can corrupt it.

Its one real use: the user who turns off clipboard access, or a target app where paste is genuinely blocked. Ship it behind a per-app override, with a visible "slower, may drop characters" label.

### 3.4 Secure Input — the failure mode that makes you look broken

**What it is.** `EnableSecureEventInput` (Carbon, since 10.3) protects a password field by stopping keyboard events from reaching *any* intercept process. Apple TN2150, verbatim `[SOURCE]` <https://developer.apple.com/library/archive/technotes/tn2150/_index.html>:

> *"The fix for this problem is to stop passing keyboard events to any intercept process whenever any process has enabled secure event input, whether that process is in the foreground or background."*

**It is system-wide, not focus-scoped.** A backgrounded password manager that leaks a reference starves every event tap on the machine. 1Password and KeePassXC both have long-running bug reports for exactly this. `[SOURCE]` <https://www.1password.community/1password-at-work-58/secure-input-blocking-other-apps-event-taps-25015>, <https://github.com/keepassxreboot/keepassxc/issues/11906>

**What breaks in mumbler, precisely — and this is the finding that vindicates the whole hotkey recommendation:**

**Secure Input filters `keyDown`/`keyUp` but `flagsChanged` KEEPS FLOWING.** So a **modifier-only push-to-talk hotkey survives Secure Input, while a letter-key hotkey goes dark.** Two independent sources, neither derived from the other:

- `cjpais/Handy` ships a whole module for this, and its header comment states it outright `[SOURCE]` <https://github.com/cjpais/Handy/blob/main/src-tauri/src/secure_input.rs>:
> *"When any process enables secure event input (password fields, Terminal's 'Secure Keyboard Entry', a stuck `loginwindow`), CGEventTaps stop receiving KeyDown/KeyUp events **while FlagsChanged still flows**. The handy-keys implementation is tap-based, so keyed shortcuts (e.g. Option+Space) die silently while **modifier-only shortcuts keep working**."*
Handy's mitigation is elegant: while secure input is sustained, it *shadow-registers* the vulnerable **keyed** bindings through the Carbon path, which secure input does not affect. Modifier-only bindings need no fallback.
- An instrumented tap-ordering experiment in `lwouis/alt-tab-macos` reports the same: *"SecureInput continues to filter `.keyDown` (passwords aren't observed) while leaving `.flagsChanged` visible."* `[SOURCE]` <https://github.com/lwouis/alt-tab-macos/blob/master/src/experimentations/EscapeAndGameOverlay.md>
- Wispr Flow's own support docs describe the same user-visible split: *"On Mac, Flow's keyboard shortcuts are blocked system-wide while another app holds Secure Keyboard Entry. **Hold-to-talk continues to work.**"* `[SOURCE]`

> **This is a second, independent reason to bind a bare right-side modifier rather than a chord.** It is not just ergonomics — it is the difference between an app that works while a password field is focused and one that mysteriously dies.

The rest of the picture:
- **Carbon `RegisterEventHotKey` keeps working** — it is not an intercept process. Keep it as the fallback for keyed bindings, exactly as Handy does.
- **Injection is a separate question.** Whether a posted ⌘V still lands in a secure field is *not* what TN2150 addresses; TN2150 is about interception. `[UNVERIFIED — I found no authoritative statement, and could not test it without posting events, which the safety constraint forbids.]` The safest policy is `slovo`'s: **fail closed**. It checks `IsSecureEventInputEnabled()` three times — before touching the pasteboard at all, again after clearing it, and again immediately before posting ⌘V — so the transcript never transits the clipboard while a secure field is focused `[SOURCE]` <https://github.com/Akurganow/slovo>. Copy that ordering; a dictated password sitting on the general pasteboard is the worst bug this app could ship.

**Detection — two APIs, and the second is the one you actually want.**

`IsSecureEventInputEnabled()` gives you the boolean. `[RUN-VERIFIED 15.1]` — it links from Swift via `import Carbon.HIToolbox` (it is exported from HIToolbox but is **not** in the SDK headers; it resolves through the `.tbd`), and returned `false` on this machine.

But a boolean is a bad error message. To name the culprit, read the IORegistry root's `IOConsoleUsers` array and look for `kCGSSessionSecureInputPID`. The canonical implementation is espanso's, itself derived from MagicKeys `[SOURCE]` <https://github.com/espanso/espanso/blob/dev/espanso-mac-utils/src/native.mm>:

```objc
// Taken (with a few modifications) from the MagicKeys project: https://github.com/zsszatmari/MagicKeys
int32_t mac_utils_get_secure_input_process(int64_t *pid) {
  if ((rootService = IORegistryGetRootEntry(kIOMasterPortDefault)) != 0) {
    if ((consoleUsersArray = (NSArray *)IORegistryEntryCreateCFProperty(
           (io_registry_entry_t)rootService, CFSTR("IOConsoleUsers"), kCFAllocatorDefault, 0)) != nil) {
      for (NSDictionary *consoleUserDict in consoleUsersArray) {
        NSNumber *secureInputPID;
        if ((secureInputPID = [consoleUserDict objectForKey:@"kCGSSessionSecureInputPID"]) != nil) {
          *pid = ((UInt64) [secureInputPID intValue]); result = 1; break;
        }
      }
    }
  }
  return result;
}
```

`[RUN-VERIFIED 15.1]` — I ported that to Swift and ran it read-only. It works, and it agrees with `IsSecureEventInputEnabled()`:

```swift
import Foundation
import IOKit

func secureInputHolderPID() -> pid_t? {
    let root = IORegistryGetRootEntry(kIOMainPortDefault)
    guard root != 0 else { return nil }
    defer { IOObjectRelease(root) }
    guard let cf = IORegistryEntryCreateCFProperty(root, "IOConsoleUsers" as CFString, kCFAllocatorDefault, 0),
          let users = cf.takeRetainedValue() as? [[String: Any]] else { return nil }
    for u in users {
        if let p = u["kCGSSessionSecureInputPID"] as? Int32 { return p }
    }
    return nil
}
// then: NSRunningApplication(processIdentifier: pid)?.localizedName
```

Output on this machine:

```
IOConsoleUsers entries: 1
  keys: ["CGSSessionUniqueSessionUUID", "kCGSSessionAuditIDKey", "kCGSSessionGroupIDKey",
         "kCGSSessionIDKey", "kCGSSessionLoginwindowSafeLogin", "kCGSSessionOnConsoleKey",
         "kCGSSessionSystemSafeBoot", "kCGSSessionUserIDKey", "kCGSSessionUserNameKey",
         "kCGSessionLoginDoneKey", "kCGSessionLongUserNameKey", "kSCSecuritySessionID"]
No kCGSSessionSecureInputPID key present -> secure input OFF
```

Note the key is **absent** when secure input is off — you cannot read it as `0`, you must check for absence. Note also `kIOMainPortDefault` (macOS 12+) rather than the deprecated `kIOMasterPortDefault` espanso still uses. **`CGSessionCopyCurrentDictionary()` is NOT the right call** — `[RUN-VERIFIED 15.1]` I tried it, and it returns a session dictionary with 11 keys that never contains `kCGSSessionSecureInputPID`. Several blog posts recommend it; they are wrong. Use `IOConsoleUsers`.

**Known caveat on the PID (Tenet 1 — the check has a blind spot):** the reported PID is wrong when a *background* app enables secure input. Radar: *"kCGSSessionSecureInputPID will report the PID of the application which is active at the time the inactive application calls EnableSecureEventInput()."* `[SOURCE]` <https://github.com/lionheart/openradar-mirror/issues/21098>. So show the name as a hint — *"Secure Input appears to be held by Foo"* — never as a certainty.

**Design requirement:** poll `IsSecureEventInputEnabled()` (cheap) while idle, and when it flips true, change the menu bar icon and say so. A dictation app that silently does nothing is unrecoverable for the user; one that says *"Secure Input is on (possibly 1Password) — the hotkey is blocked"* is a support ticket that never gets filed.

### 3.5 App-by-app reliability, honestly

| Target | AX set-text | **Pasteboard + ⌘V** | Unicode string |
|---|---|---|---|
| Native AppKit (Notes, Mail, TextEdit) | mostly works | ✅ | ✅ |
| Pages / Google Docs | ❌ silent no-op | ✅ | ⚠️ slow |
| VS Code / Slack / Discord / Obsidian (Electron) | ❌ needs `AXManualAccessibility`, often unsupported; no cursor selection | ✅ | ✅ |
| Chrome / Safari web text fields | ⚠️ unreliable | ✅ | ✅ |
| Terminal.app / iTerm2 | ❌ | ✅ (watch trailing newlines) | ⚠️ drops under kitty protocol |
| Any app, Secure Input on | ❌ | ⚠️ unverified — assume ❌ | ⚠️ assume ❌ |
| Under App Sandbox | ❌ prohibited | ✅ (PostEvent privilege) | ✅ |

### 3.6 DECISION TABLE — injection

| | AXUIElement set-text | **Pasteboard + ⌘V** | `keyboardSetUnicodeString` |
|---|---|---|---|
| Works in Electron | ❌ | ✅ | ✅ |
| Works in Terminal | ❌ | ✅ | ⚠️ |
| Silent-failure risk | **high** | low | medium |
| 500 chars | n/a | **~instant, O(1)** | ~50–100 ms, O(n) |
| Touches clipboard | no | **yes** — restore required | no |
| App Sandbox legal | ❌ | ✅ | ✅ |
| Permission | Accessibility | Accessibility (PostEvent) | Accessibility (PostEvent) |
| Future TCC risk | — | pasteboard-read prompts (15.4+) | — |

**PICK: NSPasteboard + synthetic ⌘V, with the full change-count-guarded restore from §3.2, and `keyboardSetUnicodeString` as an opt-in fallback.**

**Reason:** it is the only method that is O(1) in text length, works in Electron and terminals, and survives the App Sandbox. Its two weaknesses are both manageable: clipboard clobbering is solved by the guarded-restore algorithm, and the coming pasteboard-read prompt is avoidable by making restore optional. AX set-text is disqualified not by being slower but by *failing silently* — the worst property an injection path can have, because you cannot even tell the user it went wrong.

### 3.7 Two implementation traps the naive version gets wrong

**Trap 1 — hard-coding keycode `0x09` for V breaks on real keyboard layouts.** Three of the five open-source apps I surveyed independently discovered this. On Dvorak-QWERTY⌘ and many non-Latin layouts, Cmd-held shortcuts remap to their ANSI equivalents — but *standard* Dvorak does not, so there is no single rule. The most correct fix is Handy's: scan keycodes 0…128 through `UCKeyTranslate` **with the Command modifier state applied**, and fall back to ANSI 9. `[SOURCE]` <https://github.com/cjpais/Handy/blob/main/src-tauri/src/input.rs>:
> *"Including Command is important: non-Latin layouts commonly map Cmd shortcuts to their ANSI equivalents, while standard Dvorak does not."*

VoiceInk solves the same problem with an AppleScript escape hatch, and its comment names the exact failure `[SOURCE]` <https://github.com/Beingpax/VoiceInk/blob/main/VoiceInk/Paste/CursorPaster.swift>:
```swift
// "X – QWERTY ⌘" layouts remap to QWERTY when Command is held, so keystroke "v" resolves
// the wrong key code. key code 9 (physical V) bypasses layout translation for those layouts.
```
OpenSuperWhisper uses a hard-coded layout-ID allowlist (weakest). `slovo` hard-codes `kVK_ANSI_V` with no handling at all. **Do the `UCKeyTranslate`-with-Command scan.**

**Trap 2 — a fixed restore delay is a guess; the pasteboard can tell you when it was actually read.** Every simple implementation sleeps N milliseconds and hopes (wispr: 2 s, OpenSuperWhisper: 1.5 s, slovo: 300 ms, VoiceInk: 250 ms minimum). Handy replaces the guess with an **OS read receipt**: instead of writing data, it `declareTypes:owner:` with a *promise*, so `pasteboard:provideDataForType:` fires on its provider object the instant a consumer actually reads the clipboard. `[SOURCE]` <https://github.com/cjpais/Handy/blob/main/src-tauri/src/paste_tx/macos.rs>:

```rust
// NSPasteboardOwner informal protocol: the pasteboard is asking for the
// promised data — our receipt that a consumer read the clipboard.
#[unsafe(method(pasteboard:provideDataForType:))]
fn pasteboard_provide_data_for_type(&self, pasteboard: &NSPasteboard, data_type: &NSString) {
    let is_text = unsafe { data_type.isEqualToString(NSPasteboardTypeString) };
    if is_text {
        if let Ok(mut state) = self.ivars().state.lock() { state.record_receipt(Instant::now()); }
    }
    ...
}
#[unsafe(method(pasteboardChangedOwner:))]
fn pasteboard_changed_owner(&self, _pasteboard: &NSPasteboard) {
    if let Ok(mut st) = self.ivars().state.lock() { st.ownership_lost = true; }
}
```
It then restores after a **200 ms quiet period following the last receipt**, with an **8 s** hard cap and a **500 ms** failed-injection timeout — and only if `!ownership_lost && changeCount == expected`. **This is the correct design.** It also directly solves the auto-Enter race from §3.2: you know the paste landed because someone read the clipboard.

**Also copy: the transient markers.** VoiceInk, Handy and slovo all set `org.nspasteboard.TransientType`, `org.nspasteboard.ConcealedType` and `org.nspasteboard.AutoGeneratedType` on the staged item, so third-party clipboard managers do not archive the user's dictated text into a searchable history. OpenSuperWhisper does not, and that is a privacy bug.

### 3.8 What the five open-source dictation apps actually ship

| App | Injection | Restore strategy | Guard | Conceal markers |
|---|---|---|---|---|
| `sebsto/wispr` | pasteboard + ⌘V (`.cghidEventTap`) | 2 s, cancel/reschedule | `changeCount` | ❌ |
| `Beingpax/VoiceInk` | pasteboard + ⌘V (`.cghidEventTap`, 10 ms between edges) **or** AppleScript | ≥250 ms, user-tunable, item-by-item archive | text match **+ custom UTI session ID** | ✅ |
| `cjpais/Handy` | pasteboard promise + ⌘V | **read receipt**, 200 ms quiet, 8 s cap | `changeCount` + ownership | ✅ |
| `Starmel/OpenSuperWhisper` | pasteboard + ⌘V (`.cghidEventTap`) | 1.5 s | `changeCount` | ❌ |
| `Akurganow/slovo` | pasteboard + ⌘V (`.cgSessionEventTap`) | 300 ms, `defer` on **all** exit paths | none (deliberate) | ✅ |

**Nobody uses `AXUIElement` to write text.** Five for five. That is as strong a signal as this kind of survey produces.

---

## 4. Permissions and TCC

### 4.1 The exact set mumbler needs

| Capability | TCC service | Check API | Prompts? |
|---|---|---|---|
| Record audio | `kTCCServiceMicrophone` | `AVCaptureDevice.authorizationStatus(for: .audio)` | ✅ `requestAccess(for:)` prompts |
| Hotkey event tap | `kTCCServiceAccessibility` | `AXIsProcessTrusted()` | ⚠️ `AXIsProcessTrustedWithOptions` with `kAXTrustedCheckOptionPrompt` shows a *nag*, not a grant dialog |
| Post ⌘V | `kTCCServicePostEvent` | `CGPreflightPostEventAccess()` / `CGRequestPostEventAccess()` | ✅ |
| *(not needed)* listen-only tap | `kTCCServiceListenEvent` | `CGPreflightListenEventAccess()` / `IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)` | ✅ |
| *(not needed)* Apple ASR | `kTCCServiceSpeechRecognition` | `SFSpeechRecognizer.authorizationStatus()` | ✅ |

**You need exactly two visible grants: Microphone and Accessibility.** Skip Speech Recognition entirely if you run Whisper/Parakeet locally — it gates Apple's `SFSpeechRecognizer`, not your own model. Skip Input Monitoring — see §1.2; it buys nothing and costs an admin authentication.

`[SDK-VERIFIED 15.2]`, `IOKit.framework/Headers/hidsystem/IOHIDLib.h`, verbatim:

```c
typedef enum { kIOHIDRequestTypePostEvent, kIOHIDRequestTypeListenEvent } IOHIDRequestType;
typedef enum { kIOHIDAccessTypeGranted, kIOHIDAccessTypeDenied, kIOHIDAccessTypeUnknown } IOHIDAccessType;
IOHIDAccessType IOHIDCheckAccess(IOHIDRequestType requestType) __OSX_AVAILABLE(10.15);
```
The header also notes the implicit-prompt behavior, which is worth knowing so you can avoid it: *"If you do not request access through the IOHIDRequestAccess call, the request will be made on the process's behalf in IOHIDManagerOpen/IOHIDDeviceOpen calls."*

**Always check without prompting first.** For Accessibility use the bare `AXIsProcessTrusted()`, or explicitly pass `false`, exactly as espanso does `[SOURCE]` <https://github.com/espanso/espanso/blob/dev/espanso-mac-utils/src/native.mm>:

```objc
NSDictionary* opts = @{(__bridge id)kAXTrustedCheckOptionPrompt: @NO};
return AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)opts);
```

### 4.2 The TCC services live in TWO databases — and yours are in the root-owned one

`[RUN-VERIFIED 15.1]` — read-only `sqlite3` against both databases on this machine.

User database, `~/Library/Application Support/com.apple.TCC/TCC.db` — 23 services, including `kTCCServiceMicrophone` (31 rows). **Contains no Accessibility, ListenEvent or PostEvent rows at all.**

System database, `/Library/Application Support/com.apple.TCC/TCC.db` (`-rw-r--r-- root:wheel`, world-readable):

```
kTCCServiceAccessibility|36
kTCCServiceDeveloperTool|1
kTCCServiceListenEvent|3
kTCCServicePostEvent|6
kTCCServiceScreenCapture|24
kTCCServiceSystemPolicyAllFiles|63
```

Two consequences, both empirical rather than inferred:

1. **`kTCCServicePostEvent` is a real, separately-tracked service with its own rows.** The "PostEvent and Accessibility are the same thing" folklore is wrong at the database level even though they share one UI toggle (§1.2). An app can hold one and not the other.
2. **Microphone resets are per-user; Accessibility/PostEvent resets need `sudo`.** `tccutil reset Microphone <id>` works as you; `sudo tccutil reset Accessibility <id>` and `sudo tccutil reset PostEvent <id>` do not.

### 4.3 Deep links to the right System Settings pane

`[RUN-VERIFIED 15.1]` — rather than trust a blog list, I read the anchors out of the shipping pane. The privacy pane's bundle identifier is `com.apple.settings.PrivacySecurity.extension`, and its resources advertise these anchors (among 28):

```
Privacy_Accessibility   Privacy_ListenEvent    Privacy_Microphone
Privacy_SpeechRecognition   Privacy_ScreenCapture   Privacy_Pasteboard
```

`[RUN-VERIFIED 15.1]` — `System Settings.app` registers exactly one URL scheme:
```json
[{"CFBundleTypeRole":"Viewer","LSIsAppleDefaultForScheme":true,
  "CFBundleURLSchemes":["x-apple.systempreferences"],"CFBundleURLName":"System Preferences URL"}]
```

The URLs to use:

```
x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility
x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone
x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent
```

**Do these still work on Tahoe?** `[UNVERIFIED — Tahoe]`, but the evidence is better than a guess: `sebsto/wispr` declares `platforms: [.macOS(.v26)]` in `Package.swift` and ships the **legacy `com.apple.preference.security`** form `[SOURCE]`:

```swift
func openAccessibilitySettings() {
    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
}
func openMicrophoneSettings() {
    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
}
```
— <https://github.com/sebsto/wispr/blob/main/Sources/WisprApp/Services/PermissionManager.swift>

A shipping macOS-26-targeted app using the legacy host is strong circumstantial evidence the alias still resolves. Some sources claim Tahoe wants the new `com.apple.settings.PrivacySecurity.extension` host instead. `[UNVERIFIED]`

> **Ship both, in order.** `NSWorkspace.shared.open(_:)` returns `Bool`. Try the modern host, fall back to the legacy host, and fall back again to plain `x-apple.systempreferences:` (which at worst opens System Settings' front page). Never leave the user with a dead button — that is Tenet 8 in UI form. **First-boot test on Tahoe: click each of the three buttons and confirm the correct pane opens, not the front page.**

### 4.4 The stale-code-signature problem — proven on this machine, not theorised

This is the question with the most folklore and the least evidence online, so I went to the source of truth: the `csreq` blob in the system TCC database, decoded with `csreq -t`.

`[RUN-VERIFIED 15.1]` — a **Developer ID**-signed app's grant (real row, `kTCCServicePostEvent`):

```
client=com.googlecode.iterm2  auth=2
  csreq: anchor apple generic and identifier "com.googlecode.iterm2"
         and (certificate leaf[field.1.2.840.113635.100.6.1.9] /* exists */
              or certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */
                 and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */
                 and certificate leaf[subject.OU] = H7V7XYVQ7D)
```

`[RUN-VERIFIED 15.1]` — an **ad-hoc**-signed app's grant (three real rows under `kTCCServiceAccessibility`, two of which are this machine's own prior dev spikes):

```
client=com.pg.amm                     auth=2  csreq: cdhash H"67fbd80629081eb31b5247863dd3eeaa076cb804"
client=dev.ecn.spike.axprobe          auth=0  csreq: cdhash H"3a53000ccc4a6364282bb5b1eeb5f8f75a67159a"
client=dev.ecn.apps.axprobe-audit     auth=0  csreq: cdhash H"0ee9d00e090cbcd27525f3195ad14895241acf17"
```

**That is the entire answer, and it is not a matter of opinion.** TCC stores a *designated requirement*, and its shape depends on how you signed:

- **Signed with a named identity** (Developer ID **or a self-signed cert in your keychain**) → the requirement pins **`identifier` + certificate/team**. The cdhash is irrelevant. **Rebuild as often as you like; the grant survives.**
- **Ad-hoc signed (`codesign -s -`) or unsigned** → there is no certificate to pin, so TCC falls back to pinning the **`cdhash`** — the hash of the code directory. **Every recompile changes the cdhash, and the grant is instantly dead.** Worse, the stale row *stays in the database* with the old hash, so System Settings shows your app with the toggle ON while it is functionally denied — the exact "toggle looks on but nothing works" symptom.

**Correct dev workflow for mumbler:**

1. Create a **self-signed code-signing certificate once**, and sign every dev build with it. It does not need to be an Apple certificate — it only needs to be a *stable named identity*, because that is what changes the csreq from a cdhash pin to a certificate pin. `[SOURCE]` <https://evoleinik.com/posts/macos-dev-signing-preserve-permissions/>:
```bash
openssl req -x509 -newkey rsa:2048 -days 3650 -keyout dev.key -out dev.crt -nodes \
  -subj "/CN=Mumbler Dev" \
  -addext "keyUsage=critical,digitalSignature" -addext "extendedKeyUsage=codeSigning"
openssl pkcs12 -export -legacy -in dev.crt -inkey dev.key -out dev.p12 -password pass:dev
security import dev.p12 -k ~/Library/Keychains/login.keychain-db -P dev -T /usr/bin/codesign
# then trust it for Code Signing in Keychain Access, and:
codesign --force --sign "Mumbler Dev" Mumbler.app
```
(The `-legacy` flag is required — modern OpenSSL PKCS#12 output is rejected by the macOS keychain.)
2. **Keep the bundle identifier frozen** from day one. Changing `CFBundleIdentifier` is as destructive as changing the signature — it is the other half of the primary key.
3. When a grant does go stale, a UI toggle-off/on is **not** sufficient — it may not replace the stale csreq row. Reset and re-grant:
```bash
sudo tccutil reset Accessibility dev.ecn.mumbler
sudo tccutil reset PostEvent     dev.ecn.mumbler
tccutil      reset Microphone    dev.ecn.mumbler
```
Then **fully quit and relaunch** the app before re-granting. `[UNVERIFIED — secondary, but consistent with the csreq mechanism above]`
4. **Launch the binary directly, not via `open`/Finder, during development.** There is a documented silent-disable race where a re-signed app launched through Launch Services installs an event tap that receives nothing, while the same binary launched directly works `[SOURCE]` <https://danielraffel.me/til/2026/02/19/cgevent-taps-and-code-signing-the-silent-disable-race/>:
```bash
nohup /Applications/Mumbler.app/Contents/MacOS/Mumbler >> ~/Library/Logs/Mumbler.log 2>&1 & disown
```
5. **Never ship without also handling revocation at runtime.** Re-check `AXIsProcessTrusted()` and `CGPreflightPostEventAccess()` on `NSApplication.didBecomeActive` and on a timer; the user can revoke at any time, and macOS updates have been observed dropping Input Monitoring grants spontaneously `[SOURCE]` <https://github.com/espanso/espanso/issues/2031>.

**What this check could not see:** I read grants that already exist on this machine. I did **not** create a new ad-hoc-signed app, grant it, rebuild it, and watch the grant break — that would have required posting events and taking focus. The cdhash-vs-certificate mechanism is proven from the stored requirements; the *consequence* ("rebuild breaks it") is a deduction from how cdhash works, corroborated by the two `auth=0` dev-spike rows already sitting stale in this very database.

### 4.5 A note on the sandbox

If you sandbox (required for the App Store, optional for Developer ID + notarization), `AXUIElement` control of other apps is prohibited outright — see §3.1. `CGEvent` posting still works via the PostEvent privilege. `[SOURCE]` `sebsto/wispr` `TextInsertionService.swift`. There is also a reported interaction where `RegisterEventHotKey` behaved differently sandboxed vs not on macOS 15 `[SOURCE]` <https://github.com/feedback-assistant/reports/issues/552>. **Decide sandbox/no-sandbox before writing the injection layer, not after** — it changes which options exist.

---

## 5. Audio capture

### 5.1 `installTap` has a documented 100 ms floor — and the web docs hide it

This is the highest-leverage finding in the audio section, and it is in a header that almost nobody reads.

`[SDK-VERIFIED 15.2]`, `AVFAudio.framework/Headers/AVAudioNode.h:85-86`, verbatim:

```objc
/*! @method installTapOnBus:bufferSize:format:block:
	@param bufferSize
		the requested size of the incoming buffers in sample frames. Supported range is [100, 400] ms.
```

**That sentence does not appear on developer.apple.com.** The public page says only the much weaker *"The size of the incoming buffers. The implementation may choose another size."* `[SOURCE]` <https://developer.apple.com/documentation/avfaudio/avaudionode/installtap(onbus:buffersize:format:block:)>

The arithmetic explains every field report:
- 100 ms @ 48 kHz = **4800 frames** — matching <https://developer.apple.com/forums/thread/797033> (*"any buffer size under 4800 is just ignored"*)
- 100 ms @ 44.1 kHz = **4410 frames** — matching <https://github.com/AudioKit/AudioKit/issues/1990> (requested 32, received 4410)

WhisperKit ships the same knowledge as a code comment `[SOURCE]` <https://github.com/argmaxinc/WhisperKit/blob/main/Sources/WhisperKit/Core/Audio/AudioProcessor.swift>:
```swift
let bufferSize = AVAudioFrameCount(minBufferLength) // 100ms - 400ms supported
```

> **`installTap` is architecturally wrong for low-latency dictation.** A 100 ms floor is a 100 ms quantum on every single buffer, and `sebsto/wispr` requesting `bufferSize: 1024` is getting 4800 whether it knows it or not.

**Two escapes, both real:**

**(a) `AVAudioSinkNode`** — the low-latency path *inside* AVAudioEngine. `[SDK-VERIFIED 15.2]`, `API_AVAILABLE(macos(10.15), ios(13.0))`:
> *"AVAudioSinkNode wraps a client provided block to receive input audio on the audio IO thread… restricted to be used in the input chain and does not support format conversion… does not have an output bus and therefore it does not support tapping."*
> *"The block will be called on the realtime thread and it is the client's responsibility to handle it in a thread-safe manner and to not make any blocking calls."*

No 100 ms floor. You get the hardware IO buffer. **Use this.** The cost is real-time discipline: no locks, no allocation, no logging in that block — hand off through a lock-free ring buffer.

**(b) Set the hardware buffer directly** via CoreAudio — the macOS analogue of iOS's `setPreferredIOBufferDuration`, which does not exist here:
```
kAudioDevicePropertyBufferFrameSize      = 'fsiz'
kAudioDevicePropertyBufferFrameSizeRange = 'fsz#'
```

**`AVAudioSession` does not exist on macOS.** Its availability list is iOS/iPadOS/Mac Catalyst/tvOS/visionOS/watchOS — **macOS absent** `[SOURCE]` <https://developer.apple.com/documentation/avfaudio/avaudiosession>. The macOS SDK still *ships* `AVAudioSession.h` for Catalyst, so a naive header grep misleads. Categories, `.mixWithOthers`, `setPreferredIOBufferDuration` — none of it applies. CoreAudio device properties replace all of it.

### 5.2 Input format — why the crash happens, and the fix

`inputFormat(forBus:0)` is the **hardware** format; `outputFormat(forBus:0)` is the node's client-side output format. `[SDK-VERIFIED 15.2]`, `AVAudioIONode.h`:
> *"When rendering from an audio device, the input node does not support format conversion. Hence the format of the output scope must be same as that of the input, as well as the formats for all the nodes connected in the input node chain."*

That is exactly why `required condition is false: format.sampleRate == hwFormat.sampleRate` fires when you hand `installTap` a synthesised 16 kHz format. **Pass `nil` or the node's own format; never one you invented.**

WhisperKit's production workaround rebuilds the node format from the *hardware* rate rather than trusting either accessor `[SOURCE]`:
```swift
let hardwareSampleRate = audioEngine.inputNode.inputFormat(forBus: 0).sampleRate
let inputFormat = inputNode.outputFormat(forBus: 0)
guard let nodeFormat = AVAudioFormat(commonFormat: inputFormat.commonFormat,
                                     sampleRate: hardwareSampleRate,
                                     channels: inputFormat.channelCount,
                                     interleaved: inputFormat.isInterleaved) else { ... }
```

**Three failure classes, needing three different handlers** — most implementations only handle the first:
1. **Swift `throws`** from `startAndReturnError:` — catchable.
2. **Objective-C `NSException`** — the `required condition is false` family. **Not catchable from Swift; it terminates your app.** The only defence is validating formats *before* you call.
3. **Silent success with no buffers** — the worst, because nothing errors. See §5.4.

### 5.3 Converting to 16 kHz mono Float32

`AVAudioConverter`, with the capacity-rounding pitfall most people hit `[SOURCE]` <https://github.com/argmaxinc/WhisperKit/blob/main/Sources/WhisperKit/Core/Audio/AudioProcessor.swift>:

```swift
var capacity = converter.outputFormat.sampleRate * Double(buffer.frameLength) / converter.inputFormat.sampleRate
if capacity.truncatingRemainder(dividingBy: 1) != 0 {
    capacity = max(1, capacity.rounded(.toNearestOrEven))
}
guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: converter.outputFormat,
                                             frameCapacity: AVAudioFrameCount(capacity)) else { throw ... }
let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
    if buffer.frameLength == 0 { outStatus.pointee = .endOfStream; return nil }
    outStatus.pointee = .haveData
    return buffer
}
let status = converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)
```

`[SDK-VERIFIED 15.2]`, `AVAudioConverter.h` — the priming knob matters for live capture:
> *"AVAudioConverterPrimeMethod_None is useful in a real-time application processing live input."*

Default is `_Normal`. **Set `_None` for push-to-talk.** And **recreate the converter whenever the hardware format changes** — it binds both formats at construction, so a stale converter after a device switch is silently wrong. `AVAudioConverter` is **not documented as thread-safe** `[UNVERIFIED]`; keep one per capture thread.

### 5.4 Device changes

`[SOURCE]` <https://developer.apple.com/documentation/avfaudio/avaudioengineconfigurationchangenotification>, verbatim:
> *"When the audio engine's I/O unit observes a change to the audio input or output hardware's **channel count or sample rate**, the audio engine **stops, uninitializes itself**, and issues this notification. The nodes remain in an attached and connected state with the previously set formats. The app must reestablish connections if the connection formats need to change."*
> *"**Don't deallocate the engine from within the client's notification handler.** The callback happens on an internal dispatch queue and can deadlock while trying to tear down the engine synchronously."*

**Two traps:**
1. **The trigger is channel count or sample rate — NOT "the default device changed."** Swapping between two 48 kHz stereo devices may fire nothing. **You need a CoreAudio listener as well; the notification alone is not sufficient device-change detection.** This is the most commonly missed point in every tutorial.
2. It fires on an internal queue — hop to your own serial audio queue before restarting.

`[SDK-VERIFIED 15.2]` — the CoreAudio selectors, and the `Master`→`Main` rename:
```
kAudioHardwarePropertyDefaultInputDevice     = 'dIn '
kAudioDevicePropertyStreamConfiguration      = 'slay'
kAudioDevicePropertyDeviceIsRunningSomewhere = 'gone'
kAudioObjectPropertyElementMain = 0,
kAudioObjectPropertyElementMaster API_DEPRECATED_WITH_REPLACEMENT("kAudioObjectPropertyElementMain",
    macos(10.0, 12.0), ...) = kAudioObjectPropertyElementMain
```
Same value, so it is purely a compile-time concern — but use `...ElementMain`.

**`AudioObjectRemovePropertyListenerBlock` matches on `(block, queue)`** — store the pair together or you cannot unregister `[SOURCE]` <https://github.com/sbooth/CAAudioHardware/blob/main/Sources/CAAudioHardware/AudioObject.swift>.

**Pinning a specific input device** without changing the system default `[SOURCE]` WhisperKit:
```swift
func assignAudioInput(inputNode: AVAudioInputNode, inputDeviceID: AudioDeviceID) {
    guard let audioUnit = inputNode.audioUnit else { return }
    var inputDeviceID = inputDeviceID
    AudioUnitSetProperty(audioUnit, kAudioOutputUnitProperty_CurrentDevice,
                         kAudioUnitScope_Global, 0,
                         &inputDeviceID, UInt32(MemoryLayout<AudioDeviceID>.size))
}
```
**Ordering matters:** call this immediately after touching `engine.inputNode` and *before* reading `inputFormat(forBus:0)`. Setting the device after caching the format is a classic route to the sample-rate assertion crash.

### 5.5 Mic contention — macOS shares by default

`[SDK-VERIFIED 15.2]`, `AudioHardware.h:932-944`, verbatim:
> *"`kAudioDevicePropertyHogMode` — A pid_t indicating the process that currently owns exclusive access to the AudioDevice or a value of **-1 indicating that the device is currently available to all processes**. If the AudioDevice is in a non-mixable mode, the HAL will automatically take hog mode on behalf of the first process to start an IOProc."*

So unlike WASAPI exclusive mode, **multiple apps read the mic concurrently by default**. Reading `'oink'` tells you the owning pid when someone has hogged it — so you can name the blocker instead of showing a bare `OSStatus`.

The error you will actually hit is **`2003329396`** = `0x77686174` = `'what'` = `kAudioHardwareUnspecifiedError`, reported for `AVAudioEngine` failing to start during an active FaceTime call `[SOURCE]` <https://developer.apple.com/forums/thread/814269>. It is generic. Treat it as *contention / route in flux*, retry with backoff, do not parse meaning from it.

**The documented escape hatch for contention is `AVCaptureSession` + `AVCaptureAudioDataOutput`** — two independent reports say it fires reliably where `installTap` silently does not (Bluetooth devices, and during FaceTime). Cost: you get `CMSampleBuffer`, not `AVAudioPCMBuffer`. Worth keeping as a fallback path.

### 5.6 The orange dot — Apple documents this precisely, in a header

`[SDK-VERIFIED 15.2]`, `AVFAudio.framework/Headers/AVAudioEngine.h:465-469`, verbatim:

```objc
	Note that if the engine has at any point previously had its inputNode enabled and permission to
	record was granted, then any time the engine is running, the mic-in-use indicator will appear.

	For applications which may need to dynamically switch between output-only and input-output
	modes, it may be advantageous to use two engine instances.
```

Three things fall straight out of that sentence:

1. **The trigger is the engine RUNNING** — not tap installation, not the first buffer. So **a permanently warm `AVAudioEngine` means a permanently lit orange dot.** For a menu-bar dictation app that is a genuine trust problem: users read a persistent orange dot as "this app is always listening."
2. **It is sticky per engine instance.** Once an engine has *ever* had `inputNode` touched, *any* later run lights it — even a run that does no input. This is why Apple recommends two engine instances. **If you add start/stop chimes, play them on a separate engine or you will light the mic dot to play a sound.**
3. **`prepare()` alone does not light it** — `prepare()` is not "running." Its documented job is only to preallocate resources.

`[UNVERIFIED]` — the exact boundary (`AudioUnitInitialize` vs `AudioOutputUnitStart` vs first IOProc callback) is documented nowhere I found, and there is **no API to query indicator state**. The nearest queryable proxy is `kAudioDevicePropertyDeviceIsRunningSomewhere` (`'gone'`), which tells you the device is hot system-wide — related but not identical.

Corroboration from a shipping app: VoiceInk's architecture *depends* on prepare-without-indicator being true. It uses raw AUHAL (`kAudioUnitSubType_HALOutput`, **not** `AVAudioEngine`) and calls `prepare(deviceID:)` — *"Prepares AUHAL for the selected device without starting capture"* — at app init and on every device change, invoking `AudioUnitInitialize` but **not** `AudioOutputUnitStart`. If initialisation lit the dot, VoiceInk would show a permanent orange dot from launch, which would be a heavily-reported bug. `[SOURCE]` <https://github.com/Beingpax/VoiceInk/blob/main/VoiceInk/CoreAudioRecorder.swift>

### 5.7 Warm engine, start latency, and pre-roll

**No published measurement of `AVAudioEngine.start()` cold latency for *input* on macOS exists that I could find.** Playback-side figures circulate; reporting them as an input number would be wrong, so I am not doing it.

What does exist is real instrumentation in a shipping dictation app. `cjpais/Handy` measures the gap and documents it in source `[SOURCE]`:
> *"`Stream::play()` returning is not sufficient: some Bluetooth and USB devices take much longer to begin delivering callbacks."*
> *"silently dropped one buffer period of audio (**~10 ms built-in, up to ~100 ms on Bluetooth**) at every recording start."*

**The load-bearing lesson: the expensive, variable, device-dependent step is device-open plus first callback, not the API call.** That is exactly what a warm engine amortises.

**What the two leading open-source macOS dictation apps do — and an honest negative finding: neither implements a pre-roll ring buffer.**

- **Handy** keeps the stream open and `play()`ed permanently; `start()` merely flips a flag — and calls `processed_samples.clear()`, which is the proof that pre-keypress audio is **discarded**.
- **VoiceInk** keeps a *prepared* (not started) AUHAL, with a 96-slot lock-free ring used as a realtime→queue handoff, **not** as a history buffer.

**The app that does get it right is `whisper.cpp`**, and its default validates the ~200 ms instinct exactly `[SOURCE]` <https://github.com/ggml-org/whisper.cpp/blob/master/examples/common-sdl.cpp>:
```cpp
// keep last len_ms seconds of audio in a circular buffer
void audio_async::get(int ms, std::vector<float> & result) {
    size_t n_samples = (m_sample_rate * ms) / 1000;
    if (n_samples > m_audio_len) { n_samples = m_audio_len; }
    result.resize(n_samples);
    int s0 = m_audio_pos - n_samples;        // rewind from the write head
    if (s0 < 0) { s0 += m_audio.size(); }
    if (s0 + n_samples > m_audio.size()) {   // wrap
        const size_t n0 = m_audio.size() - s0;
        memcpy(result.data(), &m_audio[s0], n0 * sizeof(float));
        memcpy(&result[n0], &m_audio[0], (n_samples - n0) * sizeof(float));
    } else {
        memcpy(result.data(), &m_audio[s0], n_samples * sizeof(float));
    }
}
```
`stream.cpp` defaults `keep_ms = 200`. (Via SDL2, not CoreAudio — proof of the *pattern*, not of an AVFoundation implementation.)

**The design tension, stated plainly, because the two findings pull in opposite directions:**

| Mode | Start latency | Pre-roll possible | Orange dot |
|---|---|---|---|
| **Warm** (engine running, buffers discarded) | ~0 | ✅ | **lit permanently** |
| **Prepared-but-stopped** (VoiceInk's model) | ~10 ms built-in / ~100 ms Bluetooth | ❌ (no audio flows) | only while recording |

**Recommendation: default to prepared-but-stopped; offer warm + 200 ms pre-roll as an explicit opt-in** that names the always-on indicator as its cost. Do not make warm the silent default — a permanent orange dot on a menu-bar app is exactly the thing that gets an app uninstalled. Pair either mode with `AVAudioSinkNode` rather than `installTap` so you are not quantised to 100 ms.

**Battery cost of a warm engine: unresolved.** `[UNVERIFIED]` No measurement found. Apple's App Nap criteria list *"It isn't audible"* — a clause about **playback**, silent on recording. Whether a warm input engine defeats App Nap is unknown.

### 5.8 Capture API options

| Approach | Verdict |
|---|---|
| `AVAudioEngine` + `installTap` | Easiest, but **100–400 ms floor**. Fine for batch; wrong for low-latency. |
| **`AVAudioEngine` + `AVAudioSinkNode`** | **Best balance.** Hardware-rate buffers, realtime thread, keeps engine ergonomics. macOS 10.15+. |
| Raw AUHAL (`kAudioUnitSubType_HALOutput`) | **What VoiceInk ships.** Max control: per-device pinning without touching the system default, explicit buffer size, prepare/start separation. Most code. |
| `AudioQueue` | Not deprecated, but the buffer-queue model adds latency. No reason here. |
| `AVCaptureSession` + `AVCaptureAudioDataOutput` | **Keep as a contention fallback** — reported to work where `installTap` silently doesn't. |
| Core Audio process taps (`AudioHardwareCreateProcessTap`, macOS 14.2+) | For capturing *other processes' output*. Not applicable. |

**Two macOS 26 leads, both single unanswered beta reports — test, don't assume** `[UNVERIFIED]`:
- <https://developer.apple.com/forums/thread/794843> — `AVCaptureDevice.DiscoverySession` returned **zero** audio devices and `engine.start()` failed `-10877`, while CoreAudio HAL enumerated 14+ devices correctly (FB19024508). **Enumerate devices via HAL, not AVFoundation** — which VoiceInk and WhisperKit already do.
- <https://developer.apple.com/forums/thread/819525> — `installTap` silently not firing on Bluetooth; **and `NSEvent.addGlobalMonitorForEvents` crashing with a Bus error on macOS 26, fixed by moving to `CGEventTap`.** That second half is directly relevant to §1 and is another point for the tap.

---

## 6. macOS 26 "Tahoe" — what actually changed

> Everything in this section is documentation-derived. This machine cannot run Tahoe, and **it cannot even install Xcode 26**, which requires host macOS 15.6+ (this is 15.1). That is a hard blocker on compile-testing any Tahoe API here.

### 6.1 The release notes say almost nothing — and that is itself the finding

`[SOURCE]` <https://developer.apple.com/documentation/macos-release-notes/macos-26-release-notes>. A keyword scan across the macOS 26 notes plus the AppKit and SwiftUI update pages:

```
MenuBarExtra 0 · NSStatusItem 0 · NSStatusBar 0 · "menu bar" 0
NSPanel 0 · "window level" 0 · collectionBehavior 0 · nonactivating 0
```

**No deprecations** on `MenuBarExtra`, `NSStatusItem`, `NSStatusBar`, `NSPanel`, `NSWindow.level`, or `.nonactivatingPanel` — all six symbol pages report `"deprecated": false`. The entire AppKit section of the macOS 26 notes is a single TextKit bug fix.

**There is no "AppKit release notes for macOS 26"** — that series stops at Sonoma 14.

> **Caveat, and it matters:** absence from release notes is *not* proof of no behavior change. Apple documents **API** changes there, not **compositing** changes. Liquid Glass is a compositing change. See §6.4 for two real regressions that are in the forums and not in the notes.

**Two SwiftUI changes that will hit a menu bar app**, verbatim from the 26 notes:
- *"The default label style for macOS menu content is now `.titleAndIcon`. (137306701)"* — every `Label` in your `MenuBarExtra` menu gains an icon when built against the 26 SDK.
- *"The implementation of some macOS buttons no longer uses `NSButton`. (139105246)"*

**And macOS 27 reverses the icon change** `[SOURCE]` <https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes>: *"In macOS 27.0, menu bar and context menus present a reduced set of menu item images… By default, `NSMenu` hides all menu item symbol images… Use the new `preferredImageVisibility` property on `NSMenuItem`."* **Do not invest in menu icons.**

### 6.2 Liquid Glass and the transparent menu bar

Apple Newsroom, verbatim: *"The menu bar is now completely transparent, making the display feel even larger."* `[SOURCE]` <https://www.apple.com/newsroom/2025/06/macos-tahoe-26-makes-the-mac-more-capable-productive-and-intelligent-than-ever/>

Three user escapes exist (a per-feature "Show menu bar background" toggle; a "Liquid Glass: clear or tinted" picker added in 26.1; Accessibility → Reduce transparency), so **your status item icon must be legible against arbitrary wallpaper AND against a tinted bar.** The HIG's menu-bar page has **zero** occurrences of "Liquid Glass" or "transparent" — it still gives the pre-Tahoe guidance that template images use black and clear and the system tints them. That guidance was not revised for a transparent bar. `[UNVERIFIED]` — use a template image and test on a light wallpaper.

**API surface** `[SOURCE]` <https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)>, <https://developer.apple.com/documentation/appkit/nsglasseffectview>:
- SwiftUI: `glassEffect(_ glass: Glass = .regular, in shape: some Shape = DefaultGlassEffectShape())` — **macOS 26.0+**. There is **no `isEnabled:` overload**; that URL 404s. Also `GlassEffectContainer`, `glassEffectID(_:in:)`, `glassEffectUnion(id:namespace:)`, `.buttonStyle(.glass)`. Ordering rule, verbatim: *"Apply the `glassEffect(_:in:)` modifier after other modifiers that affect the appearance of the view."*
- AppKit: `NSGlassEffectView` / `NSGlassEffectContainerView`, **macOS 26.0 only**. Properties: `contentView`, `cornerRadius`, `effectIsInteractive` (defaults `NO`), `style`, `tintColor`.

**Glass and `NSVisualEffectView` do not compose.** WWDC25 session 310, verbatim `[SOURCE]` <https://developer.apple.com/videos/play/wwdc2025/310/>: *"If you're using an NSVisualEffectView to display that material inside of your sidebar, it will prevent the glass material from showing through. You should remove these visual effect views from your view hierarchy."* And: *"avoid placing the NSGlassEffectView behind your content as a sibling view."*

**Availability gating is a COMPILE-time problem, not a runtime one.** `[RUN-VERIFIED 15.1]`, with a positive control so the absence is a result and not a broken grep:

```
SwiftUI.swiftinterface (SDK 15.2):
  MenuBarExtra          = 26   <-- positive control: the grep works
  glassEffect           = 0
  GlassEffectContainer  = 0
AppKit headers: NSGlassEffectView       -> 0 files
Speech headers: SpeechAnalyzer          -> 0 files
FoundationModels.framework              -> ABSENT
```

So `if #available(macOS 26.0, *)` does **not** rescue you: with Xcode 16.2 these symbols do not compile at all. Either build with Xcode 26, or reach them dynamically. Lunar shows the dynamic pattern in shipping code `[SOURCE]` <https://github.com/alin23/Lunar/blob/master/Lunar/Views/OSDWindow.swift>:

```swift
guard let nsGlassEffectViewType = NSClassFromString("NSGlassEffectView") as? NSView.Type else { return NSView() }
let nsView = nsGlassEffectViewType.init(frame: .zero)
let hosting = NSHostingView(rootView: content)
nsView.setValue(hosting, forKey: "contentView")
```

**Opt-out:** `UIDesignRequiresCompatibility` (same key name on macOS, 26.0+). Apple: *"The system ignores this key when you build for… macOS 27 or later."* A bridge, not a strategy.

### 6.3 TCC and privacy in macOS 26: **no documented changes**

`[SOURCE]` — keyword scan of the macOS 26 release-notes JSON:
```
TCC 0 · permission 0 · "Input Monitoring" 0 · microphone 0
"Screen Recording" 0 · Gatekeeper 0 · consent 0 · authoriz 0
```
The macOS 26 notes have **no Security & Privacy section at all**, where macOS 15's did. No extension of periodic re-authorization to Input Monitoring or Accessibility appears in any Apple source. Sequoia's screen-recording reprompt (weekly → monthly) was **never documented by Apple in any release note**, so its Tahoe status is unknowable from primary sources — and it is largely moot here, since mumbler needs Microphone + Accessibility, not Screen Recording.

**One Tahoe TCC trap that IS real and does affect an SPM build:** in macOS 26.1, non-bundled executables hold grants but never appear in System Settings. Apple DTS (Quinn): *"IMO this is a bug and I encourage you to file it as such."* Reportedly fixed for Accessibility in 26.3 beta. `[UNVERIFIED]` **Do not ship the bare `.build/release/` binary — always assemble a real `.app`.**

### 6.4 Two Tahoe regressions that hit exactly this app shape

Neither is in the release notes. Both are in the forums, and one has an explicit "this is intended" from Apple.

**(a) `NSGlassContainerView` intercepts hit-testing.** `[SOURCE]` <https://developer.apple.com/forums/thread/788928>, verbatim: *"Starting with macOS 26 beta 1, a new NSGlassContainerView is added inside NSToolbarView. This view intercepts mouse events, so any SwiftUI Button (or other interactive view) overlaid on the title-bar / toolbar area no longer receives clicks."* (FB18201935, no Apple reply.)

**(b) Layered `NSHostingView`s stop receiving events on 26.2 — and Apple says this is expected.** `[SOURCE]` <https://developer.apple.com/forums/thread/812113>. Apple DTS, verbatim: *"I can confirm that it is the expected behavior. The correct solution here is to override `hitTest` and route events as desired. For example, disable user interaction in top `NSHostingView` by returning `nil` from its hitTest to always pass clicks through to the middle one."* (FB21579636)

> **These are the two most actionable Tahoe findings for a HUD that layers SwiftUI.** If your overlay has any interactive element, plan on overriding `hitTest` from the start.

### 6.5 New macOS 26 APIs worth knowing about

**`SpeechAnalyzer` / `SpeechTranscriber` — macOS 26.0, on-device, streaming, and genuinely good for this use case.** `[SOURCE]` <https://developer.apple.com/documentation/speech/speechanalyzer>, <https://developer.apple.com/documentation/speech/speechtranscriber>

Apple, verbatim: *"Analysis is asynchronous… the Swift API's modules provides their results via an `AsyncSequence`. Similarly, you provide speech input to this API via an `AsyncSequence` you create and populate."* And the volatile→finalized model, which is exactly what push-to-talk wants (WWDC25 277): *"You can show a rough result immediately and then show better iterations of that result over the next few seconds. We call the immediate rough results 'volatile results'… Eventually, the result will be as good as it can be, and the transcriber delivers one last finalized result."*

Use `prepareToAnalyze(in:)` on hotkey-down to cut first-token latency.

**Three traps:**
1. **Undocumented hardware gate.** An Apple engineer confirmed *"There are hardware requirements for using `SpeechTranscriber`"* and named A16 iPads; **no Mac-side list is published.** Gate on `SpeechTranscriber.isAvailable` and fall back to `DictationTranscriber` (macOS 26.0+, which notably does **not** require the user to have enabled Siri/keyboard dictation).
2. **Version trap:** `CaptureInputSequenceProvider` — the convenience type that pipes a mic straight into the analyzer — is **macOS 27.0 beta, not 26**. Targeting 26.0 means building your own `AVAudioEngine` → `AsyncStream<AnalyzerInput>` bridge.
3. **Models download at runtime** via `AssetInventory`, with a per-app locale reservation cap. System-managed and shared, so they do not inflate your app size.

**Do not confuse `SFSpeechAnalyzer` with `SpeechAnalyzer`.** `[RUN-VERIFIED 15.1]` — `Speech.tbd` exports `SFSpeechAnalyzer`, but it appears in **0** public headers (positive control: `SFSpeechRecognizer` appears in **2**). `SFSpeechAnalyzer` is a **private ObjC SPI class**, not the public Swift API.

`SFSpeechRecognizer` is **not** deprecated, but its documented **one-minute audio limit** is the reason to move off it.

**Foundation Models** (macOS 26.0, ~3B on-device params) is a reasonable punctuation/formatting cleanup pass, but is **Apple Intelligence devices and regions only**. Two release-note items matter: `prewarm()` now caches instructions and prompt prefix; and `Guardrails.permissiveContentTransformations` — *"allows transformations of content that might otherwise violate the default guardrails. Use this mode for text-to-text tasks, such as summarization and rewrite. (156721060)"* **You will hit guardrails on innocuous dictation without it.**

**Text insertion: there is nothing new in macOS 26.** Checked four places — the Accessibility updates page, all 37 symbols in `AXUIElement.h` (**zero** introduced in macOS 15/16/26), `CGPreflightListenEventAccess` (still `macOS 10.15`), and the 26 release-notes text sections. **You remain on `CGEvent` synthesis / `AXUIElement` / pasteboard-paste.** §3's decision stands unchanged on Tahoe.

---

## 7. The HUD overlay

### 7.1 Why `NSPanel` and not a SwiftUI `Window`

`sebsto/wispr` ships the clearest statement of the blocker, in a code comment on an app that targets macOS 26 `[SOURCE]` <https://github.com/sebsto/wispr/blob/main/Sources/WisprApp/UI/RecordingOverlayPanel.swift>:

> *"SwiftUI `Window` scenes always activate the app when shown via `openWindow`, stealing focus from whatever the user is dictating into. macOS 26 added `.windowLevel(.floating)` and `.allowsWindowActivationEvents(false)`, but the latter only prevents gesture-based activation — **the window itself still activates on appearance**. There is also no SwiftUI equivalent for `hidesOnDeactivate = false`, `.canJoinAllSpaces`, or `orderFrontRegardless()`."*

**So: `NSPanel`, on Tahoe, still.** Revisit at WWDC 2026 if Apple ships a non-activating SwiftUI window primitive.

### 7.2 The three non-negotiable rules

`[SDK-VERIFIED 15.2]`, `AppKit/Headers/NSWindow.h:51`, verbatim:
> *"`NSWindowStyleMaskNonactivatingPanel` Specifies that a panel that does not activate the owning application. **Only applicable for `NSPanel` (or a subclass thereof).**"*

**Rule 1: it must be an `NSPanel` subclass.** The style mask is inert on a plain `NSWindow`. This is the single most common mistake.

**Rule 2: raising the level silently opts you into transient behavior.** `[SDK-VERIFIED 15.2]`, `NSWindow.h:106-113`, verbatim:
> *"`NSWindowCollectionBehaviorManaged` Participates in spaces, exposé. Default behavior if `windowLevel == NSNormalWindowLevel`."*
> *"`NSWindowCollectionBehaviorTransient` Floats in spaces, hidden by exposé. **Default behavior if `windowLevel != NSNormalWindowLevel`.**"*
> *"`NSWindowCollectionBehaviorIgnoresCycle` Default behavior if `windowLevel != NSNormalWindowLevel`."*

You must set `collectionBehavior` explicitly or Exposé hides your HUD.

**Rule 3: `orderFrontRegardless()`, never `makeKeyAndOrderFront(_:)`.** And **never call `NSApp.activate`** on the dictation path.

### 7.3 Window levels — real numbers

`[RUN-VERIFIED 15.1]` — pure value queries; **no window was created and no UI was touched**:

```
NSWindow.Level.normal      = 0
NSWindow.Level.floating    = 3
NSWindow.Level.modalPanel  = 8
NSWindow.Level.mainMenu    = 24
NSWindow.Level.statusBar   = 25
NSWindow.Level.popUpMenu   = 101
NSWindow.Level.screenSaver = 1000
CGShieldingWindowLevel()   = 2147483628
CGWindowLevelForKey(.maximumWindow) = 2147483631
```

`NSWindow.Level` is arithmetic-friendly — VoiceInk's notch recorder uses `level = .statusBar + 3`.

### 7.4 Showing over full-screen apps — the part everyone gets wrong

**`.fullScreenAuxiliary` is necessary but NOT sufficient, and its name misleads.** Apple's doc says *"Windows with this collection behavior can be shown on the same space as the fullscreen window"* — which governs **your app's own** full-screen window. A forum poster puts it exactly right `[SOURCE]` <https://developer.apple.com/forums/thread/26677>: *"The `.FullScreenAuxiliary` behavior is exactly the opposite of what I and the original poster are looking for."* The same thread reports `MaximumWindowLevelKey` + `.canJoinAllSpaces | .fullScreenAuxiliary` giving *"the window on all the spaces but it does not display the window over the fullscreen app windows."*

**The combination that demonstrably works in shipping code is `.canJoinAllSpaces` plus a level at or above `.popUpMenu` (101).** The authority is `alt-tab-macos`, which visibly renders over other apps' full-screen spaces, and whose source explains the choice `[SOURCE]` <https://github.com/lwouis/alt-tab-macos/blob/master/src/switcher/main-window/TilesPanel.swift>:

```swift
// triggering AltTab before or during Space transition animation brings the window on the Space post-transition
collectionBehavior = .canJoinAllSpaces
// 2nd highest level possible; this allows the app to go on top of context menus
// highest level is .screenSaver but makes drag and drop on top the main window impossible
level = .popUpMenu
```

A dictation app encodes the ordering in **actual unit tests** `[SOURCE]` <https://github.com/TypeWhisper/typewhisper-mac/blob/main/TypeWhisperTests/FloatingPanelSpacePolicyTests.swift>:
```swift
func testNotchIndicatorPolicyUsesScreenSaverLevelAboveStatusBarButBelowShielding() {
    let level = FloatingPanelSpacePolicy.notchIndicatorWindowLevel
    XCTAssertEqual(level, .screenSaver)
    XCTAssertGreaterThan(level.rawValue, NSWindow.Level.statusBar.rawValue)
    XCTAssertLessThan(level.rawValue, Int(CGShieldingWindowLevel()))
}
```
That file also sets `panel.sharingType = .none` to exclude the HUD from screen captures — **steal that** for a dictation overlay.

**`[UNVERIFIED]`** — I could not isolate which variable is load-bearing without creating windows, which the safety constraint forbids. Treat this as "what shipping apps do", not as a controlled result.

### 7.5 The recommended recipe

Synthesised from four shipping apps. For mumbler's case — a **display-only** HUD that must never take focus — the closest match is `kitlangton/Hex`, itself a macOS dictation app `[SOURCE]` <https://github.com/kitlangton/Hex/blob/main/Hex/Views/InvisibleWindow.swift>:

```swift
final class InvisibleWindow: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }

  init() {
    let screen = NSScreen.main ?? NSScreen.screens[0]
    let styleMask: NSWindow.StyleMask = [.fullSizeContentView, .borderless, .utilityWindow, .nonactivatingPanel]
    super.init(contentRect: screen.frame, styleMask: styleMask, backing: .buffered, defer: false)

    level = .statusBar
    backgroundColor = .clear
    isOpaque = false
    hasShadow = false
    ignoresMouseEvents = true          // display-only: total click-through
    hidesOnDeactivate = false          // Prevent hiding when app loses focus
    canHide = false
    collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces, .stationary, .ignoresCycle]
  }

  static func fromView<V: View>(_ view: V) -> InvisibleWindow {
    let window = InvisibleWindow()
    window.contentView = NSHostingView(rootView: view)
    return window
  }
}
```
Its header comment is the design rationale: *"we create one giant invisible window that covers the entire screen, and render our SwiftUI views into it. I'm pretty sure this is what CleanShot X and other apps do."*

And `sebsto/wispr`'s smaller, positioned variant `[SOURCE]`:
```swift
let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 260, height: 92),
                    styleMask: [.borderless, .nonactivatingPanel],
                    backing: .buffered, defer: false)
panel.isFloatingPanel = true
panel.level = .floating
panel.isOpaque = false
panel.backgroundColor = .clear
panel.hasShadow = true
panel.hidesOnDeactivate = false
panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
panel.contentView = NSHostingView(rootView: overlayView)
// show:
panel.alphaValue = 0
panel.orderFrontRegardless()
NSAnimationContext.runAnimationGroup { ctx in
    ctx.duration = reduceMotion ? 0.0 : 0.25   // respect Reduce Motion
    panel.animator().alphaValue = 1.0
}
```

**`NSHostingView` vs `NSHostingController`:** both work. Hex and Axii assign `NSHostingView` to `contentView`; Lunar and VoiceInk assign `NSHostingController` to `contentViewController`. **Neither can force key status past `canBecomeKey = false`** — the override wins.

**Click-through:** `ignoresMouseEvents = true` is all-or-nothing at the window level; **there is no per-region window API.** For partial click-through, override `hitTest` in the content view and return `nil` for the pass-through regions — which is precisely what Apple DTS prescribed in §6.4(b). If you ever need a `TextField` in the panel, `NSPanel.becomesKeyOnlyIfNeeded` is the AppKit-sanctioned lever.

**Activation policy:** `[SDK-VERIFIED 15.2]` `NSApplication.h`: *"In OS X 10.9, any policy may be set."* Set `LSUIElement` in `Contents/Info.plist` **and** call `NSApp.setActivationPolicy(.accessory)` — the plist prevents a Dock-icon flash on launch, the runtime call is belt-and-braces.

---

## 8. Building it with SPM (no Xcode project)

**It works, and there is a shipping precedent.** `sebsto/wispr` is a Swift 6.2 SPM package targeting `platforms: [.macOS(.v26)]` with an `executableTarget` for the menu-bar app `[SOURCE]` <https://github.com/sebsto/wispr/blob/main/Package.swift>:

```swift
// swift-tools-version: 6.2
let swiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("MemberImportVisibility"),
    .defaultIsolation(MainActor.self),      // <- worth copying; this app is MainActor-heavy
]
let package = Package(
    name: "wispr",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "WisprCore", dependencies: ["WhisperKit", "FluidAudio"], swiftSettings: swiftSettings),
        .executableTarget(name: "WisprApp", dependencies: ["WisprCore", …],
                          exclude: ["Resources/Sounds", "Assets.xcassets"], swiftSettings: swiftSettings),
    ]
)
```

### 8.1 The Info.plist question, answered by experiment

There are two places a plist can live and **they do different jobs**. A discriminating experiment (embedded section says `dev.local.EMBEDDED`, on-disk `Contents/Info.plist` says `dev.local.ONDISK`, same binary) `[SOURCE — subagent-run on this machine]`:

```
codesign of the .app bundle : Identifier=dev.local.ONDISK
codesign of the bare binary : Identifier=dev.local.EMBEDDED
runtime, bare binary        -> dev.local.EMBEDDED
runtime, inside App.app     -> dev.local.ONDISK
```

**Verdict: the `-sectcreate` embedded plist governs the bare executable (handy for `swift run` during development). Once inside a `.app`, `Contents/Info.plist` wins for both code signing and `Bundle.main`. For TCC and Launch Services you need the real on-disk file. Ship both.**

Package.swift for the embedded section (note `exclude:` — SPM forbids a top-level target file named `Info.plist`) `[SOURCE]` <https://github.com/steipete/RepoBar/blob/main/Package.swift>:
```swift
.executableTarget(
    name: "Mumbler",
    exclude: ["Resources/Info.plist"],
    swiftSettings: [
        .unsafeFlags([
            "-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist",
            "-Xlinker", "Sources/Mumbler/Resources/Info.plist",
        ]),
    ])
```
`.unsafeFlags` is allowed in a **root** package and rejected for versioned dependencies — fine here.

Bundle assembly `[SOURCE]` <https://github.com/steipete/RepoBar/blob/main/Scripts/package_app.sh>:
```bash
swift build -c release
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp "${EXE}" "${APP}/Contents/MacOS/${NAME}"
cat > "${APP}/Contents/Info.plist" <<PLIST
  <key>LSUIElement</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>…</string>
PLIST
codesign --force --deep --sign "Mumbler Dev" "${APP}"   # NOT "-" — see §4.4
```
The general-purpose tool if you want one: `stackotter/swift-bundler`.

**Two hard rules that fall out of §4.4 and §6.3:**
1. **Never `codesign --sign -`.** Ad-hoc means a cdhash-pinned TCC grant that dies on every rebuild.
2. **Never run the bare `.build/release/` binary as the app.** On macOS 26.1 a non-bundled executable can hold grants but never appear in System Settings, leaving the user no way to manage them.

---

## 9. First-boot test plan for Tahoe

Every claim in this document that I could not run is listed here as an executable check. Run these in order on the first Tahoe machine; each one either confirms a design assumption or forces a redesign, and none takes more than a few minutes.

| # | Assumption | Test | If it fails |
|---|---|---|---|
| 1 | `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility` still resolves | Click each of the three permission buttons; confirm the correct **pane** opens, not the front page | Switch to `com.apple.settings.PrivacySecurity.extension` host; keep the 3-tier fallback |
| 2 | A `.defaultTap` on `.flagsChanged` needs **Accessibility**, not Input Monitoring | Grant only Accessibility; confirm `CGEvent.tapCreate` returns non-nil and the tap fires | Add `CGRequestListenEventAccess()`; accept the admin-auth step |
| 3 | Right-Option detection via keycode 61 works | Log `keyCode` + `flags` on every `flagsChanged` for 30 s of normal typing; confirm 61 appears only for Right-Option | Fall back to device-bit `NX_DEVICERALTKEYMASK` (0x40) |
| 4 | **Secure Input does not block `flagsChanged`** (§3.4 — this is load-bearing for the whole hotkey pick) | Focus a password field, confirm `IsSecureEventInputEnabled() == true`, then hold Right-Option and confirm the hotkey still fires | The bare-modifier advantage evaporates; Handy's Carbon shadow-registration becomes mandatory |
| 5 | A posted ⌘V still lands while Secure Input is on | Same setup, dictate into a *non*-secure field in a different app | Keep `slovo`'s fail-closed triple check and surface the state |
| 6 | Ad-hoc → named-cert signing preserves the grant | Grant Accessibility to a cert-signed build, make a real code change, rebuild, relaunch, confirm still granted. Then decode `csreq` and confirm it pins `identifier` + certificate, **not** `cdhash` | Fall back to a documented "re-grant after rebuild" dev loop |
| 7 | HUD floats over another app's full-screen space without stealing focus | Full-screen Safari, type in a text field, trigger the HUD, keep typing | Escalate level to `.popUpMenu` (101) then `.screenSaver` (1000); keep `.canJoinAllSpaces` |
| 8 | `installTap` really is floored at 100 ms | Request `bufferSize: 1024`, print `buffer.frameLength` for 20 buffers | (Expect 4800 @ 48 kHz — confirming the floor, which is the reason to move to `AVAudioSinkNode`) |
| 9 | `prepare()` does **not** light the orange dot; `start()` does | Prepare only, watch the indicator for 60 s; then start | Warm-engine mode is off the table entirely; ship prepared-but-stopped only |
| 10 | Fn's Globe action is genuinely unsuppressible | Bind Fn, return `nil` from a `.defaultTap`, with `AppleFnUsageType` at 2 (Emoji). See if the picker appears | If it *is* suppressed, Fn becomes viable as an opt-in without the warning |
| 11 | The transparent menu bar does not eat the status icon | Light wallpaper, tinted mode, and Reduce Transparency | Ship a template image with a subtle stroke |
| 12 | Layered `NSHostingView` still receives events (§6.4b) | Put one interactive control in the HUD and click it | Override `hitTest` per Apple DTS |

**Test 4 is the one to run first.** It is the load-bearing assumption behind the entire hotkey recommendation, it comes from two independent secondary sources rather than from Apple, and it takes ninety seconds to check.

---

## Sources

**Apple primary**
- <https://developer.apple.com/documentation/coregraphics/cgpreflightlisteneventaccess()> · <https://developer.apple.com/documentation/coregraphics/cgrequestlisteneventaccess()>
- <https://developer.apple.com/library/archive/technotes/tn2150/_index.html> — TN2150, Using Secure Event Input Fairly
- <https://developer.apple.com/forums/thread/763878> — Apple engineer on the Sequoia `RegisterEventHotKey` -9868 clampdown
- <https://developer.apple.com/forums/thread/766200> — Fn HID usage mismatch, FB15532267
- <https://developer.apple.com/forums/thread/730043> · <https://developer.apple.com/forums/thread/703188> — Quinn (DTS) on TCC and stable signing identity
- <https://developer.apple.com/forums/thread/788928> — Tahoe `NSGlassContainerView` hit-testing regression (FB18201935)
- <https://developer.apple.com/forums/thread/812113> — layered `NSHostingView` events on 26.2; Apple DTS "expected behavior" (FB21579636)
- <https://developer.apple.com/forums/thread/26677> · <https://developer.apple.com/forums/thread/759780> — full-screen overlay attempts
- <https://developer.apple.com/forums/thread/814269> — `2003329396` during FaceTime · <https://developer.apple.com/forums/thread/819525> — Bluetooth `installTap` silence + `NSEvent` global-monitor Bus error on 26 · <https://developer.apple.com/forums/thread/794843> — `DiscoverySession` empty on 26 · <https://developer.apple.com/forums/thread/797033> — 4800-frame floor
- <https://developer.apple.com/forums/thread/814074> — stuck-fn producing phantom Dictation/Emoji popups
- <https://developer.apple.com/documentation/avfaudio/avaudioengineconfigurationchangenotification> · <https://developer.apple.com/documentation/avfaudio/avaudionode/installtap(onbus:buffersize:format:block:)> · <https://developer.apple.com/documentation/avfaudio/avaudiosession> (macOS absent)
- <https://developer.apple.com/documentation/macos-release-notes/macos-26-release-notes> · <https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes> · <https://developer.apple.com/documentation/Updates/AppKit> · <https://developer.apple.com/documentation/Updates/SwiftUI>
- <https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)> · <https://developer.apple.com/documentation/appkit/nsglasseffectview> · <https://developer.apple.com/videos/play/wwdc2025/310/>
- <https://developer.apple.com/documentation/speech/speechanalyzer> · <https://developer.apple.com/documentation/speech/speechtranscriber> · <https://developer.apple.com/documentation/speech/dictationtranscriber> · <https://developer.apple.com/videos/play/wwdc2025/277/>
- <https://developer.apple.com/documentation/appkit/nspasteboard/accessbehavior-swift.enum>
- <https://support.apple.com/en-mt/guide/mac-help/kbdm162/26/mac/26> — "Press 🌐 key to" on Tahoe
- <https://www.apple.com/newsroom/2025/06/macos-tahoe-26-makes-the-mac-more-capable-productive-and-intelligent-than-ever/>

**Real open-source code read at file level**
- <https://github.com/sebsto/wispr> — SPM + Swift 6.2 + `.macOS(.v26)`; `HotkeyMonitor.swift`, `TextInsertionService.swift`, `RecordingOverlayPanel.swift`, `PermissionManager.swift`, `Package.swift`
- <https://github.com/Beingpax/VoiceInk> — `ShortcutMonitor.swift`, `Shortcut.swift`, `CursorPaster.swift`, `CoreAudioRecorder.swift`, `NotchRecorderPanel.swift`
- <https://github.com/cjpais/Handy> + <https://github.com/handy-computer/handy-keys> — `secure_input.rs`, `paste_tx/macos.rs`, `input.rs`, `listener.rs`
- <https://github.com/Akurganow/slovo> — `CGEventTapHotkeyMonitor.swift`, `FnKeyAssignment.swift`, `ClipboardPasteInjector.swift`, `docs/references/macos-fn-hotkey.md`
- <https://github.com/Starmel/OpenSuperWhisper> — `ModifierKeyMonitor.swift`, `PermissionsManager.swift`, `ClipboardUtil.swift`
- <https://github.com/kitlangton/Hex> — `InvisibleWindow.swift`, `PasteboardClient.swift`
- <https://github.com/lwouis/alt-tab-macos> — `TilesPanel.swift`, `src/experimentations/EscapeAndGameOverlay.md`
- <https://github.com/espanso/espanso> — `espanso-mac-utils/src/native.mm` (secure-input PID via `IOConsoleUsers`)
- <https://github.com/pqrs-org/Karabiner-Elements> — `event_tap_utility.hpp`; <https://github.com/pqrs-org/cpp-hid> — vendor usage pages
- <https://github.com/Hammerspoon/hammerspoon> — `libeventtap_event.m`, `libeventtap.m`
- <https://github.com/argmaxinc/WhisperKit> — `AudioProcessor.swift`
- <https://github.com/ggml-org/whisper.cpp> — `examples/common-sdl.cpp` (200 ms pre-roll ring)
- <https://github.com/sindresorhus/KeyboardShortcuts> — `HotKey.swift`, `Shortcut.swift`
- <https://github.com/alin23/Lunar> — `OSDWindow.swift` · <https://github.com/TypeWhisper/typewhisper-mac> — `FloatingPanelSpacePolicyTests.swift` · <https://github.com/bwarzecha/Axii> · <https://github.com/steipete/RepoBar> · <https://github.com/Shopify/tophat>
- <https://github.com/OpenWhispr/openwhispr> — WindowServer-ahead-of-taps comment; `TISUpdateFnUsageType` usage
- <https://github.com/electron/electron/issues/36337> · <https://github.com/electron/electron/issues/37465> · <https://www.electronjs.org/docs/latest/tutorial/accessibility/>
- <https://github.com/kovidgoyal/kitty/issues/9661> · <https://github.com/kovidgoyal/kitty/issues/10119> — swallowed bare modifiers break system double-tap
- <https://github.com/feedback-assistant/reports/issues/552> — FB15168205 · <https://github.com/lionheart/openradar-mirror/issues/21098> — `kCGSSessionSecureInputPID` background bug
- <https://github.com/anthropics/claude-code/issues/28137> — paste/Enter race
- <https://github.com/Beingpax/VoiceInk/issues/158> — Fn PTT + debounce

**Practitioner write-ups**
- <https://stormacq.com/2026/03/30/one-month-of-wispr-from-first-release-to-cli/> — dual-backend Carbon + CGEventTap; the Globe gotcha
- <https://danielraffel.me/til/2026/02/19/cgevent-taps-and-code-signing-the-silent-disable-race/>
- <https://evoleinik.com/posts/macos-dev-signing-preserve-permissions/> — self-signed cert for stable TCC identity
- <https://mjtsai.com/blog/2025/05/12/pasteboard-privacy-preview-in-macos-15-4/> · <https://mjtsai.com/blog/2023/11/20/the-hidden-secrets-of-the-fn-key/>
- <https://macos-defaults.com/keyboard/applefnusagetype.html> · <https://github.com/nix-darwin/nix-darwin>
- <https://espanso.org/docs/troubleshooting/secure-input/> · <https://manual.raycast.com/ai/dictation>
- <https://docs.wisprflow.ai/articles/2612050838-supported-unsupported-keyboard-hotkey-shortcuts> · <https://superwhisper.com/docs/get-started/settings-shortcuts> · <https://tryvoiceink.com/docs/shortcuts> · <https://docs.macwhisper.com/article/14-how-to-use-the-dictation-feature> · <https://aquavoice.com/info/faq> · <https://help.willowvoice.com/en/articles/10876257-hotkey-settings>

---

## What I could not verify

**The single largest gap: no macOS 26 machine, and no way to get one here.** This box is 15.1 with Xcode 16.2; Xcode 26 requires host macOS 15.6+, so I could not even *compile-test* a Tahoe API, let alone run one. **Every §6 claim is documentation-derived.** Absence from Apple's release notes is not proof of no behavior change — Apple documents API changes there, not compositing changes, and Liquid Glass is a compositing change. §9 exists because of this.

**Nothing that touches live input was tested, by design.** Per the safety constraint I created no windows, posted no `CGEvent`, opened no microphone, and ran no UI automation. So these specific things are **unverified by execution** even on Sequoia: that a `.defaultTap` on `flagsChanged` actually fires; that returning `nil` suppresses anything; that a posted ⌘V lands anywhere; that any `NSPanel` recipe in §7 renders over a full-screen app; that the orange dot behaves as the header says. All of §7's panel configuration is read from shipping source, not observed.

**Specific open questions, each with its test in §9:**

1. **Whether a `.cgSessionEventTap` returning `nil` on Fn suppresses the Globe action.** My "no" verdict (§2.2) rests on three consistent things — `TextInputSwitcher` importing symbolic-hotkey SPI and **zero** `CGEventTapCreate`; OpenWhispr's explicit comment; and every Globe-key tool instructing users to set "Do Nothing" — but **none of them is a measurement.** The one published tap-ordering experiment (`alt-tab-macos`) measured macOS 26 Game Overlay, a *different* symbolic hotkey, and found `cghidEventTap` *could* absorb it. Do not transfer that result to Fn without test #10.
2. **The Accessibility-vs-Input-Monitoring rule for event taps is genuinely unsettled, and I did not resolve it.** What I can state is what shipping code *does*: VoiceInk, Handy, slovo and Hammerspoon check only `AXIsProcessTrusted()`; OpenSuperWhisper (which uses `.listenOnly`) checks both. `slovo`'s own reference doc flags the mapping as practitioner-observed and cites **conflicting Apple DTS guidance** (Quinn recommends `CGPreflightListenEventAccess` for a plain tap). Test #2.
3. **`kCGHIDEventTap` root requirement.** `CGEvent.h` says *"Taps may only be placed at `kCGHIDEventTap` by a process running as the root user"*; alt-tab reports it working with Accessibility alone on 26.3.1. Unresolved.
4. **Whether Secure Input blocks posted ⌘V.** TN2150 covers interception only. I found no authoritative statement. Test #5. Until then, fail closed.
5. **The `flagsChanged`-survives-Secure-Input finding** (§3.4) comes from two secondary sources, not Apple. It is load-bearing for the hotkey recommendation. **Test #4 first.**
6. **The ad-hoc→broken-grant causal chain.** I proved the stored `csreq` is a literal `cdhash` for ad-hoc apps and a certificate pin for Developer ID apps, and found two of this machine's own dev spikes sitting stale at `auth=0`. I did **not** grant, rebuild, and observe revocation — that would have triggered TCC prompts. The consequence is deduced from how cdhash works, not observed. Test #6.
7. **The orange-dot boundary.** Apple's header pins it to "engine is running," which answers the warm-engine question. It does **not** resolve whether the trigger is `AudioUnitInitialize`, `AudioOutputUnitStart`, or the first IOProc callback. No API exists to query indicator state. Test #9.
8. **Cold-start latency in milliseconds.** No published `AVAudioEngine.start()` input-side measurement on macOS exists that I could find. The only real numbers are Handy's in-source ~10 ms built-in / ~100 ms Bluetooth for the *first-callback* gap — related but distinct, and itself uninstrumented. I did not compute or estimate a number.
9. **Warm-engine battery cost.** No measurement found. Apple's App Nap criteria say *"It isn't audible"* — about playback, silent on recording.
10. **Which variable makes a HUD float over full-screen.** `.canJoinAllSpaces` + high level works in shipping apps; I did not isolate the cause and forum reports conflict.
11. **Fn on an external Apple Magic Keyboard vs built-in.** Wispr's docs say built-in only; aresluna.org says both. Directly contradictory, untested.
12. **`AppleFnUsageType = 3` → "Start Dictation"** is three concurring documentary sources plus the correlation that this machine reads `3` and has 547 dictation invocations logged. I did not open System Settings to read the label.
13. **Whether `SpeechAnalyzer`/`SpeechTranscriber` need Speech Recognition TCC authorization.** None of the four doc pages mentions it. Plan for both usage-description strings.
14. **Mac hardware floor for `SpeechTranscriber`** is unpublished. Gate on `isAvailable`.
15. **Reddit was entirely inaccessible** (HTTP 400 to this agent), so the user-reports section draws on GitHub issues, Apple forums and HN instead.
16. **Repo line numbers will drift** — Hammerspoon, Karabiner-Elements and cpp-hid were read from `master`/`main` without pinned SHAs.
17. **One relay hop.** Apple *forum* quotes came through subagents because developer.apple.com blocks raw fetches. I independently re-verified the highest-stakes items myself on this machine: the SDK symbol absences (with a positive control), the window-level values, the TCC `csreq` decoding, the `IOConsoleUsers` secure-input probe, the `TextInputSwitcher` binary analysis, and the System Settings anchor list.

**Two of my own probes initially returned false results, reported here because they calibrate confidence in the rest.** `CGSessionCopyCurrentDictionary()` looked like the right secure-input API and is recommended by several blog posts — it returns 11 keys and **never** contains `kCGSSessionSecureInputPID`; only running it revealed that, and `IOConsoleUsers` is the correct source. And the first SDK symbol scan pointed at a nonexistent `.swiftinterface` path, silently returning "0 hits" for everything; the numbers in §6.2 are the re-run, with `MenuBarExtra = 26` as the positive control proving the grep could find things at all. A zero I had not tried to make non-zero would have been a rumor.

