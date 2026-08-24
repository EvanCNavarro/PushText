# Task 18 - Context-aware formatting, and why it was closed unbuilt

**The one problem #18 ever named does not occur.** Measured 2026-08-23 on macOS 26.6.2.

---

## 1. What #18 actually specified

Nothing, beyond a stale `blocked-by: #14` (closed long ago). `.engine/BACKLOG.md` repeats that line
and adds nothing. The only concrete requirement anywhere is `PLAN.md` Phase 3:

> Context-aware formatting (terminal -> no smart quotes, etc.)

So the whole specification is one example - suppress smart quotes when dictating into a terminal -
plus an "etc." that names nothing.

## 2. That example requires typographic characters to exist. They do not.

**The recognizer emits straight quotes.** Across **80 real transcripts** in
`~/Library/Application Support/PushText/history.jsonl`:

```
straight apostrophes ('): 7
curly apostrophes (’): 0
```

with examples like `I'm`, `There's`, `that's`. Zero occurrences of any curly quote, en dash, em
dash or ellipsis across all 80.

**Cleanup emits pure ASCII.** Driving the real on-device model through `CleanupProbe`:

```
raw     = "dont worry i said its the teams call not mine"
cleaned = "Don't worry, I said it's the team's call, not mine."
non-ASCII characters in the cleaned output: NONE
straight ' count: 3   curly count: 0
```

Checked at code-point level rather than by eye, because a curly and a straight apostrophe are nearly
indistinguishable in a terminal.

**The receiving app does not convert them either.** macOS smart-quote substitution is enabled on this
machine (`NSAutomaticQuoteSubstitutionEnabled = 1`), and it applies to TYPED input, not to a paste:

```
pasted into TextEdit: "don't stop the team's work"
non-ASCII after paste: NONE - substitution did not fire on paste
```

That was the last mechanism by which a smart quote could reach a user's document, since PushText
injects by pasteboard.

## 3. What this rules out, and what it does not

Ruled out: the specific defect #18 exists to fix. Text leaves this app as ASCII, and arrives as ASCII.

NOT ruled out:

- A different locale or a future `SpeechTranscriber` that formats differently. All 80 transcripts are
  en-US on one machine.
- Some *other* per-app need that nobody has written down. "etc." covers an empty set today: nothing
  in the issue, the backlog, or the plan names a second case, and nothing in the code reads a bundle
  identifier - `grep -rn "bundleIdentifier" Sources/` returns nothing outside comments about the
  frontmost app as an injection target.

## 4. Why it was closed rather than re-scoped

Building a per-app formatting framework now would mean inventing requirements to justify it. The
repo's own code principles forbid exactly that: "No speculative features, premature abstractions, or
unnecessary indirection. Solve the actual problem."

If a real per-app need appears, the right artifact is a new issue naming the OBSERVED problem - a
transcript that arrived wrong in a specific app - rather than this one, whose only example has been
measured away.
