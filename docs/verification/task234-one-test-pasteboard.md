# One pasteboard for the test suite (#234)

CI run [33174982445](https://github.com/EvanCNavarro/PushText/actions/runs/33174982445) failed on a
**docs-only** PR. Three tests in `Pasteboard conceal markers` timed out acquiring a named pasteboard.

## It was not the change, and that is measurable

| run | branch | Swift sources | result |
|---|---|---|---|
| [33174959734](https://github.com/EvanCNavarro/PushText/actions/runs/33174959734) | `master` | identical | green |
| [33174982445](https://github.com/EvanCNavarro/PushText/actions/runs/33174982445) | `docs/release-notes-0-6-9` | identical | **red** |
| rerun of the same commit | `docs/release-notes-0-6-9` | identical | green |

Same bytes, three runs, two answers. The PR added one file, `release-notes/0.6.9.md`.

## The bound was right; the load was not

This is #144 wearing the outfit #179 gave it. `NSPasteboard(name:)` reaches the pasteboard server
over mach, and on a headless runner that server is intermittently unresponsive - unbounded it took
the job down for ten minutes at a time, and `BoundedWork` turned that into a ten-second failure.
That part works and was not touched.

What #179 did not change is how many acquisitions the suite makes. `PasteboardMarkersTests` took a
**distinct named board per test** - seven of them - and Swift Testing runs tests in parallel, so all
seven hit a serial setup path at once.

The log shape fits a stalled server rather than seven independent coin flips: four acquisitions
returned, and the remaining three timed out at *the same instant*, 10.835s.

    ✘ "Copying for the user writes plain, UNMARKED text"    …test.copy         did not finish within 10.0s
    ✘ "Staging bumps the change count…"                     …test.changecount  did not finish within 10.0s
    ✘ "Copy and inject differ in exactly the markers"       …test.diff-copy    did not finish within 10.0s

**Correlation, cause unverified.** The wedge does not reproduce on a Mac with a live window server,
so there is no local red to turn green and no way to intervene on the variable. What is verifiable is
the exposure: seven concurrent acquisitions where one suffices.

## The change

One named board, acquired once inside a `static let`, with the suite `.serialized` so the tests do
not race on its contents. `copyAndStageDifferOnlyInMarkers` now writes the same board twice instead
of comparing two boards - the same discriminator, and one fewer confound.

Frequency, from the runs still queryable: 1 failure in the last 40 (~2.5%), against "roughly one run
in ten" for the pre-#179 hang.

## The first guard was vacuous, and planting is what showed it

The obvious runtime guard - count acquisitions, assert the count is 1 - was written first, and it
**passed on the deliberately broken version**. With the suite serialized, the counting test ran
first and saw only its own acquisition; every later test then took another board, unobserved.

    ✔ Test "The whole suite takes ONE board from the pasteboard server" passed after 0.003 seconds.
      ^ with a planted per-test acquisition in place

A verdict that depends on execution order cannot say no. It was deleted rather than shipped.

## What replaced it, and its baseline failure

`.engine/checks/one-test-pasteboard.sh` counts acquisition **sites** in `Tests/`, which has no such
ordering dependency. Run against the unchanged tree first, it reported **2 sites on a tree that has
1** - it was counting the label string `"NSPasteboard(name: \(name.rawValue))"` that the acquisition
passes to `BoundedWork`, and the `NSPasteboard(name:)` spelled out in prose. String literals and
comments are now stripped before counting. A gate red on correct code is one nobody keeps.

Four states, all run:

| state | expected | got |
|---|---|---|
| baseline, one shared board | green | `ok - 1 acquisition site` |
| second real acquisition planted | **red** | `FAIL - 2 acquisition sites`, both located |
| doc comment + string literal naming the symbol | green | `ok - 1 acquisition site` |
| restored | green | `ok - 1 acquisition site` |

It runs in CI ahead of the suite, so a red there explains a red below it.

**What it cannot see**, since a gate's blind spot is part of its result: it counts textual call
sites, so one site inside a loop would still acquire many boards. The single site lives in a
`static let`, which Swift initialises exactly once, and that structure is what makes one site mean
one acquisition.

## Not done

**No retry on acquisition.** A second attempt against a stalled mach send re-hangs and abandons
another thread, and the four acquisitions that returned are not evidence that a fifth would. Nothing
here was measured, so nothing was built on it.

## State after

456 tests in 67 suites pass, 0 lint violations in 99 files, and all 14 `.engine/checks` green.
