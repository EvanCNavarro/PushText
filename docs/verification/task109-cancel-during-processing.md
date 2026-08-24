# Task 109 - Cancelling after the utterance ends

**Cancel is now accepted through `transcribing` and `cleaning`, and refused once the paste starts.**
Verified 2026-08-23 on macOS 26.6.2 through the packaged `.app`.

---

## 1. The decision, and what decided it

#109 asked whether cancel SHOULD work mid-processing. Yes, up to the paste:

- Nothing has been typed during `transcribing` or `cleaning`, so "do not type that" is still
  satisfiable. `.injecting` is genuinely too late.
- The window is no longer theoretical. With cleanup off it is ~200 ms (OBSERVED 158-275 ms, #94) and
  nobody can react to it - but cleanup is now a user setting (#103), and with it on the window is
  ~4 s (OBSERVED 3421-3559 ms). A user WILL reach for the key.

## 2. A defect the issue did not anticipate

`finishText` writes HISTORY inside the cleaning stage, before `.cleanupFinished` is applied. So a
cancel during cleaning would have recorded a transcript that was never typed - breaking the
invariant #97 established, that history equals what the user actually got.

Caught by writing the test first: `cancelDuringCleaningLeavesNoHistory` failed on the history
assertion before any fix existed, showing the recorded text.

The fix is a `shouldCommit` check inside `TranscriptFinisher`, placed AFTER the model call and BEFORE
the dictionary and history, because everything below that line is a commitment.

## 3. Why late completions are harmless

Once the machine is `.idle`, an in-flight `feed.finish` or cleanup that later applies
`.transcriptFinalized` or `.cleanupFinished` is IGNORED: both are handled only from their own
states, and `(_, .failure)` returns nil when idle. Verified by reading the transition table rather
than assuming - it is what makes cancelling a stage that is still running safe.

## 4. The HUD had to learn the same line

`.working` covered transcribing, cleaning AND injecting, so one phase spanned both the states that
accept cancel and the one that refuses it. Offering cancel across all of them would have put a dead
button on screen; hiding it across all of them would have hidden a live one.

`.inserting` is now its own phase. Cancel is drawn in every phase except that one, which is exactly
where the machine draws the line. A test asserts both halves - the machine's acceptance and the
driver's routing - because asserting only that the phases DIFFER would pass while the driver sent
`.injecting` to `.working`.

## 5. Real path

Cleanup enabled through the setting, then the HUD's cancel clicked during cleaning:

```
state recording -> transcribing
transcript chars=55
state transcribing -> cleaning
state cleaning -> idle
cancelled: capture closed, nothing injected
```

No `injected chars`. The document was empty. **History stayed at 62 lines**, before and after.

## 6. Plants

| plant | failing tests |
| --- | --- |
| cancel refused while processing | 9 |
| cancel accepted while injecting | 7 |
| commits a cancelled utterance (no `shouldCommit`) | 2 |
| driver shows cancel during the paste | 2 |
| none | 0 |
