# Every clean update check was recorded as FAILED (#241)

Found while investigating a different report (the dictation overlay). Reading the running app's log
turned up a defect nobody had reported, because its only symptom is a wrong indicator.

## The observation

`log show --predicate 'subsystem == "dev.ecn.apps.pushtext"' --info`, from the installed 0.6.10:

    20:09:56.002997  update check: none found
    20:09:56.044114  update check FAILED: You're up to date!

Six occurrences in one day, one per check. Both lines describe the SAME check, 42 ms apart. The
second contradicts the first and wins, because it is the one that sets state.

## The cause, measured

Sparkle delivers "no update found" to `didFinishUpdateCycleFor:error:` as an `NSError` in
`SUSparkleErrorDomain`, and `UpdateWatcher` treated any non-nil error as a failed check. The
outcome that means SUCCESS arrives on the error path.

The codes were read off a binary linked against the vendored framework, not off the header:

    domain=SUSparkleErrorDomain
    noUpdate=1001
    cancelled=4007

`SUErrors.h:41` agrees, but a header is a claim about what the framework contains and the run is
what it does.

## Why it shipped

The comment above that method argues the OPPOSITE mistake, and argues it correctly: a failed check
must not render as "up to date", because a check that never ran and a check that found nothing
otherwise look identical (#170). The code overcorrected the moment it turned that into "every error
is a failure", and made *up to date* render as *broken* instead.

Nothing caught it because `UpdateIndicatorTests` covers how each `UpdateAvailability` **renders**.
There was no test of the mapping **onto** one - the seam where the defect lives.

## The fix

`UpdateWatcher.isCheckFailure(domain:code:)`, pure over its two arguments so it is testable without
driving Sparkle. `SUNoUpdateError` is a successful check with a negative answer;
`SUInstallationCanceledError` is the user declining. Everything else is a failure, including any
error outside Sparkle's domain.

On the no-update path it changes NO state: `updaterDidNotFindUpdate` already owns that answer.
Setting it in both places would be harmless today and would quietly become the authority if that
callback ever stopped firing.

## A width mismatch that compiled, and why it is not a bug

`SUError` is `NS_ENUM(OSStatus, SUError)`, so `rawValue` is `Int32` while the classifier takes `Int`.
The comparison inside the classifier compiles anyway - Swift defines heterogeneous `==`/`!=` across
`BinaryInteger`, and they compare by VALUE. The tests need an explicit `Int(...)` only because
passing an argument is a conversion rather than a comparison.

Checked rather than waved through: a width mismatch that silently compiled could have left the test
suite comparing different constants than the code, which is a green that proves nothing.

## Battle test

Both directions, because the obvious wrong fix here is as bad as the bug:

| planted implementation | expected | got |
|---|---|---|
| `return true` - the original, every error is a failure | **red** | 3 failures: no-update, cancelled, and the observed error |
| `return false` - never a failure | **red** | 6 failures across both discriminator tests |
| the real implementation | green | 5 tests pass |

The `return false` row is the one worth keeping: without it, "never report a failure" would satisfy
the suite and reintroduce #170 from the other side - the user told they are current while the app
has no idea.

## What is still NOT covered

The delegate wiring. `isCheckFailure` being right is necessary and not sufficient; reaching
`updater(_:didFinishUpdateCycleFor:error:)` in a test needs a live `SPUUpdater` with a host bundle.
The classifier is the seam that was reachable, and its absence is what let this ship.

The real proof is the log line changing on the next release. Until then this is a fix whose evidence
is a unit test and a measurement, not an observed behaviour change in the running app.

## State after

461 tests in 68 suites pass, 0 lint violations across 99 files, all 15 `.engine/checks` green.
