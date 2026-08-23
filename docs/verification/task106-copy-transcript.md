# Task 106 - Copying the last transcript out of the menu

**The copy control writes PLAIN text, not the concealed form injection uses**, and all three of its
states were driven in the running app. Verified 2026-08-23 on macOS 26.6.2 through the packaged
`.app`.

---

## 1. Plain, deliberately

`PasteboardTextInjector.stage` marks every injected item transient, concealed and auto-generated so
clipboard managers do not archive dictated text (#41). That is correct for injection: the user never
asked for that text to enter their clipboard history.

A COPY button is that request being made explicitly. Reusing `stage` would hand the user text their
own clipboard manager is instructed to discard - a button that appears to work and does not. So
`copy` writes a plain string, and the two live side by side in one file precisely so the contrast is
visible where someone would otherwise call the wrong one.

The test that matters is not "copy writes the text" - `stage` does that too. It is that the two
differ in **exactly** the markers:

```swift
#expect(stagedTypes.subtracting(copiedTypes)
            == Set(PasteboardTextInjector.concealMarkers.map(\.rawValue)))
```

That assertion was watched failing against a `copy` implemented as a call to `stage`, which is the
mistake it exists to prevent.

## 2. Driven in the running app

`ImageRenderer` cannot open a popover, so this was verified by driving the real menu. Two synthetic
`CGEvent` clicks on the status item did nothing; the accessibility route worked, but only against
the right menu bar - `menu bar 1` is the application menu and the status item is on `menu bar 2`:

```
osascript -e 'tell application "System Events" to tell process "PushText" \
  to click menu bar item 1 of menu bar 2'
```

| state | observed |
| --- | --- |
| idle | boxed copy glyph, same size and treatment as the `...` overflow |
| after clicking | checkmark, `active` lifted border |
| after ~1.6 s | reverted to the copy glyph |

Clipboard read back immediately after the click:

```
clipboard AFTER: [Copy this transcript back out of the menu.]
clipboard info:  «class utf8», 42, «class ut16», 86, string, 42, Unicode text, 84
```

42 characters, matching the `injected chars=42` from the dictation that produced it - and the type
list contains **no** `org.nspasteboard.*` entries, which is the plain-copy claim checked rather than
asserted.

The developer's clipboard was empty before the run and was restored to empty afterwards.

## 3. `IconButton`, not `GhostIconButton`

The first version used `GhostIconButton`, the borderless variant, which made the copy control a
different size and hover behaviour from the only other icon control in the menu. `IconButton` is the
control the `...` overflow uses, and its own docstring names this trap: it owns its hover state "so
callers never re-wire it (the bug where the `...` was styled by hand)".

Corrected after Bobby pointed at the mismatch, and confirmed by rendering the two controls in the
same screenshot.
