# HANDOFF — read this first in a new session

Written 2026-08-22, at the end of the session that created this project, immediately before Bobby
upgrades macOS 15.1 → macOS 26 (Tahoe). **That upgrade kills the session that wrote everything here.**

Baseline this describes: `master` at `9f93969`. Confirm with `git log --oneline -1` before trusting
a word of it — this file is prose, and prose is a claim about the code, not the code.

---

## 1. What PushText is

A local-first push-to-talk dictation app for macOS. Hold Right Option, speak, cleaned text appears in
whatever app has focus. Entirely on-device: no account, no network, no per-token cost.

The opening is not "match a cloud service with a smaller model". **Wispr Flow's latency is network,
not compute** — a teardown of its own logs shows `transcribe: 0.21s` of inference wrapped in
`basetenPing: 593ms` + `webSocket: 416ms`. We delete a second of network from an already-solved
problem.

Full reasoning: `PLAN.md`. The ~9,400 lines of sourced research behind it: `docs/research/`.

---

## 2. State at handoff

| Issue | What | Verified how |
|---|---|---|
| 3 | Hotkey: `CGEventTap` on `.flagsChanged`, held Right Option | Bobby's **physical keypresses** produced edges |
| 4 | Audio: `AVAudioSinkNode` + lock-free ring buffer | real mic, 192,000 frames = **exactly 4.0 s**, 0 dropped |
| 5 | Injection: pasteboard + synthetic ⌘V, change-count-guarded restore | text landed in **TextEdit**, clipboard restored |
| 19–22 | Hardware bit, Secure Input, tap re-arm, deterministic fault injection | all closed with pasted evidence |

Verified on `9f93969`: seven `.engine` gates exit 0, `swift build` green, 46 tests passed,
`swiftlint --strict` 0 violations in 14 files, packaged smoke OK.

**Open work is GitHub issues, and the numbers are real.** `#N` in `.engine/BACKLOG.md` IS the issue
number (ids ≥ 4). `.engine/checks/backlog-matches-github.sh` fails closed if that stops being
true, and also if an issue closes while its backlog line still says `S0`.
Backlog items 1–3 predate the migration and collide with PR numbers 1–3 — never cite them bare.

---

## 3. THE UPGRADE ITSELF — ORDER MATTERS, AND IT IS THE OPPOSITE OF THE OBVIOUS ONE

**macOS FIRST, Xcode SECOND.** I initially told Bobby the reverse — "get Xcode 26 downloading before
anything else, it's the long pole" — and that is impossible. Measured from the App Store's own
metadata on 2026-08-22:

```
$ curl -s "https://itunes.apple.com/lookup?id=497799835&country=us"
  version:          26.6
  minimumOsVersion: 26.2      <-- Xcode 26 CANNOT be installed on macOS 15
  fileSizeBytes:    2.4 GB
```

So Xcode 26 cannot be downloaded or installed until macOS 26 is already running. It is also only
2.4 GB — the macOS update is the real long pole at **10.9 GB** (or 17.9 GB for the full installer).

Target, from `softwareupdate --list-full-installers`: **macOS Tahoe 26.6.2, build 25G83**.

### 3.0 Install macOS (needs a sudo password, reboots the machine)

The download can be staged without a password and was started for Bobby on 2026-08-22:

```sh
softwareupdate --download "macOS Tahoe 26.6.2-25G83"     # no password needed
softwareupdate --install  "macOS Tahoe 26.6.2-25G83" --restart   # password + reboot
```

Or just System Settings → General → Software Update, which is the same thing with a progress bar.

**Note for the #11 spike: FB22149971 was reported against macOS 26.3, and 26.6.2 is six point
releases later.** The streaming bug may simply be fixed. That does not remove the spike — it makes
it cheap and likely to come back GO.

### 3.1 Confirm the toolchain actually moved

```sh
sw_vers                      # expect ProductVersion 26.x
xcodebuild -version          # expect Xcode 26.x  — NOT 16.2
xcrun --show-sdk-version     # expect 26.x  — THIS is the one that matters
```

**The SDK is the point, not the OS.** `SpeechAnalyzer` and `FoundationModels` ship with Xcode, not
with macOS. If `--show-sdk-version` still says 15.x, run
`sudo xcode-select -switch /Applications/Xcode.app` and check again. Nothing below is possible until
this reads 26.

Install Xcode 26 from the App Store (2.4 GB) once macOS 26 is running — `mas` is installed on this
machine, but it did not list Xcode pre-upgrade, so the App Store app is the reliable route.

Then prove the frameworks are actually present, rather than assuming the version implies it:

```sh
ls -d "$(xcrun --show-sdk-path)/System/Library/Frameworks/FoundationModels.framework"
grep -c "SpeechAnalyzer\|SpeechTranscriber" \
  "$(xcrun --show-sdk-path)/System/Library/Frameworks/Speech.framework/Versions/A/Modules/Speech.swiftmodule/arm64e-apple-macos.swiftinterface"
```

On 2026-08-22 these were: **absent**, and **0**. Both must change.

### 3.2 Rebuild from clean and re-run every gate

The toolchain changed underneath `.build/`, so clear it:

```sh
rm -rf .build
scripts/fetch-sparkle.sh          # Vendor/ is gitignored; re-fetch if missing
swift build && swift test && swiftlint --strict
for c in .engine/checks/*.sh; do echo "== $c"; "$c"; done
```

Expect 46 tests. If the count differs, something changed — find out what before proceeding, and do
not quote the old number (TRAP-17).

### 3.3 Re-grant permissions — expected, not breakage

The OS upgrade resets TCC. PushText will re-ask for **Microphone** and **Accessibility**.

Grant once. It will NOT re-ask on every build, because `scripts/setup-dev-signing.sh` gives the app a
stable code identity. If it *does* re-ask every build, that identity is missing — re-run the script
and check `build-app.sh` prints `signing with identity: PushText Dev Signing` rather than a WARNING
about ad-hoc.

### 3.4 Re-run the three probes — they are the fastest proof the app still works

```sh
APP=$(scripts/build-app.sh 2>/dev/null | tail -1)

# Hotkey: hold Right Option a few times during the window
PUSHTEXT_HOTKEY_PROBE=1 PUSHTEXT_HOTKEY_PROBE_SECONDS=15 "$APP/Contents/MacOS/PushText"

# Hotkey, self-driving (no human): expect 1 pressed / 1 released, and 0/0 for the left-Option control
PUSHTEXT_HOTKEY_PROBE=1 PUSHTEXT_HOTKEY_PROBE_SYNTHETIC=1 "$APP/Contents/MacOS/PushText"
PUSHTEXT_HOTKEY_PROBE=1 PUSHTEXT_HOTKEY_PROBE_SYNTHETIC=other "$APP/Contents/MacOS/PushText"

# Audio: expect frames == seconds * sampleRate, dropped=0, monotonic+contiguous, silent=false
PUSHTEXT_AUDIO_PROBE=1 PUSHTEXT_AUDIO_PROBE_SECONDS=4 "$APP/Contents/MacOS/PushText"

# Injection, safe mode (no keystroke): expect restore + foreign-write preserved
PUSHTEXT_INJECT_PROBE=1 PUSHTEXT_INJECT_CLIPBOARD_ONLY=1 "$APP/Contents/MacOS/PushText"
```

`scripts/test-packaged-app.sh` runs the structural and probe assertions together and is the single
best "is it all still fine" command.

---

## 4. THEN: issue #11, and it is a GO/NO-GO

**Do not build the transcription engine before running this.**

`start(inputSequence:)` — the streaming-microphone path the whole capture design feeds — has an open
bug on macOS **26.3**: `_GenericObjCError ... nilError`, radar **FB22149971**. File-based
transcription works on the same audio. Suspected causes: format mismatch, buffers under 4096 frames,
non-monotonic `bufferStartTime`.

We have already removed the third: `AudioBuffer.startTime` is derived from a running frame count, so
timestamps are monotonic and contiguous **by construction**, and the probe asserts both.

- **If streaming works** → issue 12 (`AppleSpeechEngine`) is straightforward. Conform to
  `TranscriptionEngine`, swap out `MockTranscriptionEngine` in `PushTextApp.init()`.
- **If it reproduces** → pivot to chunked file-based transcription. That changes the capture contract
  and the latency budget, and issue 15's numbers with it. `TranscriptionEngine` exists precisely so
  this is a new conformer rather than surgery.

Also verify the API renames landed — the WWDC names 404 on live docs:
`allocatedLocales` → **`reservedLocales`**, `deallocate(locale:)` → **`release(reservedLocale:)`**,
`.offlineTranscription` → **`.transcription`**. Every WWDC-derived tutorial you find is stale.

Then issue 13 (`contextualStrings` with `SpeechTranscriber`) — highest value per minute in Phase 1;
it decides whether the custom dictionary can bias the engine or is post-pass only.

---

## 5. Decisions that are SETTLED — do not re-litigate

- **Cleanup runs in-process via `import FoundationModels`. apfel is NOT a runtime dependency.**
  apfel is a CLI + OpenAI-compatible HTTP shim over the same framework. It defaults to port **11434**,
  which is Ollama's, and Ollama runs on this machine — the failure is not a bind error but Ollama
  silently answering with a different model. In-process also gives typed errors and **prewarming on
  key-down**, which the OpenAI protocol has no verb for. apfel stays a dev-time shell convenience.
- **Right Option, not Fn.** Fn doesn't exist on non-Apple keyboards and its system action is
  unsuppressible — `TextInputSwitcher.app` handles it via `_CGSSetSymbolicHotKey` and imports
  `CGEventTapCreate` zero times, so a tap can never swallow it.
- **Pasteboard, not AX, for insertion.** AX writes return success while doing nothing in Electron,
  Chrome, VS Code, Google Docs and Pages.
- **Never request Input Monitoring.** The OS's own `TCCServiceList.plist` marks it `requiresAdmin`;
  Accessibility does not. Microphone + Accessibility + PostEvent is the whole set.
- **Cleanup is polish, not a required stage.** `SpeechTranscriber` already punctuates and capitalizes
  (99.9% / 99.7% across 5,559 sampled hypotheses), and Apple's own measurements show LLM correction
  can make good ASR *worse*. Every failure path falls back to the raw transcript silently.
- **Platform floor rises to macOS 26** (issue 16) once the engines land. `Package.swift` currently
  says `.macOS(.v15)` — needed for `Synchronization.Atomic` — and moves together with
  `MIN_SYSTEM_VERSION` in `scripts/build-app.sh`.

---

## 6. What will bite you

`.engine/traps.md` has all 19 with evidence. The ones most likely to matter next:

- **TRAP-17** — a test count in prose goes stale the moment the suite changes. Re-run, then quote.
- **TRAP-6 / TRAP-19** — never silence a build script's stderr, and never bundle a file write with a
  gated action; a blocked command runs *none* of its parts, and a stale binary produces output that
  is internally consistent and entirely wrong.
- **TRAP-11** — assert the post-condition, not the attempt. A "we handled it" counter passes on a
  handler that does nothing.
- **TRAP-14 / TRAP-15** — the signing script's openssl and `find-identity -v` bugs, both fixed. If
  signing breaks again after the upgrade, read these before debugging from scratch.
- **TRAP-18** — the paste settle delay is a race; do not tune it down because it "seems to work".

---

## 7. Honest state of the evidence

Everything in section 2 was observed on real hardware. Three things were **not**:

- **Memory ordering in `AudioRingBuffer`.** Weakening `.releasing` → `.relaxed` passes the whole
  suite. Correctness rests on the acquire/release pairing argument, not on a green run.
- **Injection beyond TextEdit** (issue 27). The Electron and browser cases that motivate the whole
  pasteboard approach were never exercised. A native app succeeding proves the least interesting case.
- **Audio device changes and interleaved stereo** (issue 24). Both branches exist; neither has run.

Nothing about macOS 26 behaviour has been executed at all. Every claim in `docs/research/01` and
`docs/research/02` is documentation-derived. Phase 1 exists to convert that into observation, and it
opens with the spike that can invalidate the architecture.
