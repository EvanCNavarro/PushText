# The history file grows without bound, and reading it costs the whole file (#222)

Found while answering Bobby's *"what is bloated, what is inefficient, and how can we tell?"* - by
building the instrument instead of guessing.

## The read-cost curve, before

`HistoryPerfProbe`, five samples per size:

| records | file | decoded | `changeStamp()` | `load()` |
|---|---|---|---|---|
| 23 | 4.6 KB | 23 | 0.07 ms | 0.34 ms |
| 500 | 101 KB | 500 | 0.07 ms | 6.19 ms |
| 5,000 | 1.0 MB | 500 | 0.07 ms | 25.15 ms |
| 20,000 | 4.1 MB | 500 | 0.06 ms | **88.10 ms** |

Two readings:

- **`changeStamp()` is flat.** 0.07 ms at every size, so #202's cheap-check design does what it was
  built for - an unchanged file costs one `stat` however big it is.
- **`load()` scales with the FILE, not the display.** `decoded` stays pinned at 500 while the cost
  grows 260x, because the trim happens in memory after reading everything.

`load()` trimmed and never wrote back, so the 500 was a display cap and the file grew forever.
`clear()` deleting it was the only thing that ever shrank it.

## The fix

Compact in `append()` - the write path - once the file passes 512 KB, with an atomic write.

- **In `append()`, never in `load()`.** The viewer reaches the store through `HistoryReading`
  precisely so it cannot rewrite the file; compacting on read would hand it that power anyway.
- **The trigger is a `stat`, not a read.** Reading the file on every append to decide whether it is
  too big would BE the cost being removed.
- **It does not reintroduce what JSONL avoids.** That objection was to rewriting on EVERY append; at
  512 KB this runs about once per fourteen hundred dictations, and the write is atomic so a crash
  cannot truncate the history.

## The after-measurement I nearly got wrong

Re-running the size table gave **identical numbers** - 88.12 ms at 20,000. Correctly so: that table
writes files DIRECTLY and never calls `append()`, so compaction never fires. It is a fine read-cost
curve and it **cannot distinguish fixed from unfixed**. Reporting it as an after-measurement would
have been a green that meant nothing.

The instrument had to drive the write path:

| after 20,000 dictations through `append()` | before | after |
|---|---|---|
| file on disk | 4,088,890 B | **289,665 B** |
| `load()` | 88.10 ms | **9.93 ms** |

14x smaller, 8.9x faster, and bounded - it stops growing rather than merely growing slower.

## Tests, and the trap one of them exists for

`trim` joins lines WITHOUT a trailing newline. A compaction that forgets one makes the next append
land on the same line, merging two dictations into a record that `decodeFile` then silently skips.

| Planted | Caught by |
|---|---|
| compaction drops the trailing newline | "a dictation appended after compaction is a separate record" |
| compact on every append, ignoring the threshold | "a small file is left alone" (same inode) |

One test had to be rewritten before it meant anything. "Compaction keeps the newest records"
originally asserted on `load()` - which has always trimmed to the newest in memory - so it **passed
with no compaction at all**. It now reads the FILE.

A second assertion was wrong arithmetic rather than a wrong idea: it expected `load().count` to reach
`limit + 1`, which the cap makes impossible. What distinguishes a merge is that the joined line is
unparseable and gets skipped, so the count drops BELOW the cap and the last record is the wrong one.

## What this does not cover

The 512 KB threshold is a measured trade, not a tuned one: it keeps `load()` under ~13 ms at the
worst case while making compaction rare. Nothing measures compaction's own cost during a dictation -
it is an atomic write of ~280 KB, expected to be a few milliseconds, and it happens on the append
path rather than while the user waits for text. Unmeasured is unmeasured.
