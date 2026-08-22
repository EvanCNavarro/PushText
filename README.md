# PushText

Hold a key, speak, and cleaned text appears in whatever app you're typing into.
Entirely on-device: no account, no network, no per-token cost.

**Status: Phase 0 scaffold.** The shell, the state machine and the packaging path are real and
tested. Speech recognition is a mock — see [Why it doesn't transcribe yet](#why-it-doesnt-transcribe-yet).

## Why

Wispr Flow costs $15/month, and its latency is dominated by the network rather than the model. A
teardown of its own logs shows `transcribe: 0.21s` of inference wrapped in ~1 second of
`basetenPing` + `webSocket`. Apple ships an on-device speech recognizer and an on-device language
model in macOS 26. Running both locally deletes the network round-trip and the subscription.

## How it works

```
Right Option held  ->  CGEventTap (.flagsChanged)
                   ->  AVAudioEngine capture
                   ->  SpeechAnalyzer / SpeechTranscriber      (on-device)
                   ->  FoundationModels polish, optional        (on-device)
                   ->  drift guard: does the polish still say what you said?
                   ->  NSPasteboard + synthetic Cmd-V into the frontmost app
```

Every stage after capture sits behind a protocol in `PushTextKit`, so the engine can be swapped
without touching the app.

## Design decisions worth knowing

- **Right Option, not Fn.** Fn doesn't exist on non-Apple keyboards and its system action cannot be
  suppressed — `TextInputSwitcher.app` never enters the event-tap chain at all. Also, Secure Input
  filters `keyDown`/`keyUp` but lets `flagsChanged` through, so a bare held modifier keeps working
  in password fields where a chord would silently die.
- **Pasteboard, not Accessibility, for insertion.** `AXUIElement` text writes return *success while
  doing nothing* in Electron, VS Code, Google Docs and Pages. Five of five surveyed open-source
  dictation apps use the pasteboard route.
- **Cleanup is optional polish, not a required stage.** Apple's `SpeechTranscriber` already
  punctuates and capitalizes (99.9% / 99.7% across 5,559 sampled hypotheses). The language model
  makes good transcripts prettier; it can also make them worse, so every failure path falls back to
  the raw transcript silently.
- **The polish is checked before it's used.** If the cleaned text drops content, inverts a
  negation, or introduces words you didn't say, the raw transcript wins. Dictating "what is the
  capital of France" must not type "Paris".
- **We never request Input Monitoring.** Microphone + Accessibility + PostEvent is the whole set.

Full reasoning, with sources, in [`PLAN.md`](PLAN.md) and [`research/`](research/).

## Build

Requires Swift 6 and a Mac.

```sh
scripts/setup-dev-signing.sh   # once — stable code identity so TCC grants survive rebuilds
scripts/fetch-sparkle.sh       # once — vendors Sparkle.xcframework into gitignored Vendor/
swift build && swift test
scripts/build-app.sh           # prints the path to a signed dist/PushText.app
```

Run `setup-dev-signing.sh` before granting any permission. Ad-hoc signing produces a fresh cdhash
on every build, which silently resets every TCC grant — with three permissions in play that means
re-approving three prompts after every rebuild.

## Why it doesn't transcribe yet

`SpeechAnalyzer` and `FoundationModels` are macOS 26 APIs, and the SDK ships with Xcode, not with
the OS — so both a Tahoe upgrade and Xcode 26 are required before the real engines can even
compile. Until then `MockTranscriptionEngine` stands in, which keeps the other ~70% of the app —
hotkey, capture, injection, HUD, packaging — buildable and testable today.

One risk is already known and is the first thing to test after upgrading:
`start(inputSequence:)`, the streaming-microphone path this design rests on, has an open bug on
macOS 26.3 (FB22149971). File-based transcription works on the same audio. If it reproduces, the
architecture pivots to chunked file transcription.

## Layout

| Path | What's in it |
|---|---|
| `Sources/PushTextCore` | Pure logic: state machine, drift guard, dictionary matcher. No frameworks — enforced by `.engine/checks/core-purity.sh`. |
| `Sources/PushTextKit` | System adapters behind protocol ports. |
| `Sources/PushText` | SwiftUI `MenuBarExtra` shell and composition root. |
| `scripts/` | Build, sign, notarize, release. |
| `research/` | ~9,400 lines of sourced research behind every decision above. |

## License

Not yet chosen.
