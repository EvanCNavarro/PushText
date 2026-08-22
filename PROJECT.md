# Project

Name: pushtext
Profile: macos-native (Swift/SPM menu-bar app)
Framework adapter: none
Deploy target: local .app bundle (signed release via GitHub Releases)

## Structure

- `docs/` stores research, decisions (ADRs in `docs/decisions/`), product notes, and verification records.
- `.engine/` stores Locomotion project memory and config.
- `Sources/PushTextCore` is the pure functional core (ADR-0001), guarded by `.engine/checks/core-purity.sh`.
- `Sources/PushTextKit` holds one adapter per system capability, each behind a protocol port.
- `Sources/PushText` is the SwiftUI shell and composition root.

## Platform floor

Shipped floor is macOS 26 — `SpeechAnalyzer` and `FoundationModels` exist nowhere below it.
`Package.swift` sits at `.macOS(.v14)` during Phase 0 so the ~70% of the app that needs neither can
be built and tested on Sequoia; that single line and `MIN_SYSTEM_VERSION` in `scripts/build-app.sh`
move together in Phase 2. See `PLAN.md` §2.5.
