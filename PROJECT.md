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

macOS 26, everywhere — `SpeechAnalyzer` and `FoundationModels` exist nowhere below it. Phase 0's
lower build floor is gone (#16): `Package.swift` is `.macOS(.v26)`, `MIN_SYSTEM_VERSION` in
`scripts/build-app.sh` is `26.0`, and both CI workflows run on `macos-26`. Those four must agree, and
`.engine/checks/platform-floor-consistent.sh` fails the build if they drift — `release.yml` fires
only on a tag, so nothing else would notice its runner falling behind. See `PLAN.md` §2.5.
