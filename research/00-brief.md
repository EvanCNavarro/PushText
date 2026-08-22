# Mumbler — research brief

Started 2026-08-22. Project dir: `/Users/evancnavarro/Developer/mumbler` (empty at start; no git).

## Goal

A local-first, offline, free macOS dictation app in the shape of Wispr Flow:
hold a key → speak → text lands in the frontmost app, cleaned up.

Reference build: Per Simmons' "Murmur" (https://github.com/per-simmons/murmur-youtube,
video https://www.youtube.com/watch?v=IMQw3aHjf2Q).

Reference app-shape: `~/Developer/termtile` (SwiftUI MenuBarExtra, SPM, Sparkle
auto-update, notarized, `400faces/MacFaceKit` design system, `.engine/` Locomotion layer).
The new app should copy that structure — dev scaffolding, Sparkle updates, menu-bar UI.

Runtime intent: **zero API cost, zero network**.
- STT: Apple `SpeechAnalyzer` / `SpeechTranscriber` (Speech framework, macOS 26).
- Cleanup/translate: Apple on-device Foundation Model, via `apfel` or direct `FoundationModels`.

## VERIFIED local facts (read off this machine, 2026-08-22)

```
$ sw_vers
ProductName:    macOS
ProductVersion: 15.1
BuildVersion:   24B83

$ xcodebuild -version
Xcode 16.2 / Build 16C5032a

$ swift --version
Apple Swift version 6.0.3 (swiftlang-6.0.3.1.10 clang-1600.0.30.1)
Target: arm64-apple-macosx15.0
```

Hardware per Bobby: MacBook Pro 16" (2021), M1 Max, 64 GB.
(Model/RAM NOT independently verified by me — asserted by Bobby. UNVERIFIED.)

TermTile facts, read from `Package.swift`:
- `swift-tools-version: 6.0`, `platforms: [.macOS(.v14)]`
- deps: `https://github.com/400faces/MacFaceKit.git` `.upToNextMinor(from: "0.4.2")`
- 3 targets: `TermTileCore` (pure, CoreGraphics only, purity enforced by
  `.engine/checks/core-purity.sh`), `TermTileKit` (window-system port + AX adapters),
  `TermTile` (MenuBarExtra shell + composition root)
- Sparkle as a LOCAL `binaryTarget` at `Vendor/Sparkle.xcframework`, gitignored,
  vendored by `scripts/fetch-sparkle.sh`; needs an `@executable_path/../Frameworks`
  rpath or dyld crashes
- 3 test targets incl. one that `@testable import`s the executable
- remote: `https://github.com/EvanCNavarro/TermTile.git` (personal, godmode)
- scripts/: build-app, fetch-sparkle, install-app, notarize-app, notary-status,
  setup-dev-signing, test-packaged-app

## THE BLOCKER

macOS 15.1 has neither `SpeechAnalyzer` nor `FoundationModels`. Nothing in the
runtime half of this plan can be compiled, let alone run, until Bobby upgrades to
macOS 26 Tahoe **and** installs the matching Xcode (Xcode 16.2 ships the macOS 15
SDK — an OS upgrade alone is not enough; the SDK comes with Xcode).

Therefore this phase is research + planning + the parts that DON'T need Tahoe.

## Open questions being researched (one agent each)

1. `SpeechAnalyzer`/`SpeechTranscriber` — real API surface, asset lifecycle, latency, gotchas.
2. `FoundationModels` + `apfel` — and whether apfel is needed at all.
3. The murmur-youtube repo — architecture, quality, the verbatim cleanup prompt.
4. macOS plumbing — global Fn/Right-Ctrl push-to-talk, text injection, TCC, HUD panel.
5. TermTile blueprint — the exact shape to clone.
6. Competitive landscape — Wispr Flow's real feature set + complaints, Parakeet, prompts.

## Working hypotheses to CONFIRM OR KILL (not yet established)

- **H1 — apfel is probably unnecessary.** It's a CLI + OpenAI-compatible HTTP shim
  around `FoundationModels`. A native Swift app can `import FoundationModels` and call
  the model in-process: no HTTP hop, no extra install the user must do, access to
  guided generation and streaming. apfel's value is for shell/non-Swift callers.
  If true, apfel becomes a *dev-time* convenience, not a runtime dependency.
- **H2 — port 11434 is Ollama's default.** If apfel really binds it, that's a
  collision with any Ollama install and a reason not to depend on it at runtime.
- **H3 — the Fn/Globe key is the worst possible hotkey** to bind, because macOS
  reserves it (dictation / emoji picker / "Press Globe key to…"). Right-Control is
  likely the safer default.
- **H4 — text injection via AXUIElement is unreliable in Electron apps**; pasteboard +
  synthetic Cmd-V with clipboard save/restore is what shipping apps actually do.
- **H5 — a 3B model with a ~4k context will over-rewrite** dictated text and
  sometimes ANSWER a dictated question instead of cleaning it. Cleanup needs a hard
  prompt + an output-drift guard, and must be optional.

## Blocker — PROVEN, not assumed (run 2026-08-22)

```
$ xcrun --show-sdk-version
15.2

$ ls -d $(xcrun --show-sdk-path)/System/Library/Frameworks/FoundationModels.framework
ls: .../MacOSX.sdk/System/Library/Frameworks/FoundationModels.framework: No such file or directory

$ grep -c "SpeechAnalyzer\|SpeechTranscriber" \
    $(xcrun --show-sdk-path)/System/Library/Frameworks/Speech.framework/Versions/A/Modules/\
Speech.swiftmodule/arm64e-apple-macos.swiftinterface
0
```
Legacy `SFSpeechRecognizer.h` IS present, so the Speech framework itself is there —
it is specifically the macOS 26 additions that are absent.

What this check canNOT see: it proves only that the *installed Xcode 16.2 SDK* lacks
these. It says nothing about how the APIs behave once the macOS 26 SDK is installed.
Every API claim in files 01/02 is therefore documentation-derived, not run-derived,
until we are on Tahoe.
