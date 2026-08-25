# Task 158 - Delete History does what it says, and the race I predicted is not there

Measured 2026-08-24 on macOS 26.6.2, Swift 6.3.

Delete History shipped in the overflow menu and had never been driven. This is what driving it
showed, including the part where my own diagnosis was wrong.

---

## 1. What the menu item actually does

`AppActions.clearHistory()` puts up an `NSAlert` (Delete / Cancel), and on Delete calls
`JSONLHistoryStore.clear()`, which is `FileManager.removeItem(at:)`. It removes the FILE. It does
not truncate it and it does not touch the containing directory.

That matters because `append` writes through `FileHandle(forWritingTo:)`, which fails on a path that
does not exist. The next dictation after a delete therefore depends entirely on the atomic-write
fallback beneath it.

## 2. Does recording survive the delete? Yes - measured, not read

    PROBE exists-after-clear=false
    PROBE loaded=["after"]
    Test run with 1 test in 1 suite passed

The file is gone, and the following append recreates it. The fallback carries the whole sequence.

## 3. The hypothesis I formed, and the run that killed it

`PushTextApp.swift:70` builds the `JSONLHistoryStore` the capture pipeline appends through.
`AppActions.swift:150` built a SECOND one to delete with. Two `NSLock`s guarding one file, and
`clear()` can be clicked while a dictation is finishing - which reads exactly like a torn-file bug.

Two hundred concurrent appends racing a `clear()`, five rounds each, both configurations:

    PROBE separate-instances torn-lines=0
    PROBE shared-instance torn-lines=0

**No tearing, and the second lock changes nothing.** The reason is POSIX, not luck: `removeItem`
unlinks the name while the writer holds an open descriptor to the inode. The racing append lands in
the unlinked inode and disappears with it. Records vanish rather than tear - and vanishing is what
the user asked for when they clicked Delete.

So there is no defect here and no fix was made. Recorded because the two-lock shape is genuinely
suspicious on sight, and the next person to notice it - including me - deserves the measurement
rather than a second afternoon.

## 4. What is now covered

`Recording survives a delete instead of silently stopping` in `JSONLHistoryStoreTests`.

Its value was established by planting, not assumed. Make `clear()` leave the path unwritable - a
plausible shape for a future "delete more thoroughly" change - and the other five tests in the file
all still pass, `clear() removes the history` included, because the path does read as empty
afterwards:

    ✔ clear() removes the history
    ✔ Appends accumulate instead of replacing the file
    ✔ The cap keeps the most recent entries
    ✔ Concurrent appends do not tear each other's lines
    ✘ Recording survives a delete instead of silently stopping

It reads as empty forever, which is the failure: the user deletes their history once and PushText
stops recording, with a menu that still says it is listening.

## 5. What this does NOT show

The alert itself is unverified by any automated check - `runModal()` blocks, and nothing drives it.
Cancel is guarded by `alertFirstButtonReturn` and was exercised by hand only. The measurements above
all call `clear()` directly, so they prove the STORE behaves; they do not prove the button is wired
to it.
