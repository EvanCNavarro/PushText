# Task 27 - Injection into the apps that motivated the approach

**The shipped 120 ms settle delay is adequate for Chrome, VS Code and Slack.** The measured
boundary is 40 ms, so the margin is about 3x. Below that it is a genuine RACE, not a threshold:
20 ms passes some runs and fails others in the same app.

Measured 2026-08-23 on macOS 26.6.2, real synthetic Command-V into live applications.

---

## 1. Why this needed doing

#5 verified injection against TextEdit only, and said so: *"The apps where AX writes fail -
Electron, Chrome, VS Code, Slack - were not tested. A native app succeeding proves the least
interesting case."* Those are the apps that motivate the pasteboard approach in the first place.

## 2. Method, and why it is shaped this way

Per app: focus a text field, stage a unique marker, post Command-V through the real
`PasteboardTextInjector`, then read back what landed.

**Readback is select-all + copy + `pbpaste`, not an accessibility read.** Electron editors expose a
canvas rather than a text field, so an AX read would fail for reasons unrelated to whether the paste
worked - which is precisely the confusion this test exists to remove.

**The comparison is CONTAINMENT of a unique marker, not equality.** Equality made the harness score
its own flakiness as product failure: when a select-all did not take, pastes accumulated and an
otherwise successful injection read as a mismatch. A per-run unique marker is unaffected.

Three outcomes are distinguished, because they mean different things:

| result | meaning |
|---|---|
| marker present | the paste landed |
| `PUSHTEXT-SENTINEL-A` present | the app read the pasteboard AFTER the clipboard was restored - the bug |
| neither | the harness lost focus; not evidence about the app |

Targets: Chrome's omnibox, a real file open in VS Code (`AXTextArea` focus confirmed before
measuring), and **Slack's quick-switcher rather than the message composer** - nothing typed there
can be sent to a real channel.

## 3. The instrument was validated before it was trusted

TextEdit, whose behaviour #5 already established, in both directions:

```
TextEdit @ 120ms -> PASS
TextEdit @   0ms -> FAIL got=[PUSHTEXT-SENTINEL-A]
TextEdit @ 120ms -> PASS
```

The 0 ms failure reproduces #5's exact signature, so the harness can see the defect it is looking
for rather than only confirming success.

## 4. Results, n=3 at each point

```
             20ms   40ms   120ms
  chrome     PPF    PPP    PPP
  vscode     PPP    PPP    PPP
  slack      PFF    PPP    PPP
```

Sweeps at 0 ms failed in every application.

- **0 ms fails everywhere.** The delay is load-bearing in all four apps tested, not just TextEdit.
- **20 ms is a coin flip** for Chrome (2/3) and Slack (1/3). Same app, same delay, different result -
  which is what makes this a race rather than a threshold, and is the strongest evidence that a
  "fast enough" constant can never be proven correct.
- **40 ms and 120 ms are reliable** for all three, 3 of 3 each.

## 5. What this means for the restore strategy

#27 listed two alternatives to the fixed delay: hold the restore until the dictation session ends,
or verify via AX and retry. **Neither is justified by this evidence.** The shipped constant clears
the measured boundary by 3x in the three applications that motivated the concern, and both
alternatives carry real costs - holding the clipboard hostage across a session is worse for the
user than a 120 ms wait, and an AX verification pass fails on exactly the Electron targets this was
worried about.

The honest position: the delay remains a race that cannot be PROVEN safe, and it is now measured
rather than assumed in the apps that matter.

## 6. What this does NOT establish

- **An idle machine.** Every run was on a quiet system. The failure mode is a busy target reading
  late, so load is the condition most likely to break it, and it was not simulated.
- **Three apps, one field each.** Chrome's omnibox is not a web page textarea; Slack's
  quick-switcher is not its composer. A heavier surface could behave differently.
- **No web content.** A `contenteditable` in a page, which is what a browser dictation user is
  actually typing into, was not tested.
- **Nothing about correctness of the restore itself.** That the user's clipboard comes back is
  covered by `ClipboardRestore` and #5, not re-measured here.
- **The harness misled me twice before it was right.** A window-closing cleanup destabilised the
  next VS Code run, and an equality comparison scored accumulated pastes as failures. Both produced
  confident-looking "VS Code fails at every delay" output that was entirely artifact. The numbers
  above are from the third design, after focus was verified as `AXTextArea` and a typed-then-read
  round trip confirmed the readback path.
