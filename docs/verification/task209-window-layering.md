# Windows opened from the menu are no longer buried under it (#209)

Bobby hit this twice. First with the Sparkle update alert, whose **Install** button was covered by
the menu panel, leaving only "Skip This Version" reachable. Then with Dictation History, which he
photographed sitting behind the same panel.

## Measured, not cited

The panel and every window the app opens are at different window levels:

```
_TtGC7SwiftUI18MenuBarExtraWindowVS_7AnyView_   level=101
NSStatusBarWindow                               level=25
NSWindow   (the history viewer)                 level=0
```

101 against 0. `activate(ignoringOtherApps:)` and `makeKeyAndOrderFront` decide key and front WITHIN
a level, so neither could ever have fixed this. The panel has to close - which is also what a menu
does when you pick an item.

Sparkle's own `SPUStandardUserDriverDelegate.h` describes half of it independently: for background
applications the standard driver shows the alert "behind other running applications or behind the
app's own windows if it's currently active." PushText is `LSUIElement`, so it is a background app by
that definition.

## The first fix shipped a worse bug, and the probe caught it

`orderOut(nil)` on the panel window hid it correctly - and left SwiftUI believing the panel was still
open, so the next click on the menu-bar icon toggled it "closed" and nothing appeared:

```
t=2..5   PANEL          panel open
t=6      OURWINDOW      history opened, panel gone      <- the fix worked
t=9      reopening + panelClicked
t=9..14  OURWINDOW      the panel never came back       <- the menu-bar icon is dead
```

A dead menu-bar icon is worse than a window in the wrong order. The fix became: close the panel the
way a person does, by clicking the status item, which toggles the same state SwiftUI is tracking so
the two cannot drift. The visibility guard is what makes it safe to call unconditionally - clicking
while the panel is closed would OPEN it.

```
t=2..5   PANEL              panel open
t=6..8   HISTORY            panel dismissed, window on screen
t=9..14  PANEL + HISTORY    icon clicked again, panel back
```

## How the panel gets opened for the probe, and the near-miss that changed it

The first probe drove the real mouse to the status item's screen coordinates. On this multi-display
Mac the item is at **x=-4607**; `cliclick` did not honour the negative coordinate and the click landed
on the **Apple menu**, with **Restart** highlighted. Nothing was clicked in it and Escape was sent
immediately, but the approach was abandoned there: a coordinate conversion that fails silently is not
worth a layering measurement, and the blast radius included restarting the machine.

The probe now asks the status item's own button to click itself, in process. There are no coordinates
to get wrong.

## Scope - every presenting action, not just the update alert

Six actions put a window or dialog on screen, and all six now dismiss the panel first: `showHistory`,
`clearHistory`, `revealHistory`, `checkForUpdates`, `confirmUninstall`, `editDictionary`. The bug was
reported against two of them; it was latent in the rest, and only invisible because those windows
open centred while Bobby's panel sits at the right-hand edge.

## What is tested, and what only the probe can catch

`MenuPanelTests` pins the window class name the matcher looks for. That is the fragile part: SwiftUI
mangles the class as `_TtGC7SwiftUI18MenuBarExtraWindowVS_7AnyView_`, and if it is ever renamed,
`dismiss()` finds nothing, does nothing, and the bug returns **in silence** with no test failing.

`scripts/probe-window-layering.sh` is the real gate. It measures levels on the running app and fails
closed - a run where the panel never opened reports "SETUP FAILED", not a pass, because there would
have been nothing to dismiss.
