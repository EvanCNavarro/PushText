# Agent Instructions

## Repository Expectations

- Run `swift build && swift test && swiftlint --strict` before claiming project health.
- Run every `.engine/checks/*.sh` before claiming project health; they all fail closed.
- Conventional Commits are gated on BOTH the commit subject and the PR title, because the squash
  header comes from whichever one the PR's commit count selects (TRAP-37). Keep both under 84
  characters - GitHub appends ` (#N)` afterwards.
- Run `.engine/checks/core-purity.sh` before claiming `PushTextCore` is clean — it is the ADR-0001
  gate and it fails closed.
- Keep secrets out of commits.
- Put durable decisions in `docs/decisions/`.
- Keep generated caches out of source control.
- Treat `.skills/manifest.json` as the project-readable cross-agent skill authority.

## What a green suite does and does not prove

`SpeechAnalyzer` and `FoundationModels` ARE now verifiable here: this machine runs macOS 26 with the
26 SDK, and the package floor matches it (#16). Prefer a measurement to a citation. `docs/research/01`
and `docs/research/02` predate that and mark every unverified claim as such - when a measurement now
contradicts one of them, the measurement wins and gets written up in `docs/verification/`.

What is still NOT provable from `swift test`: the suite runs against `MockTranscriptionEngine` and
protocol seams, so a green run proves the pipeline and never the speech recognition or the on-device
model. Those have their own probes, which drive the real frameworks and exit non-zero:

    PUSHTEXT_TRANSCRIBE_PROBE=1 PUSHTEXT_TRANSCRIBE_PROBE_FILE=<abs.wav> <app-binary>
    PUSHTEXT_CLEANUP_PROBE=1 PUSHTEXT_CLEANUP_PROBE_TEXT="<raw text>" <app-binary>

Cite a probe run, not a test count, for any claim about transcription or cleanup.
