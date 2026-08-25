# Task 164 - Proving a menu item does what its label says

Measured 2026-08-25 on macOS 26.6.2.

---

## 1. The gap

`menuActions()` built `[MenuAction]` inline: a title and a closure written side by side, six times.
Everything those closures CALL was covered - the history store, the uninstaller, the dictionary
editor, the update check. The association between a TITLE and its effect was covered by nothing.

Pointing "Delete History" at `confirmUninstall()` would have passed `swift test`, `swiftlint`, all
eleven `.engine/checks` and the packaged smoke. Two of the six items are destructive and a third
quits without asking.

## 2. Why it had never been tested

The closures call `NSAlert.runModal()`, `NSWorkspace` and `NSApplication.terminate`. A test that
pressed one would block forever or genuinely quit the test process. That is not an excuse for the
gap, it is the design constraint the fix had to satisfy.

## 3. The fix: make the pairing DATA

`MenuItemKind` carries the title, icon and destructive mark. `MenuDispatch.perform` is the ONE place
a kind is paired with an effect, and `MenuEffects` gives each kind a named method. Both halves are
assertable without AppKit: a spy records which effect ran, and nothing real happens.

`MenuDispatch.actions` builds the menu from the kinds, so the array literal that used to hold the
pairing no longer exists.

## 4. The mis-wiring that appeared WHILE fixing this

Naming the protocol requirement `uninstall()` failed to compile - and the reason is the whole issue
in miniature. `AppActions` already had a **private `uninstall()` that trashes the app immediately**,
alongside `confirmUninstall()`, which asks first. A requirement called `uninstall()` can bind to the
non-confirming one, and the menu item would skip its own confirmation.

Renamed to `beginUninstall()`. The compiler caught it here only because the name collided; had the
private method been called anything else, the swap would have compiled silently and looked correct.

## 5. Five plants, and the one that exposed a tautology

| plant | result |
|---|---|
| `Delete History` -> uninstall | **FAIL** - the case this exists for |
| `Quit` -> uninstall | **FAIL** |
| a title changed under the user | **FAIL** |
| destructive mark moved to Quit | **FAIL** |
| `View History` given a trash icon | **passed** |

The icon assertion was `actions.map(\.systemImage) == kinds.map(\.systemImage)` - **both sides read
from the same source**, so changing an icon changed both and the comparison could never fail. It was
a thing compared to itself. Re-pinned to literals, the plant fires.

That is the fourth self-referential or vacuous assertion caught by planting in this session, and the
second where the plant found the TEST rather than the code.

## 6. What this does NOT show

The menu still renders through `MenuContent`, and the packaged smoke drives it (`menu: rendered and
exited cleanly`) - but the smoke evaluates the view, it does not click an item. Nothing here proves
that pressing "Delete History" in the real popover reaches `clearHistory()`; it proves that the
pairing the popover is built from is correct, which is the part that was unguarded.

`quit` and `beginUninstall` are still never executed in a test, by design.
