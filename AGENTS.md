# Agent Instructions

## Repository Expectations

- Run `swift build && swift test && swiftlint --strict` before claiming project health.
- Run `.engine/checks/core-purity.sh` before claiming `PushTextCore` is clean — it is the ADR-0001
  gate and it fails closed.
- Keep secrets out of commits.
- Put durable decisions in `docs/decisions/`.
- Keep generated caches out of source control.
- Treat `.skills/manifest.json` as the project-readable cross-agent skill authority.

## What this project cannot verify locally

`SpeechAnalyzer` and `FoundationModels` are macOS 26 APIs and the SDK ships with Xcode, not with the
OS. Until Xcode 26 is installed here, no claim about their runtime behaviour is verifiable on this
machine. Say so rather than asserting one. `docs/research/01` and `docs/research/02` mark every such
claim; keep that discipline.

`MockTranscriptionEngine` is the Phase 0 engine, not a test double. A green suite proves the
pipeline, never the speech recognition.
