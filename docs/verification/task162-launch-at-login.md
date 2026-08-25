# Task 162 - Launch at login, and the isolation that never worked

Measured 2026-08-25 on macOS 26.6.2.

---

## 1. The feature

`SMAppService.mainApp`, behind a toggle in a new GENERAL section. `mainApp` rather than a helper
bundle: PushText IS the thing to launch, so there is no login helper to install.

**Three states, not a Bool.** `SMAppService` can accept a registration and park it awaiting the
user's approval in System Settings - the app will NOT start at the next login while it sits there. A
Bool would draw that as ON and nothing would explain the silence, which is the same shape as the
permission rows that claimed a grant the app did not hold (#152). So `requiresApproval` reads as ON -
the user did ask for it - with a notice beside it saying macOS is waiting for them.

**Read through, never cached.** The user can disable PushText in System Settings without telling the
app; a stored `Bool` would keep drawing ON forever.

## 2. The dependency the backlog flagged, and it was right

`.engine/BACKLOG.md` recorded this as a DEPENDENCY rather than a nicety:

> Uninstaller must deregister it in the same change. Today's uninstall is correct ONLY because there
> is nothing to deregister.

Without it, uninstall leaves macOS trying to start an application that is no longer on disk, at every
login, with nothing left to point at. `Uninstaller.deregisterLoginItem()` runs before the bundle is
trashed.

Three plants: skipping the login item entirely, missing the awaiting-approval case, and reporting
success when `disable()` throws - all fail the suite.

**One of those plants first proved nothing.** Removing the `do`/`catch` left an orphaned `catch` and
broke the build; the test run printed no `✘` lines, and a grep for failures found none. A COMPILE
ERROR read as "no test failed". Rewritten so it compiles, the plant fires.

## 3. What this work uncovered: HOME does not isolate preferences (#185)

Rendering the new toggle changed Bobby's real dictation hotkey - the SECOND time in one day a probe
in this repo did that, and the first time it happened under the isolation that was supposed to
prevent it.

```
$ env HOME="$S/login/home" CFFIXED_USER_HOME="$S/login/home" PUSHTEXT_MENU_PROBE=1 <app>
$ find "$S/login/home" -name "*.plist"
(nothing)
$ defaults read dev.ecn.apps.pushtext hotkeyKeyCode
63          # changed, in the REAL domain
```

**The redirected home received no plist at all.** `cfprefsd` serves the logged-in user's domain
regardless of `HOME` and `CFFIXED_USER_HOME`. `HOME` isolates FILES; it has never isolated
preferences, and every probe run in this repo has been writing the user's real settings.

`scripts/test-packaged-app.sh` used the same approach, so anyone running the smoke was running an app
that could rewrite their own preferences. It had not bitten only because those probes happened not to
change settings.

### The fix, and the proof

`PUSHTEXT_DEFAULTS_SUITE` names a separate domain. `UserDefaultsSettingsStore(suiteName:)` already
existed and was unused - the seam was there.

```
real value BEFORE          61
seed isolated suite with   63
run the probe under the suite
real domain   = 61   (unchanged)
isolated suite = 63   (the app read it)
REAL SETTINGS UNTOUCHED
```

And the packaged smoke, which now exports the suite and deletes it on exit:

```
real hotkey before=61 after=61 (smoke left it alone)
```

The trust latch went through `UserDefaults.standard` directly and now uses the same suite - it had
been writing real `grantLatch` keys, which were visible in the user's domain.

## 4. What rendering caught

The Globe notice title was truncated to *"The Globe key also does something e…"*. Shortened to
"Globe has a system action". Invisible in source; obvious in a screenshot.

## 5. What this does NOT show

Nobody has rebooted. `SMAppService.mainApp.register()` returning success and the app actually
starting at the next login are different claims, and only the second one is the feature. The status
is read back from `SMAppService` rather than from our own memory, which is the strongest check
available without a reboot.

No test calls the real `SMAppService`: registering would write a real login item for whoever runs the
suite and leave it there. Every test uses a fake, and that is deliberate rather than a gap - see #185
for what happens when a test touches the real machine.
