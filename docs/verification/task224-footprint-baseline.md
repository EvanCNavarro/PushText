# Memory has no baseline, so no number about it can mean anything (#224)

The "how can we tell" half of Bobby's *"what is bloated, what is inefficient, and how can we tell?"*,
for memory.

## The measurement, and why it is not an answer

On the running app: **33 MB** physical footprint, **41.9 MB** peak, dominated by 18 MB
`MALLOC_SMALL` and ~4 MB of graphics surfaces.

Whether that is bloated is **unanswerable from that number alone**. It is only meaningful against a
baseline - an empty SwiftUI `MenuBarExtra` - or a trend. Neither existed, so every claim about
PushText's memory was a feeling with a number attached.

## The obvious instrument lies

`ps` RSS reported **89.8 MB** for the same process. RSS counts the shared AppKit and SwiftUI pages
every app on the machine maps, so it overstated the app's own cost by 2.7x. Had that been the number
reported, PushText would have looked badly bloated and someone would have gone optimising nothing.

`footprint -p` is the honest one, and the gap between them is the whole reason to name which tool
produced a number.

## What was added

`scripts/test-packaged-app.sh` records `footprint -p` for the app it already launches, and prints it
in the OK line. Every packaged run now leaves a number behind, which is what turns a value into a
trend.

**Recorded, not asserted.** A threshold needs a baseline this project does not have, and a limit
picked by feel is one that gets raised the first time it fires rather than investigated.

## A parse bug that would have shipped silently

The first version used a positional `awk` on:

```
PushText [92295]: 64-bit    Footprint: 33 MB (16384 bytes per page)
```

and printed `footprint=64-bit Footprint:`. A **value-shaped string** - it would have appeared in
every release smoke, in the position a number belongs, and never once looked like an error.

It now splits on the label rather than counting columns, and validates the shape before accepting it:
anything not matching a digit followed by KB/MB/GB is recorded as `unavailable`, which is honest
where a wrong value is not.

## Measured

| | |
|---|---|
| freshly launched, in the smoke | **16 MB** |
| after hours of use with the menu opened | **33 MB** |

So ordinary UI use roughly doubles it - the kind of thing only a per-release number surfaces.

## What this does not answer

- **Is 16 MB reasonable?** Still open. That needs a comparison app, which is separate work.
- **Launch-to-ready** is unmeasured.
- **Compaction's cost during a dictation** (#222) is unmeasured.
