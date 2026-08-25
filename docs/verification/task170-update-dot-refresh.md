# Task 170 - The update dot never appeared, and there were three reasons, not one

Measured 2026-08-25 on macOS 26.6.2.

Bobby: *"if there's a new version out, why not seeing the indicator dot on the app navbar icon, and
the ellipses, and the download menu item like in termtile"*.

He was right, and #138 had already shipped and closed with the indicator "verified".

---

## 1. The measurement that started it

```
PushText 0.3.0 (build 102), pid 18738, started 05:08 UTC (up 1h07m)
v0.3.1 published                          05:34 UTC
```

The running app launched **26 minutes before** the release it should have been pointing at.

## 2. Cause one: the probe ran once, at launch

`refreshUpdateAvailability()` was called from exactly one place - `launchDelegate.onLaunch`.
`SUEnableAutomaticChecks` is false and stays false, because automatic checks make Sparkle present
its own dialog on a schedule. So nothing re-checked, ever.

Fixed with `UpdateCheckPolicy` (pure, in Core, six tests, four plants): re-checked every six hours
and whenever the menu opens, rate-limited to one check per thirty minutes so opening the menu
repeatedly does not hammer the appcast, suppressed while a check is in flight, and - deliberately -
allowed to run when the clock has gone BACKWARDS, since reading a negative interval as "just
checked" would disable the probe until real time caught up.

TermTile has the identical launch-only design. Its dot appears because it gets relaunched after an
update, not because it re-checks.

## 3. Cause two: any probe silently deleted the app's launch behaviour

`LaunchDelegate.onLaunch` was a single closure, assigned in THREE places - the real launch work, the
HUD probe, and the menu probe. Last writer won.

So running any probe replaced the app's real launch work. The microphone request and the update
check simply did not happen, while the menu still rendered and looked completely normal.

That is worse than a bug in a probe: it is a bug in the INSTRUMENT, and it made the menu probe
structurally incapable of observing anything that happens at launch. It was found by trying to
photograph the dot coming from the real appcast and getting no dot **and no log lines at all**.

Now a list, appended to.

## 4. Cause three, and the one that actually hid the feature: `AppActions` was not `@Observable`

`AppModel` is `@Observable`. `AppActions` - which owns `updateAvailability` and is read by all three
marks - was a plain `@MainActor final class`.

`updateAvailability` is written when Sparkle's passive check comes BACK, seconds after the menu has
already rendered. With no observation SwiftUI was never told, so the menu-bar icon and the `...`
kept drawing the value they had at render time: `.unknown`, which is no dot.

**The indicator could therefore never appear in real use, on any surface, no matter how correct the
rest of it was.**

### Why #138 passed anyway

Its render check ran `PUSHTEXT_MENU_PROBE_UPDATE=1`, which sets `updateAvailability = .available`
**before the view is built**. The screenshot showed a dot. It could only ever show a dot.

A test that sets the value before the render cannot detect a missing update notification. This is
the same defect class as the vacuous tests planting has been catching all week, except it was a
vacuous SCREENSHOT - and rendering is the technique this project reaches for when it wants certainty.

## 5. Proof, end to end, with nothing forced

An app built genuinely older than the published release - `PUSHTEXT_BUILD_NUMBER=100
SHORT_VERSION=0.2.9`, against the live appcast advertising 0.3.1 (build 104) - launched with
`PUSHTEXT_MENU_PROBE=1` and **no** `_UPDATE` flag:

```
TRACE found 0.3.1
TRACE cycle-clean
```

and the `...` button carries the orange dot in the screenshot.

Two false starts are worth recording, because both looked like product bugs:

- **The first attempts screenshotted after 5-7 seconds and saw no dot.** The appcast round trip
  takes longer than that. "No dot" and "not finished yet" render identically, which is the
  zero-checks-versus-all-green failure again.
- **A dev build at HEAD reports no update, correctly.** Sparkle compares `CFBundleVersion`, which is
  `git rev-list --count`. The dev build and the release were both **104**, so "you are current" was
  the right answer to a question I had asked badly.

## 6. What this does NOT show

The six-hour timer has not been observed firing; only the policy that governs it is tested, and the
timer itself is AppKit plumbing. The menu-open path IS observed - the trace shows the second refresh
being suppressed by the quiet period, which is the policy running in the real app.

The dropdown ROW's mark still has not been rendered in place - see `task161` and `task138`. The
`@Observable` fix applies to it identically, since all three marks read the same property.
