# The history viewer re-reads when it becomes key (#207)

#202 shipped two refresh paths and only measured one. The notification chain was driven end to end
and screenshotted; `windowDidBecomeKey` - the half that covers a change made OUTSIDE PushText - was
wired and never exercised. #205 corrected the write-up to say so. This is the measurement.

## The filed dependency was wrong, and one read showed it

#207's body claimed moving key focus "likely needs `cliclick` or an `NSApplication` activation hook
added to the probe". That was inferred, not checked. The menu probe window uses
`orderFrontRegardless()`, which deliberately does NOT take key - so the viewer had held key through
every earlier probe run, and the app can take key from itself in-process with an ordinary `NSWindow`.
No external tool was needed by anything except the assumption.

## An unbundled binary cannot do this at all

First run, against `.build/debug/PushText`:

```
MAKEKEY before: isKey=false appActive=false delegate=true
MAKEKEY after:  isKey=false
```

No delegate callback, because the window never became key - an inactive app cannot make one key, and
the SPM binary has no bundle to activate. The probe reported `VERDICT: NOT CONFIRMED`, which was true
of the environment and false about the code. Believed at face value it would have sent someone to
"fix" a working delegate.

Against a bundle built by `scripts/build-app.sh`:

```
DELEGATE becomeKey fired      <- at open
DELEGATE resignKey fired      <- key stolen
MAKEKEY before: isKey=false appActive=true delegate=true
DELEGATE becomeKey fired
MAKEKEY after:  isKey=true
```

The script now refuses to be pointed at the binary in its own header, because the failure it produces
looks exactly like a real one.

## The instrument had to be replaced twice

**A whole-window pixel hash cannot answer this question.** The first control compared `before` and
`mid` and reported a failure: the window HAD changed. Looking at the frames, the content was
identical at 2 dictations - what changed was the title bar, dimmed because the window had lost key.
The instrument could not separate "the list gained a row" from "the chrome greyed out".

**The crop that was supposed to fix it silently did nothing.** `sips -c 824 1120 --cropOffset 80 0`
exits 0, prints the output path, and returns an image still 904px tall. The cropped hashes came back
byte-identical to the uncropped ones, which is the only reason it was caught.

So the verdict is read from the model instead: the app reports how many rows the list is showing at
each stage. That is the quantity the question is actually about.

## Measured

`scripts/probe-history-become-key.sh` against a bundle:

```
viewer open, 2 records on disk
key taken away - the viewer is no longer key
edited from outside; 3 records on disk

rows while unkeyed, after the outside edit : 2
rows once the window became key           : 3
CONTROL ok     - an outside edit alone did NOT update the list
RESULT  ok     - becoming key re-read the file and picked up the new record

VERDICT: become-key refresh CONFIRMED
```

The control is load-bearing. The edit is a raw append to the file, NOT through `JSONLHistoryStore`,
so no `.historyDidChange` is posted - and the window must therefore still show 2 while it sits
unkeyed. If it already showed 3, something else refreshed it and the result line would prove nothing
about becoming key.

## The probe was made to fail

`model?.refresh()` removed from `windowDidBecomeKey`, bundle rebuilt, same probe:

```
rows while unkeyed, after the outside edit : 2
rows once the window became key           : 2
CONTROL ok     - an outside edit alone did NOT update the list
RESULT  FAILED - expected 3 rows after becoming key, got 2

VERDICT: NOT CONFIRMED
```

The control still passes and only the result flips, which is what shows the two halves are measuring
different things. Source restored byte-identical afterwards (`diff -q`).

## What this does NOT prove

That a MOUSE CLICK makes the window key. The probe calls `makeKeyAndOrderFront`, so what is
established is the chain from a window becoming key to the list re-reading. Whether a physical click
produces that AppKit event is AppKit's business and not this app's.
