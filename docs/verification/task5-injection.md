# Issue 5 verification — TextInjector (pasteboard + synthetic Command-V)

Date: 2026-08-22. Machine: macOS 15.1, Xcode 16.2, Swift 6.0.3.

> This file was cited by the issue-5 commit and PR before it existed. The `search-before-file-check`
> hook blocked the compound command that would have written it, and a PreToolUse hook blocks the
> WHOLE command — so the heredoc never ran while the citation shipped. Caught by reading the merge
> diff and noticing the file absent. `.engine/checks/cited-docs-exist.sh` now fails closed on it.

## Why not the Accessibility API

`AXUIElement` text writes return `.success` while silently doing nothing in Electron apps, Chrome,
VS Code, Google Docs and Pages, and are barred outright under the App Sandbox. Five of five surveyed
open-source dictation apps use the pasteboard route (docs/research/04 sec 3). Murmur treats AX as
primary with pasteboard as fallback; that is inverted.

## The paste keycode is resolved, not hard-coded

Hard-coding `kVK_ANSI_V` (9) breaks on Dvorak-QWERTY-Command, where the layout reverts to QWERTY
positions **only while Command is held** — so the answer depends on whether the modifier is applied.
It is resolved through `UCKeyTranslate` with `cmdKey`.

Measured on this machine's layout:

```
mods=0 -> keycodes producing 'v': [9]
mods=1 -> keycodes producing 'v': [9]
```

Identical here, because this is QWERTY. That the two queries agree on THIS layout is exactly why a
hard-coded 9 would have looked correct forever and failed on someone else's machine.

## Clipboard mechanics, against the real NSPasteboard

```
INJECT_PROBE trusted=true
INJECT_PROBE pasteKeyCode=9
INJECT_PROBE seeded=PUSHTEXT-SENTINEL-A changeCount=46
INJECT_PROBE decision=restore
INJECT_PROBE restored=true value=PUSHTEXT-SENTINEL-A
INJECT_PROBE foreignDecision=skipForeignWrite
INJECT_PROBE foreignPreserved=true
```

Both branches exercised on the live pasteboard: restore when still the last writer, and leave a
foreign write alone. The second is the one that matters — restoring blindly would destroy whatever
the user had just copied.

## End to end, into a real application

TextEdit opened, a marker injected, the document read back, then closed without saving:

```
INJECT_PROBE inject=sent text=pushtext-final-1787385562
INJECT_PROBE clipboardRestored=true value=PUSHTEXT-SENTINEL-A
MATCH: 'pushtext-final-1787385562'
```

The text arrived intact AND the user's clipboard came back.

## The settle delay is load-bearing — planted, not assumed

The paste is asynchronous: the target app reads the pasteboard when it processes the key event,
which has not happened when `post` returns. Restoring too early hands it the OLD contents.

Planted `pasteSettleDelay = 0.0` and repeated the TextEdit run:

```
  expected marker : pushtext-plant-1787385390
  TextEdit got    : PUSHTEXT-SENTINEL-A
  -> PLANT CAUGHT: wrong text pasted, the settle delay is load-bearing
```

TextEdit received the restored sentinel instead of the dictated text — precisely the user-visible
bug (you speak, and your previous clipboard gets pasted).

## What this did NOT verify

- **The delay is a race, not a guarantee.** 0.12 s was enough for TextEdit on an idle machine. A
  slower or busier target could read the pasteboard after the restore, reproducing the planted
  failure in production. There is no observable signal for "the target has read the pasteboard", so
  it cannot be closed by waiting smarter. Tracked as #27.
- **Only TextEdit was tested.** The apps where AX writes fail — Electron, Chrome, VS Code, Slack —
  are the reason this path exists, and none was exercised. A native app succeeding proves the least
  interesting case. Tracked as #27.
- **Secure Input.** Injection into a password field was not attempted; synthetic keystrokes are
  expected to be blocked there, unlike `flagsChanged`, which issue 20 showed survives.
