# Task 136 - The Accessibility notice becomes a fix-it row, and #6's conclusion is reversed

Measured 2026-08-24 on macOS 26.6.2.

---

## 1. What was there

`MenuContent.swift` rendered `startupFailure` as a bare `Text`:

> Hold-to-dictate needs Accessibility. Grant it in System Settings > Privacy & Security >
> Accessibility, then relaunch PushText.

A sentence naming a path, with no button - directly above `PermissionRow`s that have one. Two code
paths for "a grant is missing", and only one of them was actionable.

## 2. What TermTile does, read rather than recalled

`Sources/TermTile/MenuBarContent.swift` switches on a three-state `AccessibilityState` and renders
MacFaceKit's `NoticeCard`:

```swift
case .needsFirstGrant:
    NoticeCard(title: "Accessibility access required", ...,
               linkLabel: "Allow Accessibility", url: viewModel.accessibilitySettingsURL)
case .grantBroken:
    NoticeCard(title: "Accessibility access needs reset", ...,
               actionLabel: "Reset & Open Settings", actionSystemImage: "arrow.clockwise") {
        _ = viewModel.repairAccessibilityPermission()
        NSWorkspace.shared.open(viewModel.accessibilitySettingsURL)
    }
```

PushText already had the three-state model (`SystemPermissionProbe` + the latch) and already had
row-with-button rendering. What it lacked was the repair action and a route from a startup failure
into that machinery.

## 3. #6 declined a repairer, and #6 was wrong

From `task6-permission-recovery.md`:

> **Accessibility and PostEvent: it would make recovery WORSE.** Resetting it removes that entry, and
> neither permission has a prompt the app can raise - so the user then has to open Settings and
> **add** PushText with `+`. Toggling an entry that is already there is strictly less work than
> re-adding one that a button just deleted.

**That assumes toggling works.** TCC binds a grant to the app's code IDENTITY, so after a re-sign the
listed row belongs to a build that no longer exists: toggling it re-grants the old one and the
current app stays denied. TermTile's repairer says so in its own docstring - it *"only clears
TermTile's own old rows so the current signed app can be granted normally"*.

Observed the same day: replacing a locally dev-signed PushText with the Developer ID-signed release
left Accessibility asking for a grant the user had already given. The entry was there. Toggling it
would have re-granted a bundle that no longer existed.

The earlier reasoning was not lazy - it was checked against the wrong case. It reasoned about a grant
the user had revoked, where the row is current and toggling does work. It never considered a row that
had gone stale, which is the case the `grantBroken` state exists for.

## 4. A runtime failure outranks the probe

The tap failing to arm is DIRECT evidence that Accessibility is unusable. `AXIsProcessTrusted()` is a
second-hand report of the same fact, and after a re-sign the two disagree.

So `PermissionAdvisor.runtimeFailures` downgrades a permission to `.grantBroken` regardless of the
probe. It downgrades rather than appending, so a permission the probe already flags is never
duplicated - asserted by test.

## 5. Battle-tested

Repairer, three plants, all caught:

| planted regression | caught by |
| --- | --- |
| drop the bundle id from the reset | "every reset is scoped to this app's bundle id" - an unscoped `tccutil reset Accessibility` clears EVERY app on the machine |
| collapse PostEvent into Accessibility | "each permission maps to its real TCC service name" |
| always report success | "a non-zero exit is reported as failure, not swallowed" |

Advice, one plant: flipping `repairs` to true everywhere failed both "nothing else offers to reset
anything" and "a broken microphone grant prompts rather than resetting".

A second advice plant did NOT land - the string did not match, so it never modified anything. Not
counted as a pass; the first plant already exercises that assertion.

## 6. Rendered

`PUSHTEXT_MENU_PROBE_PERMISSION=accessibility` forces the row so it can be looked at - the same idea
as `PUSHTEXT_HUD_PROBE_REFUSE`, because a state that only occurs when a grant is genuinely missing
cannot be screenshotted on a machine where the grant is present.

The row now reads "Accessibility / Access was granted before and has stopped working ... Clear that
entry and allow this copy" above a **Reset & Open Settings...** button with a gear icon.

## 7. What this does NOT show

**No `tccutil` has been run against a real grant.** Every test injects the runner, deliberately -
a test that shelled out would destroy the developer's own grants. So the reset is verified as
"the right command, scoped correctly, with failures reported", not as "clears a real stale row".
Whether `tccutil reset Accessibility <id>` needs `sudo` for a row that actually exists is still
unmeasured, and remains the open question `task6-permission-recovery.md` recorded.
