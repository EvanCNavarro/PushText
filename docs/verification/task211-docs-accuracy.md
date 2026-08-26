# The README said the app does not work (#211)

Bobby: *"then update the github description and readme files and documentation."*

An audit against the code found this was not staleness in the usual sense. The README's central
claim was **false**, and had been for 22 releases.

## What was false, with the code that contradicts it

| README said | Code says |
|---|---|
| `:9-10` "Status: Phase 0 scaffold ... Speech recognition is a mock" | `TranscriptionEngineFactory.makeDefault()` returns `AppleSpeechEngine`, under "There is exactly one engine, and no gate in front of it (#16)" |
| `:70-80` an entire section, "Why it doesn't transcribe yet" | The upgrade happened; `docs/verification/task11-streaming-spike.md` records FB22149971 as NOT reproducing. Verdict: GO. |
| `:35-38` "Fn ... its system action cannot be suppressed" | `ModifierGate.swift` calls that exact reasoning a misreading of our own research (#176). Globe is selectable AND suppressing, measured in `task182`. |
| `:4` "no network", flat | `SECURITY.md:30` is qualified: no network request EXCEPT the update check. |

The last one matters most. The README overclaimed privacy where the security policy was careful -
the direction of error that costs trust rather than earning it.

## The project's own rule, broken on its front page

`docs/RELEASING.md:19-23` forbids telling a reader what does not work, in Bobby's own words about
the 0.2.0 notes: *"what's not in the release is a bad thing to include in the release, makes no
sense."* The README led with exactly that - a status banner announcing the app was a scaffold, and a
section explaining why it could not transcribe.

## What was missing

Zero of ten shipped user-facing features were mentioned: fuzzy search with highlighting, the update
indicator, sound cues, silence-while-dictating, launch at login, the history window, the twenty-minute
ceiling, the double-press latch, the rebindable hotkey, the permission fix-it row.

Nor was there an install path (build-from-source only, for an app that ships signed and notarized
releases), a permissions section, usage instructions, an update story, or the **macOS 26 requirement**
- the single most important prerequisite, stated nowhere.

## Numbers, re-measured rather than copied

| Claim | Where | Measured |
|---|---|---|
| "46 tests passed" | `HANDOFF.md:28` | **443** (`grep -rc "@Test" Tests/`) |
| "~9,400 lines" of research | `README.md:91`, `HANDOFF.md:22` | **10,054** (`wc -l docs/research/*.md`) |
| "One field today, deliberately" | `AppSettings.swift:3` | **five** stored properties |

Defaults in the new settings table were read out of `AppSettings.defaults`, not remembered:
`cleanupEnabled: false`, `hotkeyKeyCode: rightOption`, `soundEnabled: true`,
`silenceWhileDictating: false`.

## What changed

- **README rewritten user-first.** Install, permissions, how to use, what it does, settings with
  their defaults and the reason for each, updates, privacy - then the engineering sections, kept.
- **`HANDOFF.md` marked superseded** rather than deleted. It is the only written record of several
  pre-upgrade assumptions that turned out wrong, which is worth keeping - but it opened with "read
  this first in a new session" and the README pointed at it, so it read as current state.
- **The stale `AppSettings` comment corrected** to say what actually happened: it started as one
  field on purpose and grew to five, one per feature that needed it, which is the outcome that rule
  wanted.
- **GitHub metadata**: ten topics added where there were none, so the repo is findable at all;
  homepage pointed at the latest release; and the description's "On-device, no network" softened to
  "Speech and cleanup both run on-device" - the same overclaim as the README, in the more visible
  place.

## What this does not cover

`PLAN.md` (275 lines) and the nine research documents were not audited line by line. They are dated
records of what was believed at the time, and `AGENTS.md` already says a measurement beats them when
the two disagree. `docs/product/`, `docs/environment/` and `docs/github/` are empty directories; two
are not even tracked. Left alone rather than filled with something invented - #212 tracks nothing
about them and neither does this.
