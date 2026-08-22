# TermTile Blueprint — the exact project shape to clone for Mumbler

Source of truth: `/Users/evancnavarro/Developer/termtile`, read 2026-08-22.
Repo state at read time: branch `master`, HEAD `fd3c184 Center menu bar glyph in badge canvas`,
remote `https://github.com/EvanCNavarro/TermTile.git` (personal / godmode).
Latest published release per `HANDOFF.md`: **v0.2.6** (2026-07-18), build 138, Developer ID
signed + notarized + stapled.

**Method / limits (Tenet 1).** Everything below was read off disk with `cat`/`grep`/`find` in this
session. Nothing was built, run, or modified. What this reading canNOT see: whether `swift build`,
`swift test`, or `swiftlint --strict` are currently green; whether the scripts still work against
the current Xcode/macOS; whether the Sparkle appcast URL currently resolves. Every claim about
runtime behavior is quoted from a source comment or a doc, not from a run — treat those as the
author's claim, not my verification.

---

## 1. File tree (excluding `.build/`, `.git/`, `dist/`, `Vendor/`, `.sparkle-tools/`)

Sizes in bytes, from `find … -exec ls -l`.

```
       47  .engine/.gitignore
    44967  .engine/BACKLOG.md
      992  .engine/MEMORY.md
     1497  .engine/checks/axprobe-detached-task.sh
     1319  .engine/checks/axprobe-no-defer.sh
     1108  .engine/checks/core-purity.sh
      617  .engine/checks/cwc-config-present.sh
      781  .engine/checks/no-iterm-whose-filter.sh
      530  .engine/checks/reorient-next-task-cited.sh
     1072  .engine/checks/scripts-ascii-only.sh
      829  .engine/checks/selftest-stderr-markers.sh
     1158  .engine/checks/task-refs-int-keys.sh
      585  .engine/checks/traps-ordered.sh
      522  .engine/config.json
        0  .engine/state/.gitkeep
    (…20 gitignored state files: notarization logs, stoke-plan-*.md, reorient.md…)
    21248  .engine/traps.md
      306  .github/dependabot.yml
      496  .github/pull_request_template.md
      848  .github/workflows/check.yml
    11086  .github/workflows/release.yml
      618  .github/workflows/semgrep.yml
      168  .gitignore
      235  .skills/manifest.json
      639  .swiftlint.yml
      461  AGENTS.md
      167  CLAUDE.md
     6527  HANDOFF.md
     1072  LICENSE
      457  PROJECT.md
      390  Package.resolved
     2787  Package.swift
     5634  README.md
     1255  Resources/AppIconSource.svg
     1349  Resources/TermTileMenuGlyph.pdf
      752  Resources/TermTileMenuGlyph.svg
     2337  SECURITY.md
     1509  Sources/TermTile/BundleResources.swift
     4834  Sources/TermTile/HotKeyRecorder.swift
    13254  Sources/TermTile/MenuBarContent.swift
    31766  Sources/TermTile/Resources/AppIcon.png
    14690  Sources/TermTile/TermTileApp.swift
     4352  Sources/TermTile/TermTileGlyph.swift
     4968  Sources/TermTile/TermTileUserDriver.swift
      261  Sources/TermTile/UpdateAvailability.swift
     6907  Sources/TermTile/Updater.swift
     1702  Sources/TermTileCore/AXGeometry.swift
      658  Sources/TermTileCore/AppIdentity.swift
      576  Sources/TermTileCore/FrameCommand.swift
      623  Sources/TermTileCore/FrameMath.swift
     1641  Sources/TermTileCore/ReorderStrategy.swift
     1256  Sources/TermTileCore/TileConfig.swift
     8903  Sources/TermTileCore/TileEngine.swift
     1782  Sources/TermTileCore/TileLayout.swift
      409  Sources/TermTileCore/TrackedWindow.swift
     6875  Sources/TermTileKit/AXWindowSystem.swift
      829  Sources/TermTileKit/AccessibilityState.swift
     1212  Sources/TermTileKit/AccessibilityTrust.swift
     3422  Sources/TermTileKit/AppSettings.swift
     8569  Sources/TermTileKit/DragMonitor.swift
     2237  Sources/TermTileKit/DragReorderController.swift
     1557  Sources/TermTileKit/DragReorderControlling.swift
     9897  Sources/TermTileKit/HotKeyMonitor.swift
     3475  Sources/TermTileKit/LoginItem.swift
    20663  Sources/TermTileKit/MenuBarViewModel.swift
     2123  Sources/TermTileKit/OwnedPaths.swift
     3068  Sources/TermTileKit/PermissionRepairer.swift
     5257  Sources/TermTileKit/SettingsStore.swift
      672  Sources/TermTileKit/TargetAppForegrounding.swift
     1165  Sources/TermTileKit/TargetApps.swift
      632  Sources/TermTileKit/TargetRunningApplicationResolver.swift
     3563  Sources/TermTileKit/TilingActor.swift
     7427  Sources/TermTileKit/Uninstaller.swift
      680  Sources/TermTileKit/WindowFiltering.swift
     1695  Sources/TermTileKit/WindowSystem.swift
     4089  Sources/TermTileKit/WorkspaceTargetAppForegrounder.swift
     1936  Sources/TermTileKit/WorkspaceTargetAppsProvider.swift
     (Tests/ — 7 Core, 20 Kit, 11 shell files; see §8)
      183  cwc.config.json
     3962  docs/NOTARIZATION.md
     4866  docs/RELEASING.md
     4269  docs/decisions/0001-functional-core-imperative-shell.md
       82  docs/decisions/0001-project-shape.md
     1782  docs/decisions/0002-notarization-release-gate.md
    16960  docs/decisions/0003-update-availability-indicators.md
    17517  docs/decisions/0004-update-indicator-visibility-polish.md
    10245  docs/decisions/0005-live-app-polish-before-release.md
      281  docs/environment/COMMAND_PORTABILITY.md
      259  docs/environment/MAC_TERMINAL.md
      196  docs/environment/TMUX.md
     1817  docs/github/REPOSITORY_POLICY.md
        0  docs/product/.gitkeep
     3245  docs/product/spec-draft.md
     6393  docs/research/macos-tiling-research.md
     4036  docs/research/menubar-app-features-research.md
    11570  docs/research/remembar-audit.md
     (docs/research/spikes/02..07-*.md — 5-8 KB each)
      315  docs/skills/SKILL_AUTHORITY.md
        0  docs/superpowers/specs/.gitkeep
      105  docs/verification/COMMANDS.md
     (docs/verification/*.md + *.png — ~30 files, screenshots up to 1.8 MB)
      417  release-notes/0.1.0.md
     1306  release-notes/0.2.0.md
      788  release-notes/0.2.1.md
      660  release-notes/0.2.2.md
      856  release-notes/0.2.3.md
      509  release-notes/0.2.4.md
      795  release-notes/0.2.5.md
      550  release-notes/0.2.6.md
     9079  scripts/build-app.sh
     1008  scripts/fetch-sparkle.sh
     1836  scripts/install-app.sh
     1256  scripts/lib/notary-auth.sh
     2067  scripts/notarize-app.sh
      858  scripts/notary-status.sh
     2322  scripts/setup-dev-signing.sh
     8545  scripts/test-packaged-app.sh
```

`Vendor/Sparkle.xcframework` (gitignored, ~25 MB incl. dSYMs) and `.sparkle-tools/`
(`generate_appcast`, `generate_keys`, `sign_update` — gitignored binaries) exist locally but are
not tracked.

---

## 2. `.engine/` — the Locomotion living layer

Five parts: a config, a trap library, a memory file, a gitignored working-state dir, and a set of
executable fail-closed checks.

### 2.1 `.engine/.gitignore`
```
state/*.lock
claims/*.lock
claims/.ledger.lock
```
The *root* `.gitignore` is what actually excludes the state dir:
```
.engine/state/*
!.engine/state/.gitkeep
.engine/events.jsonl
```
So `.engine/config.json`, `traps.md`, `MEMORY.md`, `BACKLOG.md`, and `checks/` **are tracked**;
everything under `state/` is local-only.

### 2.2 `.engine/config.json` — the live-surface map (verbatim, this IS the schema)

```json
{
  "test_command": "swift test",
  "test_command_timeout": 600,
  "build_command": "swift build",
  "build_command_timeout": 600,
  "stack_facets": [
    "runtime",
    "deps",
    "test-harness",
    "tooling",
    "process"
  ],
  "llm_node_globs": [],
  "sse_event_globs": [],
  "frontend_globs": [],
  "subprocess_globs": [
    "Sources/*.swift",
    "Sources/**/*.swift",
    "scripts/*.sh",
    "scripts/**/*.sh"
  ],
  "cost_budget_usd": 0.5,
  "lint_command": "swiftlint --strict",
  "lint_command_timeout": 120
}
```

Field meanings (per `MEMORY.md` and `checks/cwc-config-present.sh`):

| Key | Type | Meaning |
|---|---|---|
| `test_command` / `test_command_timeout` | string / int seconds | the project's test signal |
| `build_command` / `build_command_timeout` | string / int seconds | the project's build signal |
| `lint_command` / `lint_command_timeout` | string / int seconds | the lint gate |
| `stack_facets` | string[] | which facets of the stack a reorient must re-read |
| `llm_node_globs` | glob[] | files whose live surface is an LLM call (empty here) |
| `sse_event_globs` | glob[] | streaming-event surfaces (empty here) |
| `frontend_globs` | glob[] | browser-verifiable surfaces — **deliberately empty**: a native app has none |
| `subprocess_globs` | glob[] | files whose live proof means running a real process |
| `cost_budget_usd` | number | per-cycle spend ceiling |

**The duplication is deliberate and load-bearing.** `cwc.config.json` at the repo *root* is a
separate, smaller file that the cycle-closer actually reads:

```json
{
  "test_command": "swift test",
  "llm_node_globs": [],
  "subprocess_globs": ["Sources/**/*.swift", "Sources/*.swift", "scripts/**/*.sh", "scripts/*.sh"],
  "frontend_globs": []
}
```
`.engine/checks/cwc-config-present.sh` fails closed if that root file is missing or lacks a
`Sources/**/*.swift` glob — because without it the PROVE gate reports "no live surface touched"
and closes cycles on `N/A` (this is TRAP-3).

### 2.3 `.engine/MEMORY.md` — project PROVE semantics (verbatim)

```
# TermTile .engine memory

- **Live-surface semantics (native app, not web):** every Swift source under `Sources/` is
  mapped to `subprocess_globs` because the app's real surface is AX manipulation of OTHER
  apps' windows. PROVE (FL-1) for a touched Swift file means: run the built app (or a
  compiled harness) against REAL windows of the target app and verify frames/behavior —
  screenshots via `screencapture` count as rendered-reality evidence (FL-9). Chrome
  DevTools / curl verifiers do not apply here; `frontend_globs` is intentionally empty.
- **Test/build signals:** `swift test` / `swift build` at repo root (Package.swift lands
  with the first build task). Until then both signals are expected-red — that is the
  red-first baseline, not a config error.
- **Research authority:** `docs/research/macos-tiling-research.md` (verified deep-research).
  Spec draft: `docs/product/spec-draft.md`. Template app: RememBar at
  `~/Desktop/safari-history-export/BrowserMemoryBar/`.
```

### 2.4 `.engine/traps.md` — 262 lines, 18 numbered traps

Format: a top note (promote a trap to the global library at
`~/.claude/skills/locomotion/reference/traps-index.md` once it recurs across ≥2 stacks), then
`### TRAP-N: <one-line title>` with two bullets — `what happened` (the concrete failure, with real
values) and `warning` (the rule, plus which check enforces it or an explicit
"Not mechanically checkable").

The 18 traps, condensed:

| # | Trap | Enforced by |
|---|---|---|
| 1 | Menu-bar screenshot proof unreliable under a menu-bar manager (item parked at X=-4721, layer 25) — prove via AX enumeration + CGWindowList, not pixels | — |
| 2 | Gate artifacts: deferrals must be ONE physical line; `task-refs.json` keys must be bare ints | `task-refs-int-keys.sh` |
| 3 | `cycle_close.py` reads root `cwc.config.json`, not `.engine/config.json` | `cwc-config-present.sh` |
| 4 | Security hook blocks `rm -rf` outside the repo — use `rm -f` + `rmdir` | — |
| 5 | zsh expands `=word` — `echo ===` dies | — |
| 6 | iTerm2 AppleScript rejects `whose` filters on windows | `no-iterm-whose-filter.sh` |
| 7 | New traps get inserted mid-file, breaking numeric order — APPEND only | `traps-ordered.sh` |
| 8 | Spike-created windows vanish externally before cleanup; never `&&`-chain close with verification | — |
| 9 | Invert-check evidence lost by fusing flip+run+restore+run into one command | — |
| 10 | Gate parsers read the FIRST PHYSICAL LINE only — machine tokens must share the anchor's line | `reorient-next-task-cited.sh` |
| 11 | Edit tool rejects files inspected only via Bash `cat` — a prior Read-TOOL call is required | — |
| 12 | C `exit()` skips Swift `defer` — restore inline (belt: `atexit`), never `defer` | `axprobe-no-defer.sh` |
| 13 | `il7` gate false-fails on the literal Swift keyword `defer`/`skip` — document the override, never edit the receipt | — |
| 14 | Bare `Task {}` from a `main.swift` top level + `sem.wait()` on main = silent deadlock; use `Task.detached` | `axprobe-detached-task.sh` |
| 15 | A live-effect PROVE passed on a value that COINCIDED with the pre-action state — require a DELTA | — |
| 16 | `swift test --filter` matches the Swift IDENTIFIER, not the `@Suite`/`@Test` display string; a zero-match filter exits 0 | — |
| 17 | `print()` to a pipe is block-buffered and lost on SIGTERM — live markers go to `FileHandle.standardError` | `selftest-stderr-markers.sh` |
| 18 | A non-ASCII byte glued to `$var` breaks Bash under `set -u` | `scripts-ascii-only.sh` |

### 2.5 `.engine/checks/` — nine executable fail-closed guards

Every one is a standalone `#!/usr/bin/env bash`, `set -euo pipefail`-ish, exits non-zero on
violation, and **exits 0 when the guarded file does not exist** (pre-split / not-yet-built safety).

| Script | Guards |
|---|---|
| `core-purity.sh` | **ADR-0001**: nothing under `Sources/TermTileCore/` may `import AppKit` or `ApplicationServices`. Regex tolerates attribute prefixes (`@preconcurrency import …`) and `.Submodule` — anchoring on `^import` would fail OPEN. |
| `cwc-config-present.sh` | root `cwc.config.json` exists AND contains a `Sources/**/*.swift` subprocess glob |
| `scripts-ascii-only.sh` | every `scripts/*.sh` is 7-bit ASCII (uses `perl`; BSD grep has no `-P`) |
| `traps-ordered.sh` | `### TRAP-N` headings appear in ascending numeric order |
| `reorient-next-task-cited.sh` | every `^Next task:` line in `.engine/state/reorient.md` carries a same-line `←` citation |
| `task-refs-int-keys.sh` | every key in `.engine/state/task-refs.json` is a bare base-10 integer (python3 inline) |
| `selftest-stderr-markers.sh` | no `print(...SELFTEST...)` in `Sources/TermTile/TermTileApp.swift` |
| `axprobe-no-defer.sh` | no `defer {` statement in `Sources/AXProbe/main.swift` (comments stripped first) |
| `axprobe-detached-task.sh` | no bare `Task {` / `Task.init {` in `Sources/AXProbe/main.swift` |

The last two guard a target (`AXProbe`) that no longer exists in `Package.swift` — they pass
vacuously. That is the intended shape: a check outlives the code it was written for and costs
nothing.

**The pattern worth copying:** the check strips `//` comments before matching (`sed 's://.*$::'`),
so a comment *describing* the trap does not trip the guard. Example, `core-purity.sh`:
```bash
if grep -REn '(^|[[:space:]])import[[:space:]]+(AppKit|ApplicationServices)([.[:space:]]|$)' "$core_dir"; then
    echo "core-purity: FORBIDDEN import in Sources/TermTileCore/ ..." >&2
    exit 1
fi
```

### 2.6 `.engine/state/` (gitignored) — what actually accumulates

`reorient.md` (the next-task pointer + `[DEP:#N]` deferral lines), `stoke-plan-<N>-<slug>.md`
(one per planned task — 17 files, 3–12 KB each), `notarization-status-log.md` (17 KB),
`notary-poll-*.{log,tsv,jsonl,terminal}`, `task-refs.json`, `v022-local-app-path.txt`.
`.engine/BACKLOG.md` (45 KB) is **tracked** and uses the taxonomy
`#N · title · S0|S1|S2|DONE` with explicit `blocked-by #N` dependencies.

---

## 3. `docs/` and `release-notes/`

### 3.1 Directory shape

```
docs/
  NOTARIZATION.md            runbook: notarytool auth, release gate, read-only polling, post-release verify
  RELEASING.md               versioning scheme + the cut-a-release procedure + required secrets
  decisions/                 ADRs (numbered, see below)
  environment/               COMMAND_PORTABILITY.md, MAC_TERMINAL.md, TMUX.md — the "project contract"
  github/REPOSITORY_POLICY.md  CI baseline + branch-protection expectations, with doc-URL sources
  product/spec-draft.md      the provisional product spec (explicitly "not locked scope")
  docs/research/                  deep-research notes + spikes/NN-<slug>.md findings
  skills/SKILL_AUTHORITY.md  one canonical skill source; project adapters reference it
  superpowers/specs/         (empty, .gitkeep)
  verification/              COMMANDS.md + per-task evidence .md files + .png screenshots
```

`docs/verification/` is the FL-9 rendered-reality store: `task1-menubar-proof.png`,
`task13a-bundle-launch.png` (1.8 MB), `task14a-activate-grid.png`, `release-v0.2.6.md`, etc. This
is where "I ran it and here is the pixel evidence" lands.

### 3.2 The ADRs (every one read)

**`0001-project-shape.md`** — 82 bytes, a stub:
> `# 0001 Project Shape` / `This repo starts from the project-start invariant scaffold.`

**`0001-functional-core-imperative-shell.md`** — the real architectural ADR. Status "accepted
(2026-07-02). Binding for all Phase B tasks (#8–#14)." Context: pure geometry mixed with the
messiest side-effect surface on macOS; Swift 6 strict concurrency needs a deliberate answer for
CFRunLoop AXObserver callbacks. Decision — the target graph:

```
TermTileCore   (library)  — pure: layout math, domain types, reducer. CoreGraphics geometry only.
                            NO AppKit / ApplicationServices.
TermTileKit    (library)  — depends on Core. The port (WindowSystem protocol + WindowEvent/
                            FrameCommand types), the AX adapter (the ONLY code importing
                            ApplicationServices for control), the TilingActor, the fake WindowSystem.
TermTile       (executable) — depends on Kit. Thin shell: MenuBarExtra UI, settings,
                            composition root (the only place production wiring happens).
AXProbe        (executable) — throwaway spike code, quarantined.
```

**The four rules** (quoted, condensed):
1. **Pure core.** Layout functions and the reducer are pure — "testable with plain values, no mocks."
2. **One port.** All window-system access goes through `WindowSystem`. Production adapter = AX;
   test adapter = in-memory fake.
3. **Self-move classification is data, not a flag.** Commands register pending expectations
   (id → expected frame + deadline); incoming events are matched and classified by a *pure*
   function in Core.
4. **One actor owns AX.** A single `TilingActor` in Kit; the CFRunLoop AXObserver callback is
   bridged ONCE at the adapter into an `AsyncStream`.

Consequences section explicitly names what was **deliberately not added (YAGNI)**: layout-strategy
plugins, multi-app orchestration, config file formats — "A second layout or target-app profile
triggers the abstraction, not before."

**`0002-notarization-release-gate.md`** — Status "Accepted on 2026-07-16." Decision: gate public
release on Developer ID notarization; run `scripts/notarize-app.sh` **before** packaging so the zip
contains the stapled app; never publish if Notary fails, stapling fails, or Gatekeeper rejects.
Also: "Public Developer ID artifacts must also keep hardened-runtime library validation enabled.
Local self-signed or ad-hoc development builds may use
`com.apple.security.cs.disable-library-validation` … but public release artifacts must not carry
that entitlement." Consequences require the release smoke test to *inspect shipped entitlements and
reject* that key.

**`0003-update-availability-indicators.md`** (17 KB) — Status: "Implemented locally in focused
phases on 2026-07-18 and released publicly as TermTile v0.2.6. Phase 11 complete, 100%." Structure
is the interesting part, and it is the house ADR template for a *feature arc*:
`Status` → `Context` → `Verified Premises` → `Brutal Audit` (with sub-sections
`Dependency inversions to avoid`, `Bundled tasks to split`, `Traps and edge cases`) →
`Do now` → `Depends on future state` → `Execution Plan` (Phase 0…Phase 11, each with an explicit
`Status:` line). Phase 0 is always "Baseline and plan lock."

**`0004-update-indicator-visibility-polish.md`** (18 KB) — same template. Notable: phases are
labelled with the *dependency repo's* released tag —
"Phase 1 … Status: Complete in MacFaceKit `v0.4.1` (`a7401f6`)"; then
"Phase 3: TermTile Dependency Readiness". It also carries a dated
`## Continuation Audit: 2026-07-18` section, and records that Decision 0005 **supersedes** its
initial lower-corner placement after live comparison with other macOS menu-bar indicators.

**`0005-live-app-polish-before-release.md`** (10 KB) — Status: "Started on 2026-07-18 after local
live-app testing… Phases 0-3 complete, 100%." Carries an explicit release boundary:
> "this plan may commit and push source checkpoints, but it must not create a TermTile public
> release tag or run the public release pipeline until the installed live app is tested and release
> is explicitly approved."
Sections: `STOKE Audit` → `Do Now` → `Depends On Future State` → `Execution Plan`
(Phase 0 "Observe And Red Tests" → Phase 1 "Implement Root Fixes" → Phase 2 "Dependency And
Documentation" → Phase 2B "Stale Accessibility Recovery" → Phase 3 "Full Validation And Native Live
Test").

**ADR conventions to copy:** numbered `NNNN-kebab-title.md`; a `## Status` section that carries a
*date and a completion percentage*, updated in place; phases with individual `Status: Complete.`
markers; and a later ADR explicitly saying it supersedes an earlier one rather than editing it.

### 3.3 `release-notes/` — the single-source convention

One file per version: `release-notes/<version>.md` (no `v` prefix — `0.2.6.md`, not `v0.2.6.md`),
authored **before** tagging. `docs/RELEASING.md` states why:

> One file per version — `release-notes/<version>.md` — authored **before** tagging. `release.yml`
> uses it twice, so there is exactly one place to write them:
> 1. **Sparkle "What's new" dialog** — staged as `dist/TermTile-<tag>.md` (matching the archive
>    basename) and inlined into the appcast `<description>` via
>    `generate_appcast --embed-release-notes`.
> 2. **GitHub release body** — `gh release create --notes-file release-notes/<version>.md`.

Format drifted deliberately across the line:
- `0.1.0.md` and `0.2.0.md`: **no heading**, just a flat bullet list of user-visible changes.
- `0.2.2.md` onward: `# TermTile 0.2.2` heading, an optional one-line framing sentence
  ("This is the notarized distribution fix."), then bullets.

Voice: user-facing, feature-first, no commit hashes, no task numbers. Bold the UI strings
(`**Repair Accessibility**`, `**Bring app forward**`). Where a release requires user action it says
so plainly — `0.2.1.md`: "you may need to remove TermTile from System Settings > Privacy & Security
> Accessibility … then add it again once after installing this update."

**These files are asserted by tests.** `Tests/TermTileKitTests/ReleaseReadinessTests.swift` has one
`@Test` per version, e.g. `"0.2.6 release notes explain update availability indicators"` — the notes
are a *tested artifact*, not prose nobody checks.

---

## 4. `scripts/` — build, sign, notarize, install, smoke

Eight files. Every one is ASCII-only (enforced), `set -euo pipefail`, and resolves the repo root
from `${BASH_SOURCE[0]}` rather than trusting CWD.

```
scripts/build-app.sh          190 lines — SPM binary → signed .app bundle       (THE crown jewel)
scripts/fetch-sparkle.sh       18 lines — vendor Sparkle.xcframework into Vendor/
scripts/install-app.sh         44 lines — build + install to /Applications + relaunch
scripts/notarize-app.sh        75 lines — submit → wait → staple → validate → spctl
scripts/notary-status.sh       31 lines — READ-ONLY notarytool history/info/log
scripts/setup-dev-signing.sh   50 lines — one-time stable self-signed local identity
scripts/test-packaged-app.sh  227 lines — bundle invariants + real launch proof
scripts/lib/notary-auth.sh     39 lines — shared Notary credential preparation
```

### 4.1 `build-app.sh` — the .app assembly, step by step

**Env-overridable everything**, so CI and e2e reuse the *same* build path with no drift
(`build-app.sh:13-24`):
```bash
APP_NAME="${APP_NAME:-TermTile}"
BUNDLE_ID="${BUNDLE_ID:-dev.ecn.apps.termtile}"
CONFIGURATION="${CONFIGURATION:-release}"
SHORT_VERSION="${SHORT_VERSION:-0.1.0}"
DIST_DIR="${DIST_DIR:-dist}"
ICON_SRC="${ICON_SRC:-Sources/TermTile/Resources/AppIcon.png}"
SU_FEED_URL="${SU_FEED_URL:-https://github.com/EvanCNavarro/TermTile/releases/latest/download/appcast.xml}"
SU_PUBLIC_ED_KEY="${SU_PUBLIC_ED_KEY:-mIAUkTNj+kRPNqkAX1Z1EaqFqyLaFQ37pwEIGduj4Zs=}"
```
The EdDSA **public** key is committed in the script; the private key lives in the login Keychain
(`svce https://sparkle-project.org`) and, in CI, in the `SPARKLE_ED_PRIVATE_KEY` secret.

**Step 1 — build number.** `build-app.sh:29-42`:
```bash
if [ -n "${TERMTILE_BUILD_NUMBER:-}" ]; then
	if [ "${GITHUB_ACTIONS:-false}" = "true" ]; then
		echo "TERMTILE_BUILD_NUMBER is local-only and cannot be used in GitHub Actions" >&2
		exit 1
	fi
	[[ "$TERMTILE_BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || { …exit 1; }
	BUILD_NUMBER="$TERMTILE_BUILD_NUMBER"
else
	BUILD_NUMBER="$(git rev-list --count HEAD)"
fi
```
`CFBundleVersion` = monotonic commit count, **never dots-stripped**. The comment names the bug this
avoids (`build-app.sh:8-9`): "`0.10.1->0101` collides". The override exists only so a local
downgrade build can compare *below* an already-published appcast — and it is hard-blocked in CI.

**Step 2 — build and locate the product.** `build-app.sh:46-49`:
```bash
swift build -c "$CONFIGURATION" --product "$APP_NAME" >&2
BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
BINARY="$BIN_DIR/$APP_NAME"
[ -x "$BINARY" ] || { echo "built binary not found at $BINARY" >&2; exit 1; }
```
Never a hardcoded `.build/release` path. Note `--show-bin-path` **must ride the same `-c`
invocation** or it prints the debug dir (comment at `:44-45`). All build chatter goes to stderr so
stdout stays clean for the final path.

**Step 3 — skeleton.** `build-app.sh:51-54`:
```bash
APP="$DIST_DIR/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/$APP_NAME"
```

**Step 4 — flat resources.** `build-app.sh:56-60`. The menu-bar glyph PDF is copied as a *plain
file* into `Contents/Resources`, sealed by the app signature:
> "NOT an SPM resource bundle: a flat `.bundle` in `Contents/MacOS` breaks codesign."

**Step 5 — Info.plist generation.** Heredoc → `plutil -lint` gate (`build-app.sh:63-86`). The full
key set:
```xml
<key>CFBundleName</key><string>$APP_NAME</string>
<key>CFBundleDisplayName</key><string>$APP_NAME</string>
<key>CFBundleExecutable</key><string>$APP_NAME</string>
<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$SHORT_VERSION</string>
<key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
<key>SUFeedURL</key><string>$SU_FEED_URL</string>
<key>SUPublicEDKey</key><string>$SU_PUBLIC_ED_KEY</string>
<key>SUEnableAutomaticChecks</key><false/>
```
`LSUIElement` = menu-bar-only, no Dock icon. `SUEnableAutomaticChecks` is **false** so Sparkle never
raises its automatic-check permission prompt in an `.accessory` app — the passive probe uses
Sparkle's non-presenting `checkForUpdateInformation()` path instead. Comment at `:62`: "Accessibility
(`AXIsProcessTrusted`) needs NO usage-string" — *a new app that uses microphone / speech recognition
DOES need `NSMicrophoneUsageDescription` / `NSSpeechRecognitionUsageDescription` here.*

**Step 6 — icon (optional).** `build-app.sh:89-100`. Generates an `.iconset` from a single PNG with
`sips` at 16/32/128/256/512 @1x and @2x, `iconutil -c icns`, then `PlistBuddy -c "Add
:CFBundleIconFile string AppIcon"`. It **also** copies the raw PNG into `Contents/Resources` so the
shared update dialog can resolve it via `Bundle.packagedResourceURL("AppIcon","png")` from
`Bundle.main` in a *shipped* build, not just DEBUG.

**Step 7 — embed Sparkle.** `build-app.sh:102-112`:
```bash
SPARKLE_FRAMEWORK="$ROOT/Vendor/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
[ -d "$SPARKLE_FRAMEWORK" ] || "$(dirname "${BASH_SOURCE[0]}")/fetch-sparkle.sh" >&2
[ -d "$SPARKLE_FRAMEWORK" ] || { echo "Sparkle.framework missing (run scripts/fetch-sparkle.sh)" >&2; exit 1; }
FRAMEWORKS_DIR="$APP/Contents/Frameworks"
SPARKLE_DST="$FRAMEWORKS_DIR/Sparkle.framework"
SPARKLE_V="$SPARKLE_DST/Versions/B"
mkdir -p "$FRAMEWORKS_DIR"
ditto "$SPARKLE_FRAMEWORK" "$SPARKLE_DST"
```
`ditto` (not `cp -R`) **preserves the framework's version symlinks**. The comment names the failure:
a binary linking `@rpath/Sparkle.framework` with nothing in `Contents/Frameworks` **dyld-crashes at
launch**. This is why `Package.swift` carries
`.unsafeFlags(["-Xlinker","-rpath","-Xlinker","@executable_path/../Frameworks"])`.

**Step 8 — signing identity resolution.** `build-app.sh:123-131`:
```bash
DEFAULT_DEV_IDENTITY="TermTile Dev Signing"
if [ -n "${TERMTILE_SIGN_IDENTITY:-}" ]; then
	SIGN_IDENTITY="$TERMTILE_SIGN_IDENTITY"
elif security find-identity -v -p codesigning 2>/dev/null | grep -q "$DEFAULT_DEV_IDENTITY"; then
	SIGN_IDENTITY="$DEFAULT_DEV_IDENTITY"
else
	SIGN_IDENTITY="-"
fi
echo "build-app.sh: signing with identity: $SIGN_IDENTITY" >&2
xattr -cr "$APP"
```
Three-tier: explicit env wins → local stable self-signed cert → ad-hoc. **Why it matters** (`:117-122`):
ad-hoc (`-`) gets a fresh cdhash every build and *silently resets every macOS TCC grant*
(Accessibility, Input Monitoring). A stable identity keeps grants across rebuilds.

**Step 9 — entitlements, conditional.** `build-app.sh:133-166`. `TERMTILE_DISABLE_LIBRARY_VALIDATION`
defaults to `auto`, which resolves to **0 for a `Developer ID Application:*` identity and 1 for
anything else**. When 1, it writes:
```xml
<key>com.apple.security.cs.disable-library-validation</key><true/>
```
into `$APP/Contents/Resources/TermTile.entitlements`, `plutil -lint`s it, and passes it to the app
signings only. Local re-signed builds need it to load embedded Sparkle; Developer ID release
artifacts must NOT carry it (ADR-0002), and the smoke test rejects it.

**Step 10 — inside-out codesign, NO `--deep`.** `build-app.sh:167-187`:
```bash
sign_code() {
	codesign --force --options runtime --sign "$SIGN_IDENTITY" "$1" >&2
}
sign_app_code() {
	if [ -n "$ENTITLEMENTS" ]; then
		codesign --force --options runtime --entitlements "$ENTITLEMENTS" --sign "$SIGN_IDENTITY" "$1" >&2
	else
		codesign --force --options runtime --sign "$SIGN_IDENTITY" "$1" >&2
	fi
}

sign_code "$SPARKLE_V/XPCServices/Downloader.xpc"
sign_code "$SPARKLE_V/XPCServices/Installer.xpc"
sign_code "$SPARKLE_V/Autoupdate"
sign_code "$SPARKLE_V/Updater.app"
sign_code "$SPARKLE_DST"
# NB: the SPM resource bundle (glyph) is a FLAT resource bundle (no Info.plist / no Mach-O), so it is
# NOT code-signed on its own - the outer app signature below seals it as a resource.
sign_app_code "$APP/Contents/MacOS/$APP_NAME"
sign_app_code "$APP"
codesign --verify --deep --strict "$APP" >&2
```
**This exact order is the contract.** Deepest nested Sparkle code first (each XPC service
individually — `--deep` on a *sign* operation can corrupt nested signatures, per Sparkle's own
docs), then the framework, then the app binary, then the bundle. `--options runtime` = hardened
runtime, required for notarization. `--deep --strict` is used **only on verify**.

**Step 11 — the output contract.** `build-app.sh:189-190`:
```bash
# Last stdout line = the .app path, so callers can `tail -1` (RememBar convention).
echo "$APP"
```
`install-app.sh:12` does `APP="$(./scripts/build-app.sh | tail -1)"`; `release.yml:91` does
`APP_PATH="$(SHORT_VERSION="${GITHUB_REF_NAME#v}" scripts/build-app.sh | tail -1)"`.

### 4.2 `fetch-sparkle.sh`

```bash
SPARKLE_VERSION="2.9.3"
DEST="$PROJECT_DIR/Vendor/Sparkle.xcframework"
[ -d "$DEST" ] && { echo "Sparkle already vendored at $DEST"; exit 0; }
URL="https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-for-Swift-Package-Manager.zip"
curl -fsSL --max-time 180 "$URL" -o "$WORK/spm.zip"
unzip -q "$WORK/spm.zip" -d "$WORK/x"
cp -R "$(find "$WORK/x" -maxdepth 2 -name Sparkle.xcframework -type d | head -1)" "$DEST"
```
Idempotent. Reason for vendoring rather than a remote `binaryTarget` (`fetch-sparkle.sh:2-4`):
"SPM's remote binary-artifact downloader hangs in some sandboxes, while a plain download works."
`Vendor/` is gitignored, so **both CI workflows run this before any `swift build`/`swift test`** or
the binary target has no artifact.

### 4.3 `setup-dev-signing.sh` — the stable local identity

Creates a self-signed code-signing cert named `TermTile Dev Signing` in the login keychain, once,
idempotently (`setup-dev-signing.sh:16-19` early-exits if `security find-identity` already lists it).
OpenSSL config:
```
[v3]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
```
then `openssl req -x509 -newkey rsa:2048 … -days 3650 -nodes`, `openssl pkcs12 -export`, and
(`setup-dev-signing.sh:40-41`):
```bash
# -A: any app may use the key (no per-use ACL prompt); -T codesign: explicitly allow codesign.
security import "$TMP/id.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P "" -A -T /usr/bin/codesign
```
Purpose is stated bluntly (`:8`): "This does NOT help distribution — real users need Developer ID +
notarization. It only stabilizes LOCAL dev builds."

### 4.4 `install-app.sh`

```bash
APP="$(./scripts/build-app.sh | tail -1)"
DEST="${TERMTILE_INSTALL_DIR:-/Applications}"
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
pkill -x "$APP_NAME" 2>/dev/null || true
wait_for_app_exit          # 10 × 0.2s poll on pgrep -x
rm -rf "$HOME/Applications/$APP_NAME.app" 2>/dev/null || true   # migrate away from ~/Applications
rm -rf "$INSTALLED_APP"
ditto "$APP" "$INSTALLED_APP"
"$LSREG" -f "$INSTALLED_APP" 2>/dev/null || true
mdimport "$INSTALLED_APP" 2>/dev/null || true
open "$INSTALLED_APP" || { sleep 1; open -n "$INSTALLED_APP"; }
echo "$INSTALLED_APP"
```
Why `/Applications` and not `~/Applications` (`install-app.sh:4-8`): `~/Applications` is not
reliably Spotlight-indexed, "which made the app invisible in those pickers" — i.e. the app could not
be found in the Privacy permission pickers. The forced `lsregister -f` + `mdimport` make a
freshly-built bundle appear in Open panels and Privacy panes *immediately*.

### 4.5 `lib/notary-auth.sh` — one credential authority

Sourced by both notary scripts. Exports a `TERMTILE_NOTARY_ARGS` **bash array**
(`lib/notary-auth.sh:34-38`):
```bash
TERMTILE_NOTARY_ARGS=(
	--key "$TERMTILE_NOTARY_AUTH_KEY_PATH"
	--key-id "$TERMTILE_NOTARY_KEY_ID"
	--issuer "$TERMTILE_NOTARY_ISSUER_ID"
)
```
Two ways to supply the App Store Connect `.p8`: `TERMTILE_NOTARY_KEY_PATH` (a local file), or
`TERMTILE_NOTARY_KEY_P8_BASE64` (CI secret), which is decoded into the caller-supplied work dir and
`chmod 600`'d (`:23-26`):
```bash
mkdir -p "$work_dir"
TERMTILE_NOTARY_AUTH_KEY_PATH="$work_dir/AuthKey.p8"
printf '%s' "$TERMTILE_NOTARY_KEY_P8_BASE64" | base64 --decode > "$TERMTILE_NOTARY_AUTH_KEY_PATH"
chmod 600 "$TERMTILE_NOTARY_AUTH_KEY_PATH"
```
`TERMTILE_NOTARY_KEY_ID` and `TERMTILE_NOTARY_ISSUER_ID` are required; the function `return 1`s with
a named error if either is empty.

### 4.6 `notarize-app.sh` — the notarization flow

```bash
WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT
TIMEOUT="${TERMTILE_NOTARY_TIMEOUT:-60m}"
termtile_notary_prepare_auth "$WORK"

ZIP="$WORK/$(basename "${APP%.app}")-notary.zip"
ditto -c -k --keepParent "$APP" "$ZIP"          # --keepParent is REQUIRED for a .app submission

set +e
xcrun notarytool submit "$ZIP" "${TERMTILE_NOTARY_ARGS[@]}" \
	--wait --timeout "$TIMEOUT" --output-format json | tee "$RESULT_JSON"
SUBMIT_STATUS="${PIPESTATUS[0]}"                 # the pipe would otherwise mask the exit code
set -e
```
Then it parses `status` and `id` out of the JSON with two inline `python3` heredocs, and:
- if `SUBMIT_STATUS != 0` → dump `notarytool info` **and** `notarytool log` for the job id, exit with
  the submit status;
- if `STATUS != "Accepted"` → dump `notarytool log`, exit 1;
- otherwise (`notarize-app.sh:73-75`):
```bash
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=4 "$APP"
```
All three must pass. `set -e` means a failure at any of them fails the script, and therefore the
release job.

### 4.7 `notary-status.sh` — read-only

No arguments → `xcrun notarytool history`. With submission ids → `notarytool info` per id, plus
`notarytool log` only when `TERMTILE_NOTARY_FETCH_LOGS=1`. It **never calls `submit`** — and there is
a test that proves it: `PackagingScriptsTests.swift:372` `"notary-status.sh behavior: reads
history/info/log only, never submit"` runs the script against a **fake `xcrun` on `PATH`** that
`exit 97`s if `submit` is invoked. `docs/NOTARIZATION.md` states the operating rule:
> "Do not create duplicate Notary submissions unless there is a new artifact or a new hypothesis to
> test. Re-poll existing jobs with `scripts/notary-status.sh`."

### 4.8 `test-packaged-app.sh` — bundle invariants + real launch proof

Three phases.

**(a) Structural invariants** (`:78-92`):
```bash
[ -d "$APP" ] || fail "bundle not found: $APP"
BIN="$APP/Contents/MacOS/$APP_NAME"
[ -x "$BIN" ] || fail "bundle executable missing/not executable: $BIN"
[ "$(plutil -extract CFBundleIdentifier raw "$PLIST")" = "$BUNDLE_ID" ] || fail …
[ "$(plutil -extract LSUIElement raw "$PLIST")" = "true" ] || fail "LSUIElement must be true (menu-bar only)"
plutil -extract CFBundleVersion raw "$PLIST" >/dev/null || fail "CFBundleVersion missing"
[ "$(plutil -extract SUEnableAutomaticChecks raw "$PLIST")" = "false" ] || fail …
plutil -extract SUFeedURL raw "$PLIST" >/dev/null || fail "SUFeedURL missing"
plutil -extract SUPublicEDKey raw "$PLIST" >/dev/null || fail "SUPublicEDKey missing"
```

**(b) Signature gates** (`:94-125`), tiered by env so local dev and release CI share one script:
```bash
codesign --verify --deep --strict "$APP" || fail …
if [ "${REQUIRE_STABLE_CODESIGN:-0}" = "1" ]; then
	SIGNATURE_INFO="$(codesign -dv --verbose=4 "$APP" 2>&1)"
	DESIGNATED_REQ="$(codesign -d -r- "$APP" 2>&1)"
	… grep -q "Signature=adhoc"        → fail "stable signing required, but app is ad-hoc signed"
	… ! grep -q "Authority="            → fail "…no certificate authority"
	… grep -q 'cdhash H"'               → fail "…designated requirement is cdhash-only"
	if [ "${REQUIRE_DEVELOPER_ID_CODESIGN:-0}" = "1" ]; then
		APP_ENTITLEMENTS="$(codesign -d --entitlements :- "$APP" 2>/dev/null || true)"
		… ! grep -Fq "Authority=Developer ID Application:"           → fail
		… ! grep -Fq "TeamIdentifier=$REQUIRE_CODESIGN_TEAM_ID"      → fail
		… ! grep -Fq "certificate leaf[subject.OU] = $REQUIRE_CODESIGN_TEAM_ID" → fail
		… grep -Fq "com.apple.security.cs.disable-library-validation" → fail
	fi
fi
```
The last check is ADR-0002's entitlement rejection, mechanised. `release.yml:96-99` sets
`REQUIRE_STABLE_CODESIGN=1`, `REQUIRE_DEVELOPER_ID_CODESIGN=1`, `REQUIRE_CODESIGN_TEAM_ID=XG9SBNWNXT`.

**(c) The `Bundle.module` regression guard** (`:127-178`) — a 45-line `awk` program that tracks
`#if DEBUG` / `#elseif` / `#else` / `#endif` nesting depth across every `Sources/**/*.swift` and
fails if `Bundle.module` appears at `debugDepth == 0`. Rationale (from
`Sources/TermTile/BundleResources.swift:7-16`): SwiftPM's generated `Bundle.module` accessor
`fatalError`s when it can't find the resource bundle, and it looks in exactly two places — inside the
`.app`, and *a hardcoded absolute `.build` path baked in at compile time*. In a CI-built release
that path is `/Users/runner/...`, which exists on no user's machine → **crash on launch**. A locally
built binary appears to work only because its baked-in path happens to resolve.

**(d) Launch proof** (`:180-226`). First it *moves aside* every `.build/**/*_*.bundle` so a local
SwiftPM resource bundle cannot mask a packaging gap (restored on EXIT via `trap cleanup EXIT`).
Then it counts pre-existing crash reports, launches the **inner bundled executable** with an isolated
`HOME`, and polls:
```bash
env HOME="$SMOKE_HOME" CFFIXED_USER_HOME="$SMOKE_HOME" TERMTILE_SELFTEST=1 TERMTILE_GALLERY=1 \
	"$BIN" >"$GALLERY_LOG" 2>&1 &
PID=$!
poll_liveness "gallery"                       # 8 × kill -0, 0.5s apart → must survive ~4s
grep -q "GALLERY shown" "$GALLERY_LOG" || fail "gallery did not render (missing GALLERY shown marker)"
```
then a second launch proving the passive update probe arms and finishes:
```bash
env … TERMTILE_SELFTEST=1 TERMTILE_UPDATE_PROBE_SMOKE=1 "$BIN" >"$UPDATE_PROBE_LOG" 2>&1 &
poll_liveness "update probe"
grep -q "UPDATE_PROBE_SMOKE armed" … || fail
# then up to 10s waiting for "UPDATE_PROBE_SMOKE finished"
after="$(ls "$CRASH_DIR" 2>/dev/null | grep -c "^$APP_NAME" || true)"
[ "$after" -le "$before" ] || fail "a new crash report appeared for $APP_NAME"
```
**Safety invariant, stated at `:8-9` and pinned by a test:** "only ever `kill`s the ONE pid it
spawned — never `pkill`/`killall`."

Those markers are why TRAP-17's check exists: they must be written to unbuffered
`FileHandle.standardError`, because a `print()` to a pipe is block-buffered and is lost when the
harness SIGTERMs the process.

### 4.9 The end-to-end release chain

```
git tag v0.2.6 && git push origin master v0.2.6
   └─ release.yml (on: push tags 'v*')
        checkout (fetch-depth: 0 — build-app.sh needs full history for rev-list --count)
        xcode-select /Applications/Xcode.app
        scripts/fetch-sparkle.sh
        swift test                                     ← same gate as check.yml
        brew install swiftlint && swiftlint --strict
        import Developer ID .p12 into a temp keychain  ← + DeveloperIDG2CA.cer from apple.com
        SHORT_VERSION=${GITHUB_REF_NAME#v} scripts/build-app.sh | tail -1   → app_path
        scripts/test-packaged-app.sh $app_path         ← REQUIRE_DEVELOPER_ID_CODESIGN=1
        scripts/notarize-app.sh $app_path              ← submit/staple/validate/spctl
        ditto -c -k --keepParent $app_path dist/TermTile-$TAG.zip
        (cd dist && shasum -a 256 … | tee ….sha256)    ← basename-relative so `-c` works
        cp release-notes/${TAG#v}.md dist/TermTile-$TAG.md
        generate_appcast --ed-key-file … --embed-release-notes \
          --download-url-prefix https://github.com/.../download/$TAG/ dist/
        rm -f dist/TermTile-$TAG.md                    ← notes are embedded; don't ship the loose .md
        actions/attest-build-provenance@v4 (subject-path: the zip)
        VirusTotal via curl (continue-on-error, skipped if no key)
        gh release create $TAG $ZIP $ZIP.sha256 dist/appcast.xml --notes-file release-notes/…
```

**Ordering is load-bearing** (`docs/NOTARIZATION.md`):
> "That ordering is load-bearing: the zip, checksum, Sparkle appcast, provenance attestation, and
> GitHub release must all refer to the stapled app."

**Required GitHub secrets:** `TERMTILE_RELEASE_SIGNING_CERT_P12_BASE64`,
`TERMTILE_RELEASE_SIGNING_CERT_PASSWORD`, `SPARKLE_ED_PRIVATE_KEY`, `TERMTILE_NOTARY_KEY_P8_BASE64`,
`TERMTILE_NOTARY_KEY_ID`, `TERMTILE_NOTARY_ISSUER_ID`, optional `VIRUSTOTAL_API_KEY`.
**Required repo variable:** `TERMTILE_SIGN_IDENTITY` — validated to start with
`Developer ID Application:` or the job errors (`release.yml:84-87`).

---

## 5. `.github/` — CI

Three workflows, one Dependabot config, one PR template.

### `check.yml` — the every-push gate
```yaml
on: { pull_request:, push: { branches: [master] } }
permissions: { contents: read }
jobs.check.runs-on: macos-15
steps:
  actions/checkout@v7
  sudo xcode-select -switch /Applications/Xcode.app
  swift --version
  scripts/fetch-sparkle.sh      # BEFORE any swift build/test — the binaryTarget has no artifact otherwise
  swift build
  swift test
  brew install swiftlint
  swiftlint --strict
```
Gates: build, tests, strict lint. Least-privilege `contents: read`.

### `semgrep.yml`
```yaml
on: { pull_request:, push: { branches: [master] }, schedule: [{ cron: '0 7 * * 1' }] }
permissions: { contents: read }
jobs.semgrep.runs-on: ubuntu-latest
container: { image: semgrep/semgrep }
run: semgrep ci --config p/security-audit --config p/secrets
```
Comment explains the container: "Semgrep's own action is unavailable on schedule events without a PR
context; run the CLI directly."

### `release.yml` — see §4.9. Trigger `push: tags: ['v*']`. Permissions widened only to what a
release needs:
```yaml
permissions:
  contents: write
  id-token: write
  attestations: write
```

### `dependabot.yml`
```yaml
version: 2
updates:
  - package-ecosystem: github-actions
    directory: /
    schedule: { interval: weekly }
```
Comment: "SwiftPM has no Dependabot ecosystem and the package has no third-party deps; github-actions
keeps the CI workflow action pins current."

### `pull_request_template.md`
Sections: Summary; Verification checklist (`swift build && swift test && swiftlint --strict`, plus
"Report or screenshot evidence attached when UI … changed"); Security notes (no secrets/`.env`
committed; workflow permission or dependency changes explained); Project contract.

**All of this is asserted by `Tests/TermTileKitTests/WorkflowsTests.swift`** — 13 tests reading the
YAML as text, e.g. `"release.yml: notarizes and staples the app before packaging"`,
`"release.yml: release smoke rejects ad-hoc signatures before publishing"`,
`".swiftlint.yml: keeps force_cast strict (not globally disabled)"`.

---

## 6. Source architecture — the three-target split

`Package.swift` (`swift-tools-version: 6.0`, `platforms: [.macOS(.v14)]`):

```swift
products: [.executable(name: "TermTile", targets: ["TermTile"])],
dependencies: [
    .package(url: "https://github.com/400faces/MacFaceKit.git", .upToNextMinor(from: "0.4.2"))
],
targets: [
    .target(name: "TermTileCore"),
    .target(name: "TermTileKit", dependencies: ["TermTileCore"]),
    .executableTarget(
        name: "TermTile",
        dependencies: ["TermTileKit", "TermTileCore", "Sparkle",
                       .product(name: "MacFaceKit", package: "MacFaceKit")],
        resources: [.copy("Resources/AppIcon.png")],
        linkerSettings: [
            .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
        ]),
    .binaryTarget(name: "Sparkle", path: "Vendor/Sparkle.xcframework"),
    .testTarget(name: "TermTileCoreTests", dependencies: ["TermTileCore"]),
    .testTarget(name: "TermTileKitTests", dependencies: ["TermTileKit"]),
    .testTarget(name: "TermTileTests", dependencies: ["TermTile"])
]
```

Three deliberate details: `.copy` (not `.process`) for the icon "takes just the PNG — no SVG
source"; the rpath flag is what makes the embedded framework loadable; `Sparkle` is a **local**
`binaryTarget` because "SPM's remote artifact downloader hangs in some sandboxes".

### 6.1 `TermTileCore` — pure logic (9 files, CoreGraphics only)

| File | Purpose |
|---|---|
| `AppIdentity.swift` | The one name/bundle-id/URL set. `appName`, `bundleID`, `repoURL`, `licenseURL`. URLs use `HEAD`, not a branch, so a rename never 404s. |
| `AXGeometry.swift` | Pure Cocoa(bottom-left) ↔ AX(top-left) frame flip. Takes an injected `displayHeight`. |
| `TileConfig.swift` | Inputs a retile needs: `isEnabled`, `visibleFrame` (already in AX space), `gap`. |
| `TileLayout.swift` | `frames(count:visibleFrame:gap:) -> [CGRect]` — the column-of-2 grid math. |
| `TileEngine.swift` | The retile/reorder **policy**: `retileCommands(...)`, `reorderCommands(...)` → `[FrameCommand]`. No clock, no AX, no state. |
| `FrameCommand.swift` | `(windowID, targetFrame)` — the engine's output unit. |
| `FrameMath.swift` | Pure frame comparison within a per-component epsilon. |
| `TrackedWindow.swift` | `(id: CGWindowID, frame: CGRect)`. |
| `ReorderStrategy.swift` | `enum … String, CaseIterable` — adaptive/swap/shift-by-column/shift-by-row + `displayName`. |

`AppIdentity` deliberately excludes runtime version/build — those come from
`MacFaceKit.AppInfo.fromBundle()`.

### 6.2 `TermTileKit` — system adapters (17 files)

| File | Purpose |
|---|---|
| `WindowSystem.swift` | The **one port**: `protocol WindowSystem: Sendable { func tileableWindows() async -> [TrackedWindow]; func writeFrame(_:to:) async -> Bool }`. Vocabulary is CG types only — imports no ApplicationServices. |
| `AXWindowSystem.swift` | The **production AX adapter** — the only file importing `ApplicationServices` for control. `public actor`. See §7. |
| `TilingActor.swift` | The single actor owning the window system; serializes writes. `activate(config:)`, `reorderDropFresh(_:config:strategy:)`, `trackedWindow(atFresh:)`, `windowFrame(idFresh:)`. |
| `WindowFiltering.swift` | Pure predicate: is this AX window tileable (standard subrole, not minimized, not fullscreen)? Optional inputs **fail CLOSED**. |
| `AccessibilityTrust.swift` | `AXIsProcessTrustedWithOptions` wrapper + the Privacy_Accessibility deep link. `internal`, not public. |
| `AccessibilityState.swift` | `enum { trusted, needsFirstGrant, grantBroken }` — the three fix-it-row states. |
| `PermissionRepairer.swift` | `PermissionRepairScope` / `PermissionRepairReport` / `protocol PermissionRepairing` / `TCCPermissionRepairer` (runs `tccutil reset`). See §7. |
| `MenuBarViewModel.swift` | 20 KB `@MainActor @Observable` — all presentation/composition logic. The view holds none. |
| `SettingsStore.swift` | `protocol SettingsStore: Sendable` + `UserDefaultsSettingsStore` (stores only the `suiteName` String, resolves `UserDefaults` per call — `UserDefaults` isn't `Sendable`). |
| `AppSettings.swift` | The persisted value type. **Every field's init has NO default** so a partial write can't clobber a sibling back to a default. Deliberately excludes `launchAtLogin`. |
| `LoginItem.swift` | `LoginItemStatus` mirror of `SMAppService.Status` + `protocol LoginItem` + `SMAppServiceLoginItem`. Source of truth is the *status*, never a persisted bool. |
| `TargetApps.swift` | `TargetApp` value type + `protocol TargetAppsProviding`. |
| `WorkspaceTargetAppsProvider.swift` | Production adapter over `NSWorkspace`; only `.regular` apps with a bundle id and name. |
| `TargetRunningApplicationResolver.swift` | Prefers the same `.regular` process when several share a bundle id. |
| `TargetAppForegrounding.swift` | `TargetForegroundResult` enum + `protocol TargetAppForegrounding`. |
| `WorkspaceTargetAppForegrounder.swift` | Production activation adapter + a generic `TargetAppForegroundCoordinator<App: RunningAppActivating>`. |
| `HotKeyMonitor.swift` | Carbon `RegisterEventHotKey` global hotkey. **Needs no Accessibility grant** — independent of TCC. `HotKeyConfig` (keyCode + Carbon modifier mask) is the testable seam. |
| `DragMonitor.swift` | Global left-button `CGEventTap`. `CGPreflightListenEventAccess()` / `CGRequestListenEventAccess()`. |
| `DragReorderControlling.swift` | The `@MainActor` port: `start()`, `stop()`, `inputMonitoringGranted`, `requestInputMonitoring()`. |
| `DragReorderController.swift` | The concrete `@MainActor` adapter wrapping `DragMonitor`. |
| `OwnedPaths.swift` | The **exact** `~/Library` literals the app owns — never a glob. `library` root is injected. |
| `Uninstaller.swift` | Deregister login item → TCC reset → trash data → trash bundle. Uses `SettingsStore.purge()`, not a loose plist trash (cfprefsd would rewrite it). |

**Kit is UI-free.** It imports `Foundation`/`CoreGraphics`/`AppKit`/`ApplicationServices`/`Carbon`
but never `SwiftUI`, which is what makes `MenuBarViewModel` unit-testable.

### 6.3 `TermTile` — the SwiftUI shell (7 files)

| File | Purpose |
|---|---|
| `TermTileApp.swift` | `@main struct … : App` — the composition root. All production wiring. |
| `MenuBarContent.swift` | The popover view. Thin renderer over the VM; every control routes back through a VM method. |
| `TermTileGlyph.swift` | The menu-bar label: a composited `NSImage` (glyph + optional attention dot) with a drawn fallback. |
| `HotKeyRecorder.swift` | `NSViewRepresentable` click-to-record shortcut field (SwiftUI has none). |
| `Updater.swift` | `@MainActor @Observable final class Updater: NSObject` — owns Sparkle. |
| `TermTileUserDriver.swift` | The `SPUUserDriver` → `MacFaceKit.UpdateWindowController` adapter. |
| `UpdateAvailability.swift` | `enum { unknown, checking, available(version:), unavailable, failed }` + `hasAvailableUpdate`. |
| `BundleResources.swift` | `Bundle.packagedResourceURL(_:withExtension:)` — `Bundle.main` first, `Bundle.module` only `#if DEBUG`. |

#### The MenuBarExtra setup (`TermTileApp.swift:183-190`)
```swift
var body: some Scene {
    MenuBarExtra {
        MenuBarContent(viewModel: viewModel, updater: updater, appInfo: appInfo)
    } label: {
        TermTileGlyph(hasAvailableUpdate: updater.availability.hasAvailableUpdate)
    }
    .menuBarExtraStyle(.window)
}
```
`.window` style (a real popover panel, not an NSMenu) is what lets arbitrary SwiftUI controls —
Steppers, Pickers, an `NSViewRepresentable` recorder — work.

#### Composition root, in `init()` not `applicationDidFinishLaunching`
`TermTileApp.swift:12-14`: "`init()` is the reliable delegate hook (the SwiftUI adaptor never calls
`applicationDidFinishLaunching` — RememBar template)". The delegate exists anyway and re-asserts the
policy as a belt:
```swift
@NSApplicationDelegateAdaptor(TermTileAppDelegate.self) private var appDelegate
…
NSApplication.shared.setActivationPolicy(.accessory)   // in init, line 63
…
final class TermTileAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
```

Wiring order inside `init()`:
1. Read env: `TERMTILE_SELFTEST`, `TERMTILE_GALLERY`. Selftest uses a **dedicated UserDefaults
   suite** (`dev.ecn.apps.termtile.selftest`) so it never pollutes real prefs.
2. Build `settings` and `loginItem` **once** so the Uninstaller acts on the same instances the VM uses.
3. `makePrivacyComposition(...)` — returns `nil` uninstaller/repairer under selftest/gallery so a dev
   clicking Uninstall in the gallery can't trash real prefs.
4. `appInfo = AppInfo.fromBundle()`.
5. Construct `MenuBarViewModel` with every port injected, including
   `makeActor: { bundleID in TilingActor(system: AXWindowSystem(bundleID: bundleID), epsilon: eps) }`.
6. `setActivationPolicy(.accessory)`.
7. `hotKeyMonitor = Self.makeHotKeyMonitor(vm:active:)` — retained for process life.
8. **Post-init** `viewModel.setDragReorder(DragReorderController(...))` — its closures capture the VM,
   so it cannot exist at VM-init; same cycle-break as `vm.onHotKeyChanged`.
9. Env hooks: `runSelftest`, `TERMTILE_TILE_ONCE`, `armUpdateAvailabilityProbeIfAllowed`,
   `armAutoUpdateCheckIfRequested`, `armGalleryUpdateAttentionIfRequested`, `showGallery`.

The AX visible frame is resolved once, on the main-actor init (`TermTileApp.swift:221-224`):
```swift
private static func originAXVisibleFrame() -> CGRect {
    guard let screen = NSScreen.screens.first else { return .zero }
    return AXGeometry.axFrame(fromCocoa: screen.visibleFrame, displayHeight: screen.frame.height)
}
```
`.screens.first` (the ORIGIN screen), never `.main` — `.main` is the key window's screen and moves
with focus.

#### The "app navbar" / menu UI structure (`MenuBarContent.swift`)
One `AppIdentityCard` wrapping a stack of `SectionCard`s, then the notice, then the hero:
```
AppIdentityCard(name:version:subtitle:actions:links:) {
    SectionCard("Target")     → LabeledContent("Target app") { Picker }
    SectionCard("Rearrange")  → Gap Stepper, "Bring app forward" Toggle,
                                optional warning Label, Shortcut HotKeyRecorder
    SectionCard("Drag")       → "Reorder windows on drag" Toggle,
                                conditional strategy Picker,
                                conditional NoticeCard("Input Monitoring required")
    SectionCard("General")    → "Launch at login" Toggle
    accessibilityNotice       → NoticeCard, switched on viewModel.accessibilityState
    PrimaryButton("Rearrange now", systemImage:, trailing: shortcut, enabled: trusted)
}
.frame(width: 280)
.background(Tokens.panel)
```
Ordering rule, stated at `MenuBarContent.swift:105-108`: the blocker notice sits "right above the
action it gates", and the primary action comes last — "after the settings it operates on (configure,
then tile)".

The `···` overflow is `actions:` on the card (`MenuBarContent.swift:139-150`):
```swift
MenuAction(title: "Check for Updates", systemImage: "arrow.triangle.2.circlepath",
           enabled: updater.canOpenUpdateCheck,
           attention: updater.availability.hasAvailableUpdate,
           attentionAccessibilityHint: "Update available") { updater.checkForUpdates() },
MenuAction(title: "Quit TermTile", systemImage: "power") { NSApplication.shared.terminate(nil) },
MenuAction(title: "Uninstall TermTile…", systemImage: "trash", destructive: true) {
    DispatchQueue.main.async { runUninstallFlow() }
}
```
Uninstall defers to the next tick so the popover closes first. The uninstall confirm/outcome flow
uses imperative `NSAlert`s in their own windows — *not* SwiftUI modals anchored to the popover, which
auto-dismisses on focus loss and orphans the dialog (`MenuBarContent.swift:175-179`). Confirmed
removal always ends in `exit(0)`, never `NSApp.terminate` (a graceful quit lets cfprefsd re-flush the
purged prefs).

Trust is re-probed on **every panel open**, because `MenuBarExtra(.window)` keeps the view alive
across opens so `.onAppear` fires once per process (`MenuBarContent.swift:117-123`):
```swift
.onAppear { viewModel.refreshTrust() }
.onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
    viewModel.refreshTrust()
}
```

#### Sparkle + `UpdateWindowController` integration
`Updater` is a lazy `@MainActor @Observable` class with three inits — production, and two
test-injection variants taking a `startSession` closure. `startSparkleSession`
(`Updater.swift:128-153`):
```swift
let preferStock = ProcessInfo.processInfo.environment["TERMTILE_STOCK_UPDATER"] != nil
if !preferStock {
    let custom = SPUUpdater(hostBundle: .main, applicationBundle: .main,
                            userDriver: driver, delegate: delegate)
    if (try? custom.start()) != nil { return StartedUpdateSession(updater: custom) }
}
// fall back so the user can still update
let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: delegate,
                                              userDriverDelegate: nil)
return StartedUpdateSession(updater: controller.updater, retainedObject: controller)
```
Two paths from the UI:
- **Foreground:** `checkForUpdates()` → `SPUUpdater.checkForUpdates()` → Sparkle drives
  `TermTileUserDriver` → `MacFaceKit.UpdateWindowController`.
- **Passive:** `refreshAvailability()` → `checkForUpdateInformation()` (Sparkle's **non-presenting**
  path) → the `SPUUpdaterDelegate` callbacks set `availability`, which drives the menu-bar dot and
  the `···` attention dot. Guarded so it never runs while `sessionInProgress`.

The delegate conformance is the whole state machine (`Updater.swift:156-172`):
```swift
func updater(_:didFindValidUpdate item: SUAppcastItem) { recordAvailableUpdate(version: item.displayVersionString) }
func updaterDidNotFindUpdate(_:error:)                 { recordNoUpdateFound() }
func updaterDidNotFindUpdate(_:)                       { recordNoUpdateFound() }
func updater(_:didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
    guard updateCheck == .updateInformation else { return }
    recordPassiveAvailabilityCheckFinished(error: error)
}
```
`TermTileUserDriver` is 117 lines of pure translation — see the mapping table in §9.4. Its whole
justification (`TermTileUserDriver.swift:11-17`): the window, morph, escape/ack and progress math live
once in MacFaceKit; the Sparkle-coupled shim is app-local "because Sparkle is a vendored binaryTarget
that can't live in the public kit."

#### MacFaceKit usage in TermTile — the exact surface consumed
`AppIdentityCard`, `SectionCard`, `NoticeCard` (both inits), `PrimaryButton`, `MenuAction`,
`IdentityLink.link` / `.license`, `AppInfo.fromBundle()` / `AppInfo(version:build:)`,
`UpdateWindowController`, `ReleaseNotesParser.embeddedItems` / `.items(from:)`,
`ReleaseNotesFormat(sparkleFormat:)`, and tokens `Tokens.panel`, `.caption`, `.warning`,
`.attentionDot`, `.nsField`, `.nsAccent`, `.nsLine`, `.nsText`.

---

## 7. The AX / permission pattern — request, detect, recover

This is the part Mumbler needs almost verbatim (it will want Accessibility for text injection, plus
Microphone and Speech Recognition).

### 7.1 Detection — non-prompting, read-only

`Sources/TermTileKit/AccessibilityTrust.swift` (whole file, 22 lines):
```swift
// @preconcurrency: the SDK imports kAXTrustedCheckOptionPrompt as a mutable global
// (`public var … : Unmanaged<CFString>`), which Swift 6 strict concurrency rejects on plain import.
@preconcurrency import ApplicationServices
import Foundation

enum AccessibilityTrust {
    static let settingsDeepLink = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    static func isTrusted(prompting: Bool) -> Bool {
        let key: CFString = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
        return AXIsProcessTrustedWithOptions([key: prompting] as CFDictionary)
    }
}
```
Two non-obvious facts recorded here:
- `@preconcurrency import` is **required** under Swift 6 — a plain import fails to compile.
- Even `prompting: false` **registers a denied TCC entry** when called from a bundled `.app`
  (spike-02 finding). So any call is observable by TCC.

It is exposed to the shell only through the VM, never imported by the executable:
```swift
// MenuBarViewModel.swift:375
public static let liveTrustProbe: @Sendable () -> Bool = { AccessibilityTrust.isTrusted(prompting: false) }
// MenuBarViewModel.swift:234
public var accessibilitySettingsURL: URL { AccessibilityTrust.settingsDeepLink }
```
`prompting: false` is deliberate: "a read-only status check that never pops the grant dialog on a
menu open (the user reaches System Settings via the fix-it row's `Link` instead)."

### 7.2 The three-state model — first grant vs broken grant

`AccessibilityState.swift`:
```swift
public enum AccessibilityState: Equatable, Sendable {
    case trusted
    case needsFirstGrant
    case grantBroken
}
```
Derived in the VM from the live probe plus a **persisted latch** (`MenuBarViewModel.swift:46-49`):
```swift
public var accessibilityState: AccessibilityState {
    if isAccessibilityTrusted { return .trusted }
    return wasTrusted ? .grantBroken : .needsFirstGrant
}
```
The latch (`MenuBarViewModel.swift:215-222`):
```swift
private func syncTrust() {
    isAccessibilityTrusted = isTrustedProbe()
    if isAccessibilityTrusted && !wasTrusted {
        wasTrusted = true
        persist()
    }
    syncReorderMonitor()   // trust change may enable/disable the drag monitor
}
```
Latched on the **persisted flag, not a probe edge**, so it fires for a user who was already trusted
at launch. The honest hedge is written into the doc comment: a deliberate revoke and a
moved/duplicate-bundle break are indistinguishable via `AXIsProcessTrusted`, so the `grantBroken`
copy covers both.

### 7.3 Recovery — `tccutil reset` scoped to this bundle only

`PermissionRepairer.swift` — the whole recovery primitive:
```swift
public enum PermissionRepairScope: Equatable, Sendable {
    case accessibility
    case inputMonitoring
    public var label: String { … "Accessibility" / "Input Monitoring" }
    var tccutilService: String {
        switch self {
        case .accessibility:   "Accessibility"
        case .inputMonitoring: "ListenEvent"      // ← the TCC service name, NOT the UI label
        }
    }
}

@MainActor public protocol PermissionRepairing: AnyObject {
    @discardableResult func reset(_ scopes: [PermissionRepairScope]) -> [PermissionRepairReport]
}

@MainActor public final class TCCPermissionRepairer: PermissionRepairing {
    public typealias Runner = (_ executable: String, _ arguments: [String]) -> Int32
    private static let processTimeout: DispatchTimeInterval = .seconds(2)
    private static let timedOutExitCode: Int32 = 124

    public convenience init(bundleID: String = AppIdentity.bundleID)
    public init(bundleID: String, runner: @escaping Runner)

    public func reset(_ scopes: [PermissionRepairScope]) -> [PermissionRepairReport] {
        scopes.map { scope in
            let exitCode = runner("/usr/bin/tccutil", ["reset", scope.tccutilService, bundleID])
            return PermissionRepairReport(scope: scope, exitCode: exitCode)
        }
    }
}
```
Four things worth copying exactly:
1. **`tccutil reset <SERVICE> <bundleID>`** — always scoped to this bundle id. Never a bare
   `tccutil reset Accessibility` (which would nuke every app's grant).
2. **The `Runner` closure is injected** so tests prove the exact argv without touching the real TCC
   database.
3. **Bounded wait** — `DispatchSemaphore` + `terminationHandler`, 2-second timeout, `terminate()` on
   expiry, exit code 124. There is a test named `"TCC repair process has a bounded wait"`.
4. **It does not grant anything.** The doc comment: "This does not grant permission; it only clears
   TermTile's own old rows so the current signed app can be granted normally in System Settings."

VM entry points (`MenuBarViewModel.swift:177-193`):
```swift
@discardableResult
public func repairAccessibilityPermission() -> [PermissionRepairReport] {
    guard let permissionRepairer else { return [] }
    let reports = permissionRepairer.reset([.accessibility])
    refreshTrust()
    return reports
}

@discardableResult
public func repairInputMonitoringPermission() -> [PermissionRepairReport] {
    guard let permissionRepairer else { return [] }
    let reports = permissionRepairer.reset([.inputMonitoring])
    syncReorderMonitor()
    return reports
}
```
`permissionRepairer` is **optional and nil under selftest/gallery**, so a dev harness can never
mutate the real permission database.

### 7.4 The UX — three notices, three different asks

`MenuBarContent.swift:154-173`:
```swift
switch viewModel.accessibilityState {
case .trusted:
    EmptyView()
case .needsFirstGrant:
    NoticeCard(title: "Accessibility access required",
               message: "TermTile needs Accessibility permission to arrange windows. "
               + "Open Settings and allow TermTile.",
               linkLabel: "Allow Accessibility", url: viewModel.accessibilitySettingsURL)
case .grantBroken:
    NoticeCard(title: "Accessibility access needs reset",
               message: "Settings may show TermTile enabled for an older build. "
               + "Reset the saved entry, then allow this copy.",
               actionLabel: "Reset & Open Settings", actionSystemImage: "arrow.clockwise") {
        _ = viewModel.repairAccessibilityPermission()
        NSWorkspace.shared.open(viewModel.accessibilitySettingsURL)
    }
}
```
And the Input Monitoring one (`MenuBarContent.swift:88-96`):
```swift
if viewModel.reorderNeedsInputMonitoring {
    NoticeCard(title: "Input Monitoring required",
               message: "Reorder-on-drag needs Input Monitoring to detect when you drag a window. "
               + "Open Settings and allow TermTile.",
               actionLabel: "Allow Input Monitoring") {
        _ = viewModel.repairInputMonitoringPermission()
        NSWorkspace.shared.open(viewModel.inputMonitoringSettingsURL)
    }
}
```
The repair **always runs before opening Settings** — reset the stale row, then show the pane so the
user can grant the current signed copy. `repairAccessibilityPermission()` deliberately does *not*
request the AX prompt, "because that can leave both a Settings pane and a stale modal dialog on
screen."

### 7.5 Input Monitoring is a separate, differently-shaped grant

`DragMonitor.swift:61,67`:
```swift
public static var inputMonitoringGranted: Bool { CGPreflightListenEventAccess() }
public static func requestInputMonitoring()    { _ = CGRequestListenEventAccess() }
```
Preflight is non-prompting **and does not register the app in the pane**; only the *request* adds it.
So the VM requests once when the feature is opted into but not granted
(`MenuBarViewModel.swift:141-153`):
```swift
private func syncReorderMonitor() {
    guard let dragReorder else { return }
    if reorderOnDrag, isAccessibilityTrusted, dragReorder.inputMonitoringGranted {
        dragReorder.start()
    } else {
        if reorderOnDrag, !dragReorder.inputMonitoringGranted {
            dragReorder.requestInputMonitoring()
        }
        dragReorder.stop()
    }
}
```
Deep links:
- Accessibility → `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`
- Input Monitoring → `x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent`
- Privacy root (uninstall fallback) → `x-apple.systempreferences:com.apple.preference.security`

Note the pattern: the **TCC service name** (`ListenEvent`) differs from both the UI label
("Input Monitoring") and the deep-link anchor (`Privacy_ListenEvent`). For Mumbler the analogous
triples are `Microphone` / `Privacy_Microphone` and `SpeechRecognition` /
`Privacy_SpeechRecognition` — **UNVERIFIED**, I did not confirm those service names on this machine.

### 7.6 The AX adapter itself

`AXWindowSystem.swift` is a `public actor` — an actor "so it satisfies the `Sendable` port and
serializes AX writes; each call resolves the running app fresh, so app launch/quit between calls is
handled without stale handles."

The frame write (`AXWindowSystem.swift:66-82`) carries three hard-won workarounds:
```swift
public func writeFrame(_ id: CGWindowID, to target: CGRect) async -> Bool {
    guard let appEl = appElement(), let win = windowElement(id) else { return false }

    let euiWasOn = (copyAttr(appEl, kAXEnhancedUserInterface) as? Bool) == true
    if euiWasOn { setBool(appEl, kAXEnhancedUserInterface, false) }
    defer { if euiWasOn { setBool(appEl, kAXEnhancedUserInterface, true) } }

    var size = target.size
    var origin = target.origin
    guard let sizeVal = AXValueCreate(.cgSize, &size),
          let posVal = AXValueCreate(.cgPoint, &origin) else { return false }

    let s1 = AXUIElementSetAttributeValue(win, kAXSizeAttribute as CFString, sizeVal)
    let p  = AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, posVal)
    let s2 = AXUIElementSetAttributeValue(win, kAXSizeAttribute as CFString, sizeVal)
    return s1 == .success && p == .success && s2 == .success
}
```
1. **size → position → size** (Rectangle's cross-display clamp workaround).
2. **`AXEnhancedUserInterface` disabled around the write**, restored via `defer` — and the comment
   explicitly distinguishes this from TRAP-12: "this is a normally-returning actor method, so `defer`
   DOES run on every path (unlike AXProbe's `exit()`)."
3. **`_AXUIElementGetWindow`** — the one private symbol the architecture permits itself
   (`AXWindowSystem.swift:105-106`), imported as a bodyless external symbol:
```swift
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ el: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError
```
Also honest about what it does **not** do: "A `.success` write can still be silently size-clamped
(iTerm2 73×67, spike-04 — err=0 even when clamped); detecting that is the CALLER's readback concern
… no clamp compensation (YAGNI)."

---

## 8. Tests — three targets, 278 `@Test` declarations, 35 `@Suite`s

Framework is **swift-testing** (`import Testing`, `@Suite`/`@Test`/`#expect`/`#require`/`Issue.record`),
not XCTest.

### 8.1 `TermTileCoreTests` (7 files) — pure-value tests, no mocks
`AXGeometryTests`, `AppIdentityTests` ("App identity — one name everywhere"), `FrameMathTests`,
`ReorderStrategyDisplayTests`, `TileEngineTests`, `TileLayoutTests` ("TileLayout — column-of-2
tiling"), `TileReorderTests` (14 KB — the strategy permutations). Imports: `@testable import
TermTileCore`, `CoreGraphics`, `Testing`. Nothing else — no AppKit, no fakes needed.

### 8.2 `TermTileKitTests` (20 files) — port fakes + text-invariant tests
Four in-memory fakes, each its own file, named `InMemory*`:
`InMemoryLoginItem.swift`, `InMemorySettingsStore.swift`, `InMemoryTargetAppsProvider.swift`,
`InMemoryWindowSystem.swift`. That is the whole mocking strategy — no mocking library, no
monkeypatching; the ports exist precisely so a struct can stand in.

Behavioural suites: `MenuBarViewModelTests` (43 KB — the biggest file in the repo),
`SettingsStoreTests`, `LoginItemTests`, `TilingActorTests`, `UninstallerTests`, `OwnedPathsTests`,
`PermissionRepairerTests`, `DragMonitorTests`, `HotKeyMonitorTests`, `WindowFilteringTests`,
`AccessibilityTrustTests` (titled "stable invariants only (trust value is environment-dependent)" —
an honest scope limit), `AXWindowSystemTests` ("adapter invariants (non-live)"),
`TargetAppForegrounderTests`, `TargetRunningApplicationResolverTests`,
`WorkspaceTargetAppsProviderTests`.

**The unusual and highly transferable ones — shell scripts and YAML tested as text:**
- `PackagingScriptsTests.swift` (25 KB, 20 tests) — reads `scripts/*.sh` as strings and asserts
  line-scoped invariants. Root is resolved by walking up from `#filePath` until a directory contains
  `Package.swift` (robust against CWD). Examples:
  `"build-app.sh: sign lines use $SIGN_IDENTITY (ad-hoc fallback), no --deep; verify has --deep AND --strict"`,
  `"build-app.sh: CFBundleVersion uses git rev-list --count, never dots-stripped"`,
  `"test-packaged-app.sh: launches (kill -0) + verifies signature, never pkill/killall"`,
  `"notarize-app.sh: submits, staples, validates, and Gatekeeper-assesses the app"`,
  `"packaging scripts exist and are executable"`.
  The header states the boundary: "Each assertion pins one hard-won packaging lesson as a POSITIVE,
  line-scoped invariant so it can't be satisfied vacuously by an empty/stub file … The LIVE proof
  that the script actually produces a launchable, correctly-signed bundle is #13a's PROVE … not here."
  Two tests go further and **execute** `notary-status.sh` against a generated fake `xcrun` on `PATH`
  that logs its argv and `exit 97`s on `submit`.
- `WorkflowsTests.swift` (14 KB, 13 tests) — the same treatment for `check.yml`, `release.yml`,
  `semgrep.yml`, `.swiftlint.yml`.
- `ReleaseReadinessTests.swift` (28 KB, 30 tests) — asserts the *documentation* is truthful: one test
  per `release-notes/<version>.md`, plus `"handoff records the current MacFaceKit dependency line"`,
  `"release docs do not claim public CI can self-sign releases"`,
  `"public docs version-qualify Developer ID notarized and stapled distribution"`,
  `"Sparkle remains confined to the executable target"`,
  `"menu identity links do not require MacFaceKit SwiftPM resource bundles at runtime"`. It parses
  `Package.resolved` JSON and does a real semver floor/ceiling comparison for the MacFaceKit pin.

### 8.3 `TermTileTests` (11 files) — testing an **executable** target

The convention, from `Package.swift`:
```swift
// Shell-level tests (the branded update dialog render — mirrors RememBar's executable-linked
// test target). @testable-imports the TermTile executable.
.testTarget(name: "TermTileTests", dependencies: ["TermTile"])
```
Then in the test files: `@testable import TermTile`. This works because SwiftPM links the executable
target's objects into the test bundle; `@main` is not re-entered. The tests reach `internal` types —
`Updater`, `TermTileUserDriver`, `MenuBarContent`, `TermTileImage`, `UpdateAvailability` — none of
which are `public`.

Files and what they assert:
| File | Asserts |
|---|---|
| `MenuBarContentRenderTests` | Renders the real `MenuBarContent` through `ImageRenderer` at scale 2, twice (update available / not), and asserts **same pixel dimensions but non-zero changed pixels** — i.e. the indicator appears without resizing the panel. |
| `MenuBarContentAccessibilityTests` | Accessibility labels/hints on the panel. |
| `TermTileGlyphTests` (9.5 KB) | The composited menu-bar glyph — dot placement, colour scheme, fallback. |
| `UpdateDialogRenderTests` | The branded dialog renders. |
| `PrimaryButtonRenderTests` | Renders `PrimaryButton` and, **only if `TERMTILE_RENDER_DIR` is set**, writes `primary_button.png` — a render test that doubles as a screenshot generator. |
| `UpdateDriverWiringTests` | Drives the `SPUUserDriver` callbacks in order and asserts the `UpdateWindowController.model` morphs: `.progress("Downloading update…")` → fraction 0.25 after 250/1000 bytes → `.progress("Preparing update…")` → 0.5 → `.ready` → `.progress("Installing…")`, fraction nil → `close()`. **No Sparkle rig, no server, no relaunch.** |
| `UpdaterAvailabilityCallbackTests`, `UpdaterObservationTests`, `UpdaterProbeTests` | The passive-probe state machine, via `Updater(startSession:)` injection. |
| `UpdateAvailabilityTests` | The enum's `hasAvailableUpdate`. |
| `AppKitAPITests` | "TermTile AppKit API use" — pins which AppKit APIs the shell is allowed to touch. |

Note `TermTileTests` also does `@testable import MacFaceKit` (in `UpdateDriverWiringTests`) to read
the controller's `internal` `model`. That works because MacFaceKit is a source dependency compiled in
the same build.

**The injection seam that makes the executable testable** — `Updater` has three inits, two of which
exist purely for tests (`Updater.swift:52-65`):
```swift
init(startSession: @escaping (TermTileUserDriver) -> StartedUpdateSession?)
override init()                                                    // production
init(startSession: @escaping (TermTileUserDriver, any SPUUpdaterDelegate) -> StartedUpdateSession?)
```
so a test writes `Updater(startSession: { _ in nil })` and gets a real `Updater` with no Sparkle.

---

## 9. MacFaceKit — the design system a new app consumes

*(Inventoried by a parallel read-only agent against `/Users/evancnavarro/Developer/MacFaceKit`.)*

### 9.1 Where it lives, and which version

| Path | Exists | HEAD |
|---|---|---|
| `/Users/evancnavarro/Developer/MacFaceKit` | yes | `c430176` = tag **v0.4.2** |
| `/Users/evancnavarro/Developer/termtile/.build/checkouts/MacFaceKit` | yes | same commit `c430176` |
| `/Users/evancnavarro/Developer/400faces/MacFaceKit` | **no** — that dir holds `b3games`, `basemorph`, `platform`, `pycasso` only | — |

All checkouts are the same code (`rev-parse HEAD` identical; `diff -rq` clean). The termtile
checkout's `git describe` reads `v0.3.1-7-g…` only because its local tag refs are stale.
`Package.resolved` confirms `"revision": "c430176…", "version": "0.4.2"`.
Remote: `https://github.com/400faces/MacFaceKit.git`, default branch `master`.

### 9.2 Its `Package.swift`

```swift
// swift-tools-version: 6.0
let package = Package(
    name: "MacFaceKit",
    platforms: [.macOS(.v14)],
    products: [.library(name: "MacFaceKit", targets: ["MacFaceKit"])],
    targets: [
        .target(name: "MacFaceKit", resources: [.process("Resources")]),
        .testTarget(name: "MacFaceKitTests", dependencies: ["MacFaceKit"])
    ]
)
```
**Zero external dependencies** — deliberately, and notably **no Sparkle**: the kit stays Sparkle-free
so consumers don't end up with two copies. 22 source files, 1753 lines.

### 9.3 Every public symbol a new app can consume

**Views** (all `public struct … : View`; exact initializers):
```swift
ActionRow(title:systemImage:destructive:enabled:action:)
AppHeader(name:version:bundledIcon:showsMadeWith:trailing:)          // + EmptyView-Trailing overload
AppIconView(bundledImage:fallbackMonogram:)
AppIdentityCard(name:version:subtitle:bundledIcon:showsMadeWith:actions:links:content:)
AppIdentityCard(name:version:repoURL:licenseURL:subtitle:…)          // ⚠ see caveat below
AttentionDot(size:color:)
ActionPillButton(title:tint:action:)
ExternalLink(_:_:)                                                    // both args unlabeled
GhostIconButton(hitSize:restColor:hoverColor:fill:action:label:)     // + systemName: convenience
GhostGlyph                                                            // no public init
IconButton(systemImage:size:active:attention:accessibilityHint:action:)
LearnMoreLink(displayText:url:prefix:)
LinkButton(_:url:systemImage:) / (_:url:image:) / (_:url:icon:)
LinkButton(_:systemImage:action:) / (_:image:action:) / (_:icon:action:)
LinkButton.Icon { case symbol(String); case image(Image) }
MadeWithSignoff() ; RobotGlyph(color:)
MenuRow(title:systemImage:destructive:enabled:attention:attentionAccessibilityHint:action:)
OverflowMenu(_ actions:width:)
PrimaryButton(_:systemImage:trailing:enabled:action:)
SectionCard(_:content:)
NoticeCard(title:message:linkLabel:url:)
NoticeCard(title:message:actionLabel:actionSystemImage:action:)      // ← added in v0.4.2
UpdateActionButton / UpdateProgressBar / ReleaseNotesSection / UpdateDialog
```
There are **no public view modifiers** except `UpdateDialog.icon(_:)`.

**Tokens** (`public enum Tokens`, all `CGFloat`):
`micro 4`, `space 8`, `radius 8`, `control 34`, `controlButton 26`, `attentionDot 7`,
`iconHeader 64`, `gap 16`, `inset 10`, `pad 14`.

**Colors** (fixed-dark, **not** system-adaptive — you must paint `Tokens.panel` yourself):
`panel`, `field`, `row`, `rowActive`, `line`, `lineStrong`, `text`, `muted`, `quiet`, `warning`,
`destructive`, `accent`, `updateWindow`.
`NSColor` mirrors for AppKit views: `nsPanel`, `nsField`, `nsRow`, `nsLine`, `nsText`, `nsMuted`,
`nsAccent`, `nsUpdateWindow` — note there is **no** `nsRowActive`/`nsLineStrong`/`nsQuiet`/
`nsWarning`/`nsDestructive`.

**Typography** — `title` (18 semibold), `body` (13), `caption` (12), `label` (10 semibold). All
`Font.system`. **No custom fonts ship; no font registration exists or is needed.**

**Non-View types:** `AppInfo` (`version`, `build`, `displayVersion`, `from(infoDictionary:)`,
`fromBundle(_:)`), `MenuAction`, `IdentityLink` (+ `.github(_:)`, `.license(_:)`, `.link(_:_:systemImage:)`),
`ReleaseNotesFormat` (+ `init(sparkleFormat:)`), `ReleaseNotesParser` (`items(from:format:)`,
`items(from:Data:format:)`, `embeddedItems(releaseNotesURL:description:format:)`), `Brand.github`,
`IconButtonStyle`, `UpdateWindowController`.

**Extensions:** only three, all internal-to-the-package generic constraints. **MacFaceKit adds
nothing to `Bundle`, `Color`, `View`, or `NSImage`.** The `Bundle.packagedResourceURL` helper lives in
the *consumer*, not the kit — copy it.

**Resources:** exactly one file, `Resources/github.pdf` (1443 bytes), loaded lazily via
`Bundle.module` by `Brand.github`.

### 9.4 `UpdateWindowController` — the update dialog

```swift
@MainActor
public final class UpdateWindowController: NSObject, NSWindowDelegate {
    public init(appName: String, icon: NSImage?)
    public func showPermission(onAllow:onDecline:)
    public func showChecking(onCancel:)
    public func showAvailable(version:currentVersion:notes:onInstall:onRemindLater:)
    public func updateReleaseNotes(_ notes: [String])
    public func showDownloadStarting(onCancel:)
    public func setExpectedContentLength(_ length: UInt64)
    public func addReceivedBytes(_ length: UInt64)
    public func showPreparing()
    public func updateProgress(_ fraction: Double)
    public func showInstalling()
    public func showReady(onRestart:onDismiss:)
    public func showUpToDate(version:) async      // suspends until acknowledged
    public func showError(message:) async         // suspends until acknowledged
    public func showInFocus()
    public func close()
}
```
The state model (`UpdateFlowModel`, 7-case `Screen`) is **internal** — a host drives the controller
only through these semantic calls. It owns an `NSWindow` (400×220 initial, transparent titlebar,
`.darkAqua`, `Tokens.nsUpdateWindow` background, movable by background) hosting SwiftUI, animates
every transition with `withAnimation(.easeInOut(duration: 0.22))`, and re-fits the window to
`contentView.fittingSize` about its own centre — the "morph".

Two behaviours a host must respect: **escape bookkeeping** (each `show*` arms a traffic-light escape;
pressing a button disarms it first, so it can't double-fire) and the **async ack states**
(`showUpToDate`/`showError` suspend on a `CheckedContinuation`; `close()` resumes it so the task
can't leak). Progress math is owned by the controller — `expected == 0` yields a `nil` fraction =
indeterminate bar.

**Full Sparkle → controller mapping** (as implemented in `TermTileUserDriver.swift`):

| `SPUUserDriver` callback | Controller call |
|---|---|
| `show(_:reply:)` | `showPermission(onAllow:onDecline:)` |
| `showUserInitiatedUpdateCheck(cancellation:)` | `showChecking(onCancel:)` |
| `showUpdateFound(with:state:reply:)` | `showAvailable(version:currentVersion:notes:onInstall:onRemindLater:)` |
| `showUpdateReleaseNotes(with:)` | `ReleaseNotesParser.items(from: data)` → `updateReleaseNotes(_:)` |
| `showUpdateNotFoundWithError(_:) async` | `await showUpToDate(version:)` |
| `showUpdaterError(_:) async` | `await showError(message:)` |
| `showDownloadInitiated(cancellation:)` | `showDownloadStarting(onCancel:)` |
| `showDownloadDidReceiveExpectedContentLength(_:)` | `setExpectedContentLength(_:)` |
| `showDownloadDidReceiveData(ofLength:)` | `addReceivedBytes(_:)` |
| `showDownloadDidStartExtractingUpdate()` | `showPreparing()` |
| `showExtractionReceivedProgress(_:)` | `updateProgress(_:)` |
| `showReady(toInstallAndRelaunch:)` | `showReady(onRestart:onDismiss:)` |
| `showInstallingUpdate(withApplicationTerminated:retryTerminatingApplication:)` | `showInstalling()` |
| `showUpdateInstalledAndRelaunched(_:) async` | `close()` |
| `dismissUpdateInstallation()` | `close()` |
| `showUpdateInFocus()` | `showInFocus()` |

### 9.5 ⚠ The `Bundle.module` trap — do not use `IdentityLink.github`

The `AppIdentityCard(name:version:repoURL:licenseURL:…)` convenience init calls
`IdentityLink.github(_:)` → `Brand.github` → `Bundle.module`. SwiftPM's generated accessor
`fatalError`s if it can't find the resource bundle, and a hand-packaged `.app` doesn't carry it. The
shipping consumer routes around it (`MenuBarContent.swift:130-135`):
```swift
private var identityLinks: [IdentityLink] {
    [ IdentityLink.link("GitHub", AppIdentity.repoURL, systemImage: "globe"),
      IdentityLink.license(AppIdentity.licenseURL) ]
}
```
**Use the 8-arg init with explicit `links:`.** (The crash itself is per the in-repo comments; neither
I nor the sub-agent reproduced it — **UNVERIFIED**. But the avoidance is what the shipped app does,
and there is a test named `"menu identity links do not require MacFaceKit SwiftPM resource bundles at
runtime"`.)

### 9.6 Versioning policy and the 0.4.x line

No `CHANGELOG` file. Policy is in MacFaceKit's `HANDOFF.md`: semver — **minor for new
components/APIs, patch for fixes**; tag `vX.Y.Z` and push (400faces is godmode, no gate); then in
each consumer `swift package update MacFaceKit` and commit the `Package.resolved` bump. README
prescribes pinning as `.upToNextMinor(from: "0.4.2")`.

`v0.4.0` → `v0.4.2` added: `AttentionDot`, `attention:`/`accessibilityHint:` on `IconButton`,
`attention:`/`attentionAccessibilityHint:` on `MenuRow` and `MenuAction`, derived attention on
`OverflowMenu`, `Tokens.attentionDot`, and `NoticeCard`'s action-closure init.

### 9.7 Minimal consumer skeleton

```swift
import MacFaceKit
import SwiftUI

struct PanelContent: View {
    let appInfo = AppInfo.fromBundle()

    var body: some View {
        AppIdentityCard(
            name: "Mumbler",
            version: appInfo.displayVersion,
            subtitle: "Hold a key, speak, and the text lands where you're typing.",
            actions: [
                MenuAction(title: "Check for Updates", systemImage: "arrow.triangle.2.circlepath",
                           attention: false, attentionAccessibilityHint: "Update available") { },
                MenuAction(title: "Quit Mumbler", systemImage: "power") {
                    NSApplication.shared.terminate(nil)
                }
            ],
            links: [
                IdentityLink.link("GitHub", AppIdentity.repoURL, systemImage: "globe"),
                IdentityLink.license(AppIdentity.licenseURL)
            ]
        ) {
            SectionCard("General") { Toggle("Launch at login", isOn: .constant(false)) }
            NoticeCard(title: "Microphone access required",
                       message: "Mumbler needs the microphone to transcribe. Open Settings and allow Mumbler.",
                       actionLabel: "Allow Microphone", actionSystemImage: "gearshape") { }
            PrimaryButton("Start dictation", systemImage: "mic.fill", trailing: "⌃") { }
        }
        .frame(width: 280)
        .background(Tokens.panel)
    }
}
```
No setup call is required at launch — there is no `register()`/`configure()` anywhere in the package.

---

## 10. Bootstrap checklist — a NEW app with this exact shape

Worked for `mumbler` / `Mumbler` / `dev.ecn.apps.mumbler`. Order is dependency-first: nothing later
invalidates anything earlier.

### Naming decisions to make once, before commit 1
TermTile's `.engine/BACKLOG.md` #1 says it outright: **"ONE NAME EVERYWHERE from commit 1"** —
RememBar's naming drift required cleanup machinery.

| Slot | TermTile | Mumbler |
|---|---|---|
| Repo / dir | `termtile` | `mumbler` |
| SPM package + product + executable target | `TermTile` | `Mumbler` |
| Core target | `TermTileCore` | `MumblerCore` |
| Kit target | `TermTileKit` | `MumblerKit` |
| Test targets | `TermTileCoreTests` / `TermTileKitTests` / `TermTileTests` | `MumblerCoreTests` / `MumblerKitTests` / `MumblerTests` |
| Bundle ID | `dev.ecn.apps.termtile` | `dev.ecn.apps.mumbler` |
| Env-var prefix | `TERMTILE_` | `MUMBLER_` |
| Dev signing identity | `TermTile Dev Signing` | `Mumbler Dev Signing` |
| Selftest defaults suite | `dev.ecn.apps.termtile.selftest` | `dev.ecn.apps.mumbler.selftest` |
| Dev port (if ever needed) | — | MUMB → 3,1,4,2 → `--port 3142` |

### Phase 0 — repo skeleton
1. `git init`; remote will be `github.com/EvanCNavarro/Mumbler` (personal / godmode — push freely).
2. `LICENSE` (MIT), `.gitignore`:
```
.env
.env.*
.engine/state/*
!.engine/state/.gitkeep
.engine/events.jsonl
dist/
build/
.build/

# Sparkle (vendored by scripts/fetch-sparkle.sh)
Vendor/
.sparkle-tools/
```
3. `PROJECT.md`, `AGENTS.md`, `CLAUDE.md` (which is just `@AGENTS.md` + a Claude delta),
   `.skills/manifest.json` — copy verbatim, swap the name.

### Phase 1 — the Locomotion layer (copy, then re-point)
4. **Copy verbatim:** `.engine/.gitignore`, `.engine/checks/core-purity.sh`,
   `.engine/checks/cwc-config-present.sh`, `.engine/checks/scripts-ascii-only.sh`,
   `.engine/checks/traps-ordered.sh`, `.engine/checks/reorient-next-task-cited.sh`,
   `.engine/checks/task-refs-int-keys.sh`.
   - In `core-purity.sh` change `core_dir="$root/Sources/TermTileCore"` → `MumblerCore`.
   - In `cwc-config-present.sh` nothing changes.
5. **Drop:** `no-iterm-whose-filter.sh`, `axprobe-no-defer.sh`, `axprobe-detached-task.sh`
   (TermTile-specific). Keep `selftest-stderr-markers.sh` but re-point the file path — the
   buffered-stdout trap applies to any env-selftest.
6. **Template:** `.engine/config.json` (only `subprocess_globs` paths and the commands matter; keep
   `frontend_globs: []`), and the mirrored root `cwc.config.json`.
7. **Start fresh:** `.engine/traps.md` (keep the header note + the promotion rule; traps are earned,
   not copied), `.engine/MEMORY.md` (rewrite the live-surface paragraph for a dictation app: PROVE
   means speaking into the real app and observing text land in a real target), `.engine/BACKLOG.md`
   (keep the taxonomy header, empty the tasks), `.engine/state/.gitkeep`.

### Phase 2 — `Package.swift`
8. Three targets + one binary target + three test targets, exactly as §6, renamed. Keep:
   - `swift-tools-version: 6.0`, `platforms: [.macOS(.v14)]` — **but note Mumbler's runtime target
     is macOS 26 for `SpeechAnalyzer`/`FoundationModels`; the platform floor must be raised to
     whatever those require. That is a decision this blueprint cannot make.**
   - the MacFaceKit dependency `.upToNextMinor(from: "0.4.2")`
   - `.binaryTarget(name: "Sparkle", path: "Vendor/Sparkle.xcframework")`
   - `resources: [.copy("Resources/AppIcon.png")]` on the executable — `.copy`, not `.process`
   - **the rpath linker flag** — without it the packaged app dyld-crashes:
     `.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])`

### Phase 3 — scripts (the highest-value copy)
9. **Copy and rename tokens only:** `fetch-sparkle.sh` (change nothing but the comment),
   `lib/notary-auth.sh` (`TERMTILE_NOTARY_*` → `MUMBLER_NOTARY_*`, function name
   `termtile_notary_prepare_auth` → `mumbler_notary_prepare_auth`), `notarize-app.sh`,
   `notary-status.sh`, `setup-dev-signing.sh`, `install-app.sh`, `test-packaged-app.sh`.
10. **`build-app.sh` — the edits that matter:**
    - `APP_NAME`, `BUNDLE_ID`, `ICON_SRC`, `SU_FEED_URL` defaults.
    - `SU_PUBLIC_ED_KEY` — **generate a NEW keypair**: run Sparkle's `generate_keys`, paste the
      public key here, and store the private key as the `SPARKLE_ED_PRIVATE_KEY` repo secret. Never
      reuse TermTile's.
    - `DEFAULT_DEV_IDENTITY="Mumbler Dev Signing"`.
    - `TERMTILE_BUILD_NUMBER` / `TERMTILE_SIGN_IDENTITY` / `TERMTILE_DISABLE_LIBRARY_VALIDATION` →
      `MUMBLER_*`.
    - **Info.plist additions Mumbler needs that TermTile does not:**
      `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription` (Accessibility needs no
      usage string, but mic and speech do). Add them inside the heredoc so `plutil -lint` still gates.
    - Glyph resource: swap `TermTileMenuGlyph.pdf` for the new app's menu glyph, or drop the block.
    - Keep the inside-out codesign order and `--deep` only on verify, unchanged.
11. Keep the **stdout contract**: build chatter to `>&2`, last stdout line = the `.app` path.
12. `chmod +x scripts/*.sh scripts/lib/*.sh .engine/checks/*.sh`.

### Phase 4 — CI
13. Copy `.github/workflows/check.yml` (change nothing but the branch if not `master`),
    `semgrep.yml` (verbatim), `dependabot.yml` (verbatim), `pull_request_template.md`.
14. `release.yml` — copy, then change: every `TERMTILE_*` secret/var name, the
    `download-url-prefix` (`https://github.com/EvanCNavarro/Mumbler/releases/download/${GITHUB_REF_NAME}/`),
    the zip basename (`Mumbler-${GITHUB_REF_NAME}.zip`), and `REQUIRE_CODESIGN_TEAM_ID`
    (still `XG9SBNWNXT` if the same Apple developer account).
    Keep `fetch-depth: 0` — `git rev-list --count` needs full history.

### Phase 5 — signing, Sparkle, and secrets
15. `scripts/setup-dev-signing.sh` once locally → stable TCC grants across rebuilds.
16. `scripts/fetch-sparkle.sh` once → `Vendor/Sparkle.xcframework`. Bump `SPARKLE_VERSION` if a newer
    Sparkle is current; check the `Versions/B` path still matches.
17. Fetch Sparkle's CLI tools tarball and run `generate_keys` → public key into `build-app.sh`,
    private key into `gh secret set SPARKLE_ED_PRIVATE_KEY`.
18. GitHub **secrets**: `MUMBLER_RELEASE_SIGNING_CERT_P12_BASE64`,
    `MUMBLER_RELEASE_SIGNING_CERT_PASSWORD`, `SPARKLE_ED_PRIVATE_KEY`,
    `MUMBLER_NOTARY_KEY_P8_BASE64`, `MUMBLER_NOTARY_KEY_ID`, `MUMBLER_NOTARY_ISSUER_ID`,
    optional `VIRUSTOTAL_API_KEY`.
    GitHub **variable**: `MUMBLER_SIGN_IDENTITY = "Developer ID Application: Evan Navarro (XG9SBNWNXT)"`.
19. **Appcast bootstrap:** `SUFeedURL` 404s until the first release publishes `appcast.xml` — that is
    expected and fine. Sparkle simply reports no update.

### Phase 6 — source skeleton
20. `Sources/MumblerCore/AppIdentity.swift` first (name, bundleID, repoURL, licenseURL — URLs on
    `HEAD`, not a branch).
21. Core: the pure domain. For Mumbler that is transcript/segment types, the cleanup-prompt policy,
    text post-processing — **no AVFoundation, no Speech, no AppKit.** Point `core-purity.sh` at the
    right forbidden imports (likely `AppKit`, `ApplicationServices`, `AVFoundation`, `Speech`).
22. Kit: one port per system surface, each with an in-memory fake — e.g.
    `protocol AudioCapturing`, `protocol Transcribing`, `protocol TextInjecting`,
    `protocol HotKeyMonitoring`, plus copies of `SettingsStore`, `AppSettings`, `LoginItem`,
    `OwnedPaths`, `Uninstaller`, `PermissionRepairer`, `AccessibilityState`, `AccessibilityTrust`,
    and the `MenuBarViewModel`.
    **`PermissionRepairer` needs new scopes** — `.microphone` (`tccutil` service `Microphone`) and
    `.speechRecognition` (`SpeechRecognition`). Verify those service names with
    `tccutil reset --help` / a live probe before shipping; I have **not** verified them.
23. Shell: `MumblerApp.swift` (composition root in `init()`, `setActivationPolicy(.accessory)`,
    `MenuBarExtra { … } label: { … }.menuBarExtraStyle(.window)`), `MenuBarContent.swift`,
    `MumblerGlyph.swift`, `Updater.swift`, `MumblerUserDriver.swift`, `UpdateAvailability.swift`,
    `BundleResources.swift` (copy verbatim — the `#if DEBUG`-gated `Bundle.module` fallback).
24. Env hooks, renamed: `MUMBLER_SELFTEST`, `MUMBLER_GALLERY`, `MUMBLER_GALLERY_UPDATE_AVAILABLE`,
    `MUMBLER_AUTOCHECK`, `MUMBLER_STOCK_UPDATER`, `MUMBLER_UPDATE_PROBE_SMOKE`, plus a one-shot
    action hook (TermTile's `TERMTILE_TILE_ONCE` → e.g. `MUMBLER_DICTATE_ONCE`).
    `test-packaged-app.sh` greps for `GALLERY shown` and `UPDATE_PROBE_SMOKE armed`/`finished` —
    keep those exact marker strings, written to `FileHandle.standardError`.

### Phase 7 — tests
25. Three test targets. `MumblerTests` depends on the **executable** target and uses
    `@testable import Mumbler` — that is the whole convention.
26. Copy and adapt `PackagingScriptsTests`, `WorkflowsTests`, `ReleaseReadinessTests` — the
    `#filePath`-walk-up `repoRoot()` helper is reusable verbatim. These are cheap and catch script
    regressions that a build never will.
27. Fakes as `InMemory*.swift`, one per port. No mocking library.

### Phase 8 — docs
28. `README.md` (what it is / Install / Privacy & permissions / Verify this download / Build from
    source / Not yet / Releasing / License), `SECURITY.md` (supported versions, private advisory
    reporting, what it can and can't touch, supply-chain integrity, known limitations),
    `HANDOFF.md` (the "Current state" table + "Start here (next session, in order)" +
    "Known-good dev hooks / gotchas" + "Open items / deferred"),
    `docs/RELEASING.md`, `docs/NOTARIZATION.md`, `docs/decisions/0001-*.md` (the architecture ADR),
    `docs/environment/*`, `docs/github/REPOSITORY_POLICY.md`, `docs/verification/COMMANDS.md`.
29. `release-notes/0.1.0.md` before the first tag.

### Phase 9 — first release
30. `scripts/fetch-sparkle.sh && swift build && swift test && swiftlint --strict`
31. `scripts/install-app.sh` → grant permissions once → exercise the app live → screenshot into
    `docs/verification/`.
32. Write `release-notes/0.1.0.md`, commit the whole release diff, `git tag -a v0.1.0`,
    `git push origin master v0.1.0`.
33. After CI publishes, verify the **downloaded** artifact (not a local build):
```sh
gh release download v0.1.0 --repo EvanCNavarro/Mumbler --pattern 'Mumbler-v0.1.0.zip*'
ditto -x -k Mumbler-v0.1.0.zip unpacked
codesign --verify --deep --strict --verbose=2 unpacked/Mumbler.app
xcrun stapler validate unpacked/Mumbler.app
spctl --assess --type execute --verbose=4 unpacked/Mumbler.app
env LC_ALL=C LANG=C shasum -a 256 -c Mumbler-v0.1.0.zip.sha256
gh attestation verify Mumbler-v0.1.0.zip --repo EvanCNavarro/Mumbler
```

### Copy / template / rewrite — the quick table

| Copy verbatim | Template (rename tokens) | Write fresh |
|---|---|---|
| `fetch-sparkle.sh`, `lib/notary-auth.sh`*, `notarize-app.sh`*, `notary-status.sh`*, `test-packaged-app.sh`*, `install-app.sh`*, `setup-dev-signing.sh`*, `BundleResources.swift`, `semgrep.yml`, `dependabot.yml`, `check.yml`, `pull_request_template.md`, `.engine/checks/{core-purity,cwc-config-present,scripts-ascii-only,traps-ordered,reorient-next-task-cited,task-refs-int-keys}.sh`, `.gitignore`, `.swiftlint.yml`, `.skills/manifest.json`, `docs/environment/*` | `build-app.sh`, `release.yml`, `Package.swift`, `.engine/config.json`, `cwc.config.json`, `AppIdentity.swift`, `Updater.swift`, `*UserDriver.swift`, `UpdateAvailability.swift`, `MenuBarViewModel.swift`, `SettingsStore.swift`, `AppSettings.swift`, `LoginItem.swift`, `OwnedPaths.swift`, `Uninstaller.swift`, `PermissionRepairer.swift`, `AccessibilityState.swift`, `AccessibilityTrust.swift`, `PackagingScriptsTests`, `WorkflowsTests`, `ReleaseReadinessTests`, `README.md`, `SECURITY.md`, `HANDOFF.md`, `docs/RELEASING.md`, `docs/NOTARIZATION.md` | `.engine/traps.md`, `.engine/MEMORY.md`, `.engine/BACKLOG.md`, `docs/decisions/0001-*.md`, `docs/product/spec-draft.md`, all domain Core/Kit code, `MenuBarContent.swift`, the glyph, `release-notes/*.md` |

\* = only the `TERMTILE_` env prefix and the app name change.

### Things that will silently break if you skip them
1. **The rpath linker flag** — packaged app dyld-crashes on `@rpath/Sparkle.framework`.
2. **`ditto` (not `cp -R`) for the framework** — loses version symlinks.
3. **`fetch-sparkle.sh` before any `swift build`/`swift test` in CI** — the binaryTarget has no artifact.
4. **`fetch-depth: 0` in release CI** — `git rev-list --count` returns 1 on a shallow clone.
5. **`Bundle.module` outside `#if DEBUG`** — CI-baked `.build` path crashes on every user's machine.
6. **Ad-hoc signing a public release** — resets every TCC grant on every update.
7. **`disable-library-validation` on a Developer ID artifact** — ADR-0002 violation; smoke test rejects it.
8. **Notarizing after zipping** — the zip then contains an unstapled app.
9. **`print()` for live-PROVE markers** — block-buffered, lost on SIGTERM.
10. **A non-ASCII character in a shell script** — `set -u` unbound-variable at runtime.

---

## Appendix — verification and blind spots

**What I checked:** every file listed in §1 outside `Vendor/`, `.build/`, `dist/`, and
`docs/verification/*.png`, read with `cat -n` / `sed` / `grep` and quoted above. Git metadata via
`git log -1 --oneline`, `git branch --show-current`, `git remote -v`. MacFaceKit inventoried by a
parallel read-only agent against `/Users/evancnavarro/Developer/MacFaceKit` @ `c430176` (= v0.4.2,
the pinned revision), cross-checked against `Package.resolved`.

**What this canNOT see:**
- **Nothing was built or run.** `swift build`, `swift test`, `swiftlint --strict`, and every script
  are quoted, not executed. Whether they are currently green is UNVERIFIED.
- **`.engine/state/*` is gitignored**, so the stoke plans and notary logs I read are one machine's
  local history, not a reproducible artifact of the repo.
- **`docs/decisions/0003`–`0005` were read structurally** (headings, status blocks, phase markers)
  rather than line-by-line; their 44 KB of phase detail is summarised, not exhausted.
- **`.engine/BACKLOG.md` (45 KB)** — only the header and the first ~80 lines were read. The taxonomy
  is confirmed; the full task history is not.
- **TCC service names for microphone / speech recognition are UNVERIFIED.** TermTile only proves
  `Accessibility` and `ListenEvent`.
- **The `Bundle.module` packaged-app crash is UNVERIFIED by direct observation** — it is the repo's
  stated rationale, corroborated by the shipping code routing around it and by a test asserting the
  avoidance.
- **The macOS platform floor for Mumbler is an open decision.** TermTile targets `.macOS(.v14)`;
  `SpeechAnalyzer`/`FoundationModels` require macOS 26. This blueprint does not resolve that.
