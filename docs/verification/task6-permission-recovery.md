# Task 6 - Permission recovery: what shipped, and the repairer that did not

Measured 2026-08-23 on macOS 26.6.2.

---

## 1. The defect: one OS state, two different answers

`SystemPermissionProbe.microphoneStatus()` derives **both** unmet microphone states from the same
reading:

```swift
case .notDetermined:
    return latch.wasEverGranted(.microphone) ? .grantBroken : .needsFirstGrant
```

`AVAuthorizationStatus.notDetermined` is the whole OS input. The latch that separates the two is
**ours**, persisted in `UserDefaults` - TCC knows nothing about it.

`AVCaptureDevice.requestAccess(for:)` prompts whenever the status is `.notDetermined`. So the app can
raise the system prompt in **both** states, by construction, and no measurement is needed to know it:
they are the same state.

The menu did not act that way. `needsFirstGrant` offered **Allow...** and `grantBroken` sent the user
to System Settings. That is worse than a detour - with no TCC entry recorded, there is nothing in that
pane to act on. The user is told to go and fix something that is not listed.

Fixed: a broken microphone grant now offers **Allow Again...** and prompts. The copy still says the
access "was granted before and has stopped working", because the diagnosis is still different even
though the remedy is the same.

Accessibility and PostEvent are the opposite case and keep the Settings route: their entry IS still
in the list, ticked and ineffective after a re-sign, and toggling it off and on is what re-associates
it with the new signature. `PermissionAdviceTests` now asserts the asymmetry in both directions, so a
later "make it consistent" edit cannot hand them a prompt button that does nothing.

Rendered rather than asserted: `PermissionRowSnapshotTests` stacks the first-grant and repair rows
against each other, because the risk with an asymmetry is that it reads as inconsistency. It does
not - the shield icon on **Allow Again...** and the gear on **Open Settings...** already say they are
different actions.

## 2. `TCCPermissionRepairer` was specified and is not being built

> **SUPERSEDED 2026-08-24 by #136.** The section below argues against a repairer on the grounds that
> resetting forces the user to re-ADD the app, which is more work than toggling a row that is already
> there. That assumes toggling WORKS, and it does not when the row is stale: TCC binds a grant to the
> app's code identity, so after a re-sign the listed entry belongs to a build that no longer exists.
> TermTile has shipped a repairer for exactly this reason. The reasoning below was checked against
> the wrong case - a grant the user revoked, where the row is current - and never considered the
> stale row that `grantBroken` exists for. Kept rather than rewritten, because the argument's shape
> is the useful part: see `task136-permission-fixit-row.md`.

The issue asked for `tccutil reset <SERVICE> <bundleID>` behind a fix-it button. It should not exist,
for a different reason per permission:

**Microphone: unnecessary.** A broken grant is `.notDetermined` - the entry is already gone. There is
nothing for `tccutil` to reset, and the prompt already works. This is the fix in section 1.

**Accessibility and PostEvent: it would make recovery WORSE.** Their broken state is an entry that is
present and ineffective. Resetting it removes that entry, and neither permission has a prompt the app
can raise - so the user then has to open Settings and **add** PushText with `+`. Toggling an entry
that is already there is strictly less work than re-adding one that a button just deleted.

That holds regardless of privilege, so the sudo question below never decides anything.

## 3. What the tccutil measurement did and did not show

Non-destructive: a throwaway `.app` under a bundle id TCC has never seen, registered with
`lsregister`, then unregistered and deleted. No real grant was touched.

```
tccutil reset Microphone     dev.ecn.apps.pushtext-tccprobe   exit=0  Successfully reset
tccutil reset Accessibility  dev.ecn.apps.pushtext-tccprobe   exit=0  Successfully reset
tccutil reset PostEvent      dev.ecn.apps.pushtext-tccprobe   exit=0  Successfully reset
```

All three succeeded **without sudo**, which is the opposite of what `docs/research/04` sec 4.2 says.

**That is not a disproof, and it is important not to report it as one.** The probe id held no grants,
so "Successfully reset" may be a no-op that never wrote to the root-owned system TCC database where
Accessibility and PostEvent rows live. What was shown: `tccutil` *accepts* the command as the user.
What was NOT shown: that a real Accessibility grant can be *removed* as the user. Testing that
requires destroying a live grant on this machine, which is a user-visible cost with no payoff, since
section 2 already decided against the repairer.

The research claim therefore stands as unverified in both directions rather than corrected.

An unrelated trap worth recording: `tccutil` validates the bundle id against LaunchServices **before**
any privilege check. An unregistered id returns `exit=64, OSStatus -10814` for every service, which
looks exactly like a permission failure and is not one. The first two attempts at this measurement
read that as the answer.

## 4. Prompting for Accessibility and PostEvent stays unwired, deliberately

`AXIsProcessTrustedWithOptions` shows a dialog whose only content is a button to System Settings -
less context than the menu row already gives. The row is the better prompt, so `canPromptInApp` is
false for both and the test asserts it.
