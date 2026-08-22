# PushText .engine memory

- **Live-surface semantics (native app, not web):** every Swift source under `Sources/` is mapped to
  `subprocess_globs`. The app's real surface is a global event tap, microphone capture, and synthetic
  keystrokes into OTHER applications. PROVE (FL-1) for a touched Swift file means running the built
  `.app` and observing the effect in a real target application — not a green suite. `frontend_globs`
  is intentionally empty; Chrome DevTools verifiers do not apply.

- **The suite cannot prove transcription.** `MockTranscriptionEngine` is the Phase 0 production
  engine, not a test double. `swift test` green proves the pipeline and the state machine; it says
  nothing about speech recognition, which cannot be compiled here at all yet.

- **Two frameworks are unbuildable on this machine.** `SpeechAnalyzer` and `FoundationModels` ship in
  the macOS 26 SDK, which comes with Xcode 26, not with the OS upgrade. Verified 2026-08-22:
  `xcrun --show-sdk-version` -> 15.2; `FoundationModels.framework` absent from the SDK;
  `grep -c "SpeechAnalyzer|SpeechTranscriber"` against `Speech.swiftinterface` -> 0. Any claim about
  their behaviour is documentation-derived until that changes.

- **Build/test signals:** `swift build` / `swift test` at repo root. Gates: `swiftlint --strict` and
  `.engine/checks/core-purity.sh` (ADR-0001, fail-closed, battle-tested 5/5 on planted imports).

- **Research authority:** `docs/research/` — ~9,400 lines across 9 files, each with its own
  "what I could not verify" section. `PLAN.md` holds the decisions those files support. Template app:
  TermTile at `~/Developer/termtile`, mapped in `docs/research/05-termtile-blueprint.md`.

- **Signing must be stable before any permission is granted.** Run `scripts/setup-dev-signing.sh`
  first. Ad-hoc signing produces a fresh cdhash per build and silently resets every TCC grant; this
  app needs three (Microphone, Accessibility, PostEvent), so the cost of forgetting is three prompts
  per rebuild.
