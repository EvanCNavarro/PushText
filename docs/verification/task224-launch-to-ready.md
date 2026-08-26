# Launch to menu-bar ready (#224)

The third of the three unmeasured dimensions named while answering *"what is bloated, what is
inefficient, and how can we tell?"* - and the one a person actually feels, because **Launch at login**
means it happens every morning.

## Measured

Exec to the status item having a real frame, which is the moment it can be clicked. Three samples per
build, because one is noise and the first is always cold.

| run | debug | release |
|---|---|---|
| 1 (cold) | 894 ms | 834 ms |
| 2 | 585 ms | 569 ms |
| 3 | 570 ms | 578 ms |

## What the comparison says

**Debug and release are indistinguishable.** A release build compiles our Swift with optimisation and
a debug build does not, so if our code dominated launch the two columns would differ. They do not -
which places the time in dyld and framework initialisation (AppKit, SwiftUI, AVFoundation), not in
anything this project wrote.

That is the useful finding: **there is nothing here to optimise.** Roughly 570 ms warm, 850 ms cold,
and the cold number is the one that applies at login.

## No permanent gate, and why

Recording this on every run would need a readiness marker in PRODUCTION code - the measurement above
borrows the `#209` probe's status-item poll, which only exists under a probe env. That is real cost
for a regression that is both unlikely (the time is not ours) and already partly covered: the
footprint line added to `test-packaged-app.sh` catches "the app got heavier" in the adjacent
dimension, and the smoke's existing liveness poll catches "the app stopped starting at all".

The obligation here is discharged by the measurement, not deferred: the question was whether launch
is slow enough to matter, and the answer is no, on numbers rather than on feel.

## What this does not measure

Time from **login** to ready, which includes `SMAppService` deciding to start the app at all - that is
macOS's schedule, not ours, and is part of what #206 was closed without measuring.
