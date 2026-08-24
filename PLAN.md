# Mumbler — plan

Written 2026-08-22 from `docs/research/00`–`07` (9,412 lines, ~400 sources).
Nothing here has been compiled or run. Every runtime claim is documentation- or
source-derived; the Tahoe half of this cannot be executed on this machine at all.

---

## 1. The thesis changed

The brief was "clone Wispr Flow, but free and offline." Research found the actual
opening is better than that, and for a different reason than assumed.

**Wispr Flow's latency is network, not compute.** From a forensic teardown of its own
logs: `transcribe: 0.21s` of inference wrapped in `basetenPing: 593ms` +
`webSocket: 416ms`. A local app beats it by ~1 second *without needing a better model*.
We are not trying to match a cloud service on quality with a smaller model — we are
deleting a second of network from a solved problem.

**Apple's `SpeechTranscriber` already punctuates and capitalizes.** Measured across
5,559 published raw hypotheses: 99.9% contain punctuation, 99.7% start capitalized.
The widely-repeated claim that it emits unpunctuated text traces to a single
picovoice.ai page and is wrong.

That second finding is the most important one in the whole corpus, because it
demotes the LLM. **Cleanup is polish, not load-bearing.** Which means:

- The product works with `FoundationModels` switched off entirely.
- The Apple-Intelligence dependency, the 40% guardrail false-refusal rate, the
  background rate-limiting, the 4,096-token ceiling — all become degradations of an
  optional feature rather than product-killing risks.
- The apfel question (§2.1) stops being architectural and becomes a footnote.

**And the LLM can actively make it worse.** Apple's own measurement: every LLM
configuration degraded a 2.2% WER baseline; Mistral-7B zero-shot hit 32.0% with
3–12% hallucination. Caveat: that's N-best correction on read speech, not dictation
formatting — different task. But the direction is a warning, and the useful part
transfers: **5 few-shot examples beat 4× the parameters** (Llama-8B 16.7% → 7.1%).
Our cleanup prompt gets few-shot examples, not a bigger model.

---

## 2. Decisions — locked

Each is mine to make (Tenet 5) and each is backed by evidence in the research files.

### 2.1 Cleanup runs in-process via `import FoundationModels`. apfel is not a runtime dependency.
apfel is a CLI + OpenAI-compatible HTTP shim over the same framework. For a native
Swift app it costs an install step, loses typed errors (apfel reconstructs them by
string-matching `desc.contains(["guardrail","content policy","unsafe"])`), makes
guardrail mode a daemon-launch flag instead of a per-session choice, and has no verb
for **prewarm** — the single biggest latency win available, since prewarming on
hotkey-down buys the user's entire speech duration for free.

**Verified on this machine, 2026-08-22:**
```
$ lsof -nP -iTCP:11434 -sTCP:LISTEN
ollama  1228 evancnavarro  3u  IPv4  TCP 127.0.0.1:11434 (LISTEN)
```
apfel's default port is 11434 (`CLIArguments.swift:104`); its own `Server.swift`
prints *"Another process (e.g. Ollama) may be listening on this port."* The failure
is not a bind error you'd notice — it's Ollama silently answering
`/v1/chat/completions` and cleaning dictation with a different model.

apfel stays useful as a **dev-time** tool for shell experiments. Not shipped.

### 2.2 Hotkey: `CGEvent.tapCreate(.defaultTap)` on `.flagsChanged`, held **Right-Option** (keycode 61).
Only mechanism that both detects a bare held modifier and can suppress it.
`NSEvent` global monitors are observe-only (Apple's docs); Carbon
`RegisterEventHotKey` can't express a bare modifier and its header says right-side
modifiers are "Not supported on Mac OS X."

**Fn is rejected as the default.** It doesn't exist on non-Apple keyboards, and its
system action is unsuppressible — `TextInputSwitcher.app` imports
`_CGSSetSymbolicHotKey` and `_TISGetFnUsageType` and imports `CGEventTapCreate`
**zero** times; it never enters the tap chain. The video author demoing on Fn was
living with the conflict, not solving it. Fn stays available as a user override with
a warning.

Strongest supporting fact: **Secure Input filters `keyDown`/`keyUp` but `flagsChanged`
keeps flowing.** A bare-modifier hotkey works in password fields where a chord dies
silently.

Must use device-dependent flag bits (`0x40` right-⌥), not `CGEventFlags.maskAlternate`
— the union mask means holding left-⌥ makes the right-⌥ release invisible and **the
mic hangs open**.

### 2.3 Injection: `NSPasteboard` + synthetic ⌘V, change-count-guarded restore.
Five of five open-source dictation apps do this; **none** writes text via
`AXUIElement`. AX set-text returns *success while doing nothing* in Electron, VS Code,
Google Docs and Pages, and is barred under the App Sandbox. Murmur's "verified AX
insert with pasteboard fallback" inverts this — the fallback is the correct primary.

Resolve the V keycode via `UCKeyTranslate` **with Command applied**; hard-coding 9
breaks on Dvorak-QWERTY⌘.

### 2.4 We do NOT request Input Monitoring.
`CGRequestListenEventAccess` is the Input-Monitoring permission call, not a detection
mechanism. The OS's own `TCCServiceList.plist` marks it `requiresAdmin => 1`;
Accessibility has no such flag. Accessibility + `kTCCServicePostEvent` + Microphone
is the set. (`PostEvent` is a *separate* TCC service despite sharing one UI toggle.)

### 2.5 Platform floor: **macOS 26**. Single floor, no split.
I floated shipping the shell at macOS 14 with the engines gated. That's dead: without
`SpeechAnalyzer` there is no product, and legacy `SFSpeechRecognizer` is throttled
with a 1-minute limit. A Sequoia build would be a menu-bar app that can't transcribe.
Not worth doubling the engine surface for a personal tool.

This does **not** stop us developing on Sequoia today — see §4 Phase 0.

### 2.6 Output-drift verification ships in v1. This is the differentiation.
Handy (30k★), VoiceInk (6k★) and Whispering (4.7k★) all fall back to raw output
**only on transport errors** — zero content comparison. Only one 1-star repo actually
verifies, and it has usable thresholds: length ratio 0.72/1.35, Levenshtein 0.62,
negation-count equality, token grounding. Murmur's guard keys on "no novel content
words." Combine both.

The failure this prevents: you dictate "what is the capital of France" and the model
types **"Paris"** into your document.

### 2.7 Engines and cleanup sit behind protocols from commit one.
`TranscriptionEngine` and `CleanupProvider`. These were originally wrapped in
`#if canImport(FoundationModels)` + `@available(macOS 26, *)` so a mock engine could be
built against on Sequoia; that scaffolding was removed with the floor bump (#16) and the
protocols are what remain. They keep Parakeet an option we can add without surgery.

### 2.8 Guardrails: `SystemLanguageModel.Guardrails.permissiveContentTransformations`.
Apple describes it as permissively transforming input *"including potentially unsafe
content"* — practically a spec for dictation cleanup. Needed: apfel's own measurement
found default guardrails blocked **4/10 benign prompts (40%)**, including "describe
the color red to someone who has never seen any color." Small author-selected sample;
direction is unambiguous. It is a **construction-time** argument, so it's decided when
the session is built, not per request.

### 2.9 Cleanup uses `respond`, not `streamResponse`, and degrades silently.
Apple engineer, forums thread 789788: rate limiting applies on battery when the
process is backgrounded, and they recommend against streaming. A menu-bar
`LSUIElement` app is *always* backgrounded — that's the entire product. `.rateLimited`
is invisible to `.availability`. All nine `GenerationError` cases fall back to the raw
transcript without user-visible failure.

---

## 3. Architecture

Three SPM targets, mirroring TermTile's split (`docs/research/05`), with its purity check:

```
MumblerCore     pure logic, no AppKit/ApplicationServices
                · dictation state machine (idle→arming→recording→transcribing→cleaning→injecting)
                · isPlausibleCleanup() drift guard  ← pure, testable, the thing nobody else has
                · custom-dictionary matcher (longest-match-first, NFC, \p{L}\p{N} lookarounds,
                  parts joined with [\s\-]* to catch "CloudCode")
                · history model
MumblerKit      system adapters, each behind a protocol port, UI-free so it unit-tests
                · HotkeyMonitor (CGEventTap)      · AudioCapture (AVAudioSinkNode)
                · TranscriptionEngine             · CleanupProvider
                · TextInjector (pasteboard+⌘V)    · PermissionProbe / PermissionRepairer
Mumbler         SwiftUI MenuBarExtra(.window) shell + composition root in App.init()
                · non-activating NSPanel HUD (canBecomeKey = false — stealing focus breaks injection)
                · MacFaceKit components, Sparkle UpdateWindowController
```

Packaging, signing, notarization, Sparkle appcast and CI all lifted from TermTile's
`scripts/` (`docs/research/05` §4 documents every step).

---

## 4. Build phases

### Phase 0 — buildable TODAY on Sequoia 15.1. No Tahoe needed.
Roughly 70% of the app. Everything except the two engines.

0.1  Scaffold from the TermTile blueprint: `Package.swift`, three targets, `.engine/`,
     `scripts/`, `.github/`, docs, purity check. Init git, remote → `EvanCNavarro/Mumbler`
     (personal, godmode — I push without asking).
0.2  `setup-dev-signing.sh` FIRST — a stable self-signed identity, before any TCC grant
     exists. Ad-hoc signing produces a fresh cdhash per build and **silently resets every
     grant**; with four permissions in play that would be re-granting on every rebuild.
0.3  HotkeyMonitor + the right-⌥ device-flag handling. Works on 15.1.
0.4  AudioCapture via `AVAudioSinkNode` (`installTap` has a documented 100–400 ms floor
     that's in the SDK header but absent from web docs). Works on 15.1.
0.5  TextInjector + clipboard save/restore + `UCKeyTranslate` V lookup. Works on 15.1.
0.6  MockTranscriptionEngine — returns canned text on a timer. Makes the whole pipeline
     runnable end-to-end today.
0.7  HUD panel, MenuBarExtra, history, permission UX (three-state probe + `tccutil`
     repairer, lifted from TermTile).
0.8  `isPlausibleCleanup()` + its tests. Pure function, no OS dependency, and the one
     piece of real differentiation. Red-first.
0.9  Dictionary matcher + tests.
0.10 Full packaging path green: build-app → sign → smoke test → Sparkle appcast.

**Exit:** a signed, notarizable menu-bar app where holding right-⌥ pops a HUD and types
mock text into the frontmost app. Everything but the intelligence.

### Phase 1 — Tahoe spikes. First thing after upgrade, before any more architecture.
Requires macOS 26 **and Xcode 26** — the SDK ships with Xcode, not the OS. Budget both
downloads.

**S1 is a go/no-go.** `start(inputSequence:)` — the exact streaming-mic path this whole
design rests on — has an open bug on **macOS 26.3**: `_GenericObjCError ... nilError`,
FB22149971. File-based transcription works on the same audio. Suspected: format
mismatch, buffers under 4096 frames, non-monotonic `bufferStartTime`.
→ If streaming is broken on your point release, we pivot to chunked file-based
transcription and the latency budget changes. **Do not build on it before proving it.**

S2  `SpeechTranscriber.isAvailable` on your M1 Max. Expected true — the gate is Neural
    Engine core count (8-core/A13 fails, 16-core/A14+ passes), **not** Apple Intelligence.
    An empty `supportedLocales` is a *hardware* signal, not a download one.
S3  `AnalysisContext.contextualStrings` with `SpeechTranscriber` — documented only for
    `DictationTranscriber` (the 9.02% WER engine), capped at 100 short phrases. Highest
    value-per-minute check in the list; determines whether custom vocabulary biases the
    engine or is post-pass only.
S4  Measure real latency. **No published SpeechAnalyzer figure exists anywhere.** The
    ~0.13s number circulating from Muesli is Parakeet. We cite our own numbers or none.
S5  FoundationModels: availability, prewarm-on-hotkey-down win, `contextSize` at runtime
    (4,096 documented as combined input+output — read it, don't hardcode), permissive
    guardrails, `.rateLimited` under real backgrounded use.
S6  Verify the API renames landed: `reservedLocales` / `release(reservedLocale:)` /
    `.transcription`. The WWDC names (`allocatedLocales`, `deallocate`,
    `.offlineTranscription`) 404 on live docs — every WWDC-derived tutorial is stale.
S7  Run `docs/research/04` §9 — the 12-item Tahoe first-boot plan. Test #1 is Secure Input:
    confirm `flagsChanged` still flows in a password field.

### Phase 2 — real engines
Swap MockTranscriptionEngine for `AppleSpeechEngine`. Volatile results must be
**replaced, never appended** — they duplicate the tail of the last finalized result.
Wrap `transcriber.results` in a timeout (VoiceInk ships `max(20, duration*4+10)`s
because the stream hangs in the field). Then `FoundationModelsCleanup` behind the drift
guard, few-shot prompt, 2.5–4s budget with deterministic non-LLM fallback.

### Phase 3 — ship
Release notes, notarize, appcast, tag.

~~Context-aware formatting (terminal → no smart quotes, etc.)~~ — **withdrawn, measured 2026-08-23.**
The example does not occur: `SpeechTranscriber` emits straight quotes (7 straight, 0 curly across 80
real transcripts), on-device cleanup returns pure ASCII, and macOS smart-quote substitution does not
fire on a paste. See `docs/verification/task18-context-formatting.md`.

---

## 5. Open — Bobby's call

**The name.** "Mumbler" is not viable. Two App Store apps already use it, OccamBox
asserts `Mumbler®`, `github.com/Mumbler` is taken — and **`Mumble Dictation`
(heymumble.com) is the identical product**: local macOS dictation with on-device LLM
cleanup, $50 one-time. Directory stays `mumbler` until renamed; bundle ID, repo name and
all scaffolding follow the decision, so it's cheapest to make before Phase 0.2.

---

## 6. Risk register

| # | Risk | Evidence | Mitigation |
|---|------|----------|------------|
| R1 | `start(inputSequence:)` broken on 26.3 | FB22149971, reproduced by others | Phase 1 S1 go/no-go before building on it |
| R2 | Cleanup degrades good ASR | Apple: every LLM config worsened 2.2% baseline | Drift guard §2.6; cleanup off by default until measured |
| R3 | Guardrails refuse benign speech | 4/10 blocked under `.default` | Permissive guardrails; silent raw fallback |
| R4 | Background rate-limiting | Apple engineer, thread 789788 | `respond` not `streamResponse`; degrade silently |
| R5 | Mic indicator always lit if engine kept warm | `AVAudioEngine.h`: dot tracks "engine is running" | Don't prewarm audio; prewarm the *LLM* instead |
| R6 | TCC grants reset every rebuild | ad-hoc cdhash churn | Stable self-signed identity, Phase 0.2, first |
| R7 | `Bundle.module` crashes shipped builds | bakes absolute `.build` path | Copy TermTile's `BundleResources.swift` + awk guard |
| R8 | Xcode 26 download blocks everything | SDK ships with Xcode | Start it at the same time as the OS upgrade |

---

## 7. What this plan cannot see

No line of the Tahoe half has been compiled or run. §2.1, §2.8, §2.9 and all of Phase 1
rest on Apple's documentation, forum posts, and other people's source — not on
observation. Phase 1 exists to convert them into observations, and it is deliberately
front-loaded with the one that can invalidate the architecture (S1).

The Phase 0 decisions (§2.2, §2.3, §2.4) are better grounded — read out of SDK headers,
`TCCServiceList.plist`, and five shipping apps' source — but still not run here.
