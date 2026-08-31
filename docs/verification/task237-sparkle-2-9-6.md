# Sparkle 2.9.3 -> 2.9.6, and the pins that let it drift (#237)

Bobby asked where things stood and whether there was "any dependabot stuff". Nothing was open. The
answer turned out to be that the dependency most worth watching is the one no dependency tool can
see.

## Measured, not assumed

| | version |
|---|---|
| `scripts/fetch-sparkle.sh` pin | 2.9.3 |
| framework on disk (`CFBundleShortVersionString`) | 2.9.3 |
| `generate_appcast` CLI in `release.yml` | 2.9.3 |
| upstream latest | **2.9.6**, published 2026-08-17 |

Read off the framework's own `Info.plist` and the GitHub releases API, not from the pin alone - the
pin is a claim about what should be vendored, and the plist is what is.

## Two of the three missing releases are security releases

- **2.9.5** - symlink hardening in delta patching.
- **2.9.6** - privilege escalation fix, and package installs are now rejected when signature
  validation fails.

**Exposure is low, and inflating it would be as wrong as ignoring it.** The privilege-escalation fix
concerns processes running as root; PushText does not run as root. The 2.9.5 fix is in *delta*
patching and our appcast ships a plain zip with no deltas. The package-install fix does not apply -
we ship a zip, not a pkg. What remains is that the component which installs code on a user's machine
was three releases and two advisories behind.

## Why every gate was green

Sparkle is a local `binaryTarget` at `Vendor/Sparkle.xcframework`, fetched by a shell script with the
version in a variable. No manifest, no lockfile, nothing for Dependabot to read - and enabling its
`swift` ecosystem would not change that, because the ecosystem reads `Package.swift`/`Package.resolved`
and Sparkle appears in neither as a versioned dependency. Nothing was wrong with the gates. Nothing
was looking.

## Three defects found while confirming it

1. **Pinned twice, tied together by nothing.** The framework pin and the appcast-signing CLI pin live
   in different files. Bump one and the release signs its appcast with a different Sparkle than the
   app runs.
2. **The version was pinned; the bytes were not.** `curl | unzip`, no checksum. HTTPS says the
   transport was not tampered with, never that the artifact is the one this project was tested
   against.
3. **The bump would not have taken locally.** `[ -d "$DEST" ] && exit 0` short-circuits on any
   existing `Vendor/`. CI would have taken 2.9.6 from a fresh checkout while this machine kept 2.9.3,
   silently, with no output saying so.

## Two defects the plants found in my own fix

**The first version of the fix destroyed the vendor on failure.** It removed the old framework and
*then* downloaded the new one, so a wrong digest or a dropped connection left the machine with no
Sparkle at all. Planting a bad digest printed the refusal correctly and wrecked the checkout:

    fetch-sparkle: REFUSING to vendor - sha256 mismatch for Sparkle 2.9.5
    ...
    vendor after refusal: VENDOR DESTROYED

Restructured to verify first and replace last. Re-planted:

    fetch-sparkle: REFUSING to vendor - sha256 mismatch for Sparkle 2.9.5
      expected 000000...
      got      34b9b2071f3de0012eca3faa3a9290bb94e62131e9a74f6dc91514a000097a6c
    exit=1
      vendor after refusal: 2.9.6

**The new gate failed closed and silently.** Run against the pre-change tree, which has no
`SPARKLE_CLI_VERSION`, it exited 1 with no output: under `set -e` the non-matching `grep` killed the
script before the branch that explains the problem. `|| true` on the lookups; the missing-pin case
now prints which file and which variable.

That second one is only visible by running a new gate against the PRE-change baseline. It reached
green on the fixed tree either way.

## The gate's battle test

`.engine/checks/sparkle-pins-agree.sh`, five states, all run:

| state | expected | got |
|---|---|---|
| tree as written | green | `ok - both pins at 2.9.6, both digests present` |
| pre-change tree (2.9.3, no digests) | **red** | `FAIL - could not read a pin`, names both |
| framework 2.9.6, CLI left at 2.9.3 | **red** | `FAIL - the two Sparkle pins disagree` |
| digest replaced with garbage | **red** | `FAIL - no usable SPARKLE_SHA256` |
| restored | green | `ok - both pins at 2.9.6` |

An earlier run of this table returned `exit=126` on all five - the copied script was not executable.
Worth recording because the three RED rows "passed" on that run: only the two GREEN rows failing
exposed it. A table checked for red alone would have scored a broken harness as a working gate.

## The real path, driven

`swift test` cannot prove this. Sparkle links into the app target only, and the suite never launches
the app - a framework swap fails at dyld, not at compile.

    Sparkle embedded in dist/PushText.app: 2.9.6
    OK: dist/PushText.app launched and stayed alive (alive=8/8, footprint=15 MB, crash-reports 0->0);
    hotkey probe: tap armed, recovered from forced disable; audio probe: capture verified,
    timestamps monotonic+contiguous

**What this does NOT prove:** that an end-to-end Sparkle *update* installs correctly under 2.9.6.
That path only executes when a real user takes a real update against the published appcast, and no
local run reaches it. What is proven is that the app links, launches and runs with the new framework
embedded and re-signed.

## Explicitly not solved

**Nothing notices that upstream has moved.** The gate keeps the two pins consistent with each other,
not current with the world. A network check would go red the moment Sparkle released, turning a
correctness gate into a nag - and a gate nobody can satisfy on the spot gets ignored, which is how
the OSV-Scanner lesson went. Noticing a new Sparkle stays a human walking up to it.

## State after

456 tests in 67 suites pass, 0 lint violations across 99 files, all 15 `.engine/checks` green,
packaged app launches with 2.9.6 embedded.
