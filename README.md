# PushText

Hold a key, speak, and cleaned text appears in whatever app you are typing into. The speech
recognition and the polish both run on this Mac: no account, no subscription, no per-token cost, and
nothing you say leaves the machine.

Requires **macOS 26 (Tahoe)** or later, on Apple silicon or Intel.

## Install

Download the latest `PushText-vX.Y.Z.zip` from
[Releases](https://github.com/EvanCNavarro/PushText/releases/latest), unzip it, and drag
`PushText.app` to `/Applications`.

The app is signed with a Developer ID and notarized by Apple, so it opens without a Gatekeeper
warning. Each release also ships a `.sha256` file if you want to check the download.

PushText lives in the menu bar and has no Dock icon or window of its own.

## Permissions

macOS will ask for two things the first time you need them. PushText tells you which one is missing
and takes you to the right Settings pane if a grant is refused.

| Permission | What it is for |
|---|---|
| **Microphone** | Hearing you. |
| **Accessibility** | Watching for the hotkey, and pasting the finished text into the app you are in. |

Those two panes are the whole set. PushText may name the second capability **"input control"** when
it asks - macOS has no separate pane for permission to type on your behalf, so it is granted under
Accessibility alongside the hotkey.

**Input Monitoring is never requested.**

## Using it

**Hold** your hotkey, speak, and release. The text is inserted where your cursor is.

**Double-press** it to latch hands-free: dictation keeps running with your hands off the keyboard,
and you press again to finish. Useful for anything longer than a sentence.

A single dictation can run for **twenty minutes**. If you reach that ceiling the recording stops and
everything you said up to that point is kept and inserted - it is a limit, not a discard.

The default hotkey is **Right Option**. You can change it in the menu under *Dictate*: hold the key
you want and PushText records it. Nine keys are offered - the four right-hand modifiers, the four
left-hand ones, and **Globe (fn)**.

Globe is worth a note. macOS assigns it its own action - by default "Start Dictation (Press Globe
Twice)" - and PushText takes that key over completely when you bind it, so Apple's dictation does not
fire alongside ours.

## What else it does

- **A searchable history.** Every transcript PushText has typed, with fuzzy search that highlights
  what matched. It updates while the window is open.
- **A custom dictionary.** Names, jargon and spellings the recognizer keeps getting wrong. The
  recognizer itself cannot be biased, so this is a post-pass over the transcript.
- **Optional cleanup.** Apple's on-device language model tidies filler and stray punctuation. Off by
  default, because it adds about three seconds to roughly half of dictations - and because the
  transcriber already punctuates and capitalises well on its own.
- **Start and stop cues.** A short tone when dictation starts, a lower one when it ends. On by
  default.
- **Silence other audio.** Mutes the Mac while you dictate so music does not reach the microphone.
  Off by default.
- **Launch at login**, if you want it.

## Settings and their defaults

| Setting | Default | Why |
|---|---|---|
| Hotkey | Right Option | Works on every keyboard, and survives Secure Input where a chord would not. |
| Start and stop cues | **On** | You need to know the microphone is live. |
| Silence other audio | Off | Muting the machine is a bigger side effect than most dictations need. |
| Tidy transcripts | Off | Costs about three seconds on roughly half of dictations. |
| Launch at login | Off | Your call, not ours. |

## Updates

PushText checks for updates quietly and marks the menu-bar icon when one is available. Nothing is
downloaded or installed until you ask for it, and the release notes are shown before you agree.

## Privacy

Your speech, your transcripts and your dictionary never leave this Mac. Recognition and cleanup both
run on-device; audio is never written to disk.

The one network request the app makes is the update check, which fetches a signed appcast from
GitHub. It sends no telemetry and no analytics. [`SECURITY.md`](SECURITY.md) has the details.

## Why this exists

Wispr Flow costs $15/month, and its latency is dominated by the network rather than the model. A
teardown of its own logs shows `transcribe: 0.21s` of inference wrapped in ~1 second of
`basetenPing` + `webSocket`. Apple ships an on-device speech recognizer and an on-device language
model in macOS 26. Running both locally deletes the network round-trip and the subscription.

## How it works

```
hotkey held       ->  CGEventTap (.flagsChanged)
                  ->  AVAudioEngine capture
                  ->  SpeechAnalyzer / SpeechTranscriber      (on-device)
                  ->  FoundationModels polish, optional        (on-device)
                  ->  drift guard: does the polish still say what you said?
                  ->  NSPasteboard + synthetic Cmd-V into the frontmost app
```

Every stage after capture sits behind a protocol in `PushTextKit`, so the engine can be swapped
without touching the app.

## Design decisions worth knowing

- **A held modifier, not a chord.** Secure Input filters `keyDown`/`keyUp` but lets `flagsChanged`
  through, so a bare held modifier keeps working in password fields where a chord would silently die.
- **Globe is offered, and it wins.** An earlier version of this file said Fn "cannot be suppressed".
  That was a misreading of our own research: an event tap can both see the Fn flag and consume it.
  Binding Globe replaces Apple's dictation rather than firing alongside it - measured, in
  [`docs/verification/task182-globe-replaces-system-action.md`](docs/verification/task182-globe-replaces-system-action.md).
- **Pasteboard, not Accessibility, for insertion.** `AXUIElement` text writes return *success while
  doing nothing* in Electron, VS Code, Google Docs and Pages. Five of five surveyed open-source
  dictation apps use the pasteboard route.
- **Cleanup is optional polish, not a required stage.** Apple's `SpeechTranscriber` already
  punctuates and capitalizes (99.9% / 99.7% across 5,559 sampled hypotheses). The language model
  makes good transcripts prettier; it can also make them worse, so every failure path falls back to
  the raw transcript silently.
- **The polish is checked before it is used.** If the cleaned text drops content, inverts a negation,
  or introduces words you did not say, the raw transcript wins. Dictating "what is the capital of
  France" must not type "Paris".

Full reasoning, with sources, in [`PLAN.md`](PLAN.md) and [`docs/research/`](docs/research/).
Measurements that contradict the research live in
[`docs/verification/`](docs/verification/), and the measurement wins.

## Build from source

Requires macOS 26 and Swift 6.2 - the manifest is `swift-tools-version: 6.2` because `.v26` does not
exist in earlier PackageDescription versions.

```sh
scripts/setup-dev-signing.sh   # once - stable code identity so TCC grants survive rebuilds
scripts/fetch-sparkle.sh       # once - vendors Sparkle.xcframework into gitignored Vendor/
swift build && swift test
scripts/build-app.sh           # prints the path to a signed dist/PushText.app
scripts/test-packaged-app.sh   # structural invariants + a real launch proof
scripts/install-app.sh         # build, install to /Applications, relaunch
```

Run `setup-dev-signing.sh` before granting any permission. Ad-hoc signing produces a fresh cdhash on
every build, which silently resets every TCC grant - which means re-approving the prompts after every
rebuild.

A green `swift test` proves the pipeline, not the speech recognition: the suite runs against a mock
engine and protocol seams. Claims about transcription or cleanup are backed by probe runs instead -
see [`AGENTS.md`](AGENTS.md).

## Layout

| Path | What's in it |
|---|---|
| `Sources/PushTextCore` | Pure logic: state machine, drift guard, dictionary matcher. No frameworks - enforced by `.engine/checks/core-purity.sh`. |
| `Sources/PushTextKit` | System adapters behind protocol ports. |
| `Sources/PushText` | SwiftUI `MenuBarExtra` shell and composition root. |
| `scripts/` | Build, sign, install, notarize, smoke-test, and the probes. |
| `docs/decisions/` | Architecture decision records. |
| `docs/verification/` | What was measured, and what the measurement could not see. |
| `docs/research/` | ~10,000 lines of sourced research behind the decisions above. |
| `.engine/` | Project memory, backlog, traps, and the fail-closed check scripts. |

## License

MIT. See [LICENSE](LICENSE).
