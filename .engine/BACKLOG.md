# PushText backlog

Taxonomy: `#N - title - S0|S1|S2|DONE` (S0 captured, S1 stoke-planned, S2 brutally audited).
Dependencies are explicit; do not start a task whose `blocked-by` is not DONE.

Authorities: `PLAN.md` (decisions + phases), `docs/research/` (the evidence behind them),
`.engine/MEMORY.md` (PROVE semantics: live surface = a real app receiving real text).

## Phase 0 - buildable on macOS 15.1, no Tahoe required

#1 - SPM skeleton: three targets, purity gate, Sparkle, packaging, CI - DONE
  (2026-08-22: swift build green; 15 tests pass; swiftlint --strict 0 violations; core-purity.sh
  5/5 planted imports detected; build-app.sh produced a signed dist/PushText.app that codesign
  --verify --deep --strict accepts; launched via `open -g`, stayed resident, terminated cleanly.)

#2 - Repo shape parity with TermTile - DONE
  (2026-08-22: master branch, docs/decisions + docs/research layout, AGENTS/CLAUDE/PROJECT/SECURITY/
  LICENSE/cwc.config.json, .engine living layer, .skills manifest, dependabot + PR template +
  semgrep + release workflows, install/notarize/notary-status/test-packaged scripts.)

#3 - HotkeyMonitor: CGEventTap on .flagsChanged, held Right-Option - S0
  blocked-by: none. Device-dependent flag bit 0x40 (NX_DEVICERALTKEYMASK), NOT
  CGEventFlags.maskAlternate - the union mask makes a right-side release invisible while the left
  side is held, and the microphone stays open. Needs the watchdog already modelled in
  DictationMachine. Authority: docs/research/04 sec 1.

#4 - AudioCapture: AVAudioSinkNode - S0
  blocked-by: none. `installTap` carries a documented 100-400 ms latency floor that appears in the
  SDK header and not in the web docs. Do not keep the engine warm: the orange microphone indicator
  tracks "engine is running", so a warm engine lights it permanently. Authority: docs/research/04 sec 5.

#5 - TextInjector: pasteboard + synthetic Command-V, change-count-guarded restore - S0
  blocked-by: none. Resolve the V keycode through UCKeyTranslate WITH Command applied; hard-coding
  keycode 9 breaks on Dvorak-QWERTY-Command. Authority: docs/research/04 sec 3.

#6 - Permission probes + three-state recovery UX - S0
  blocked-by: #3, #5 (nothing to probe for until they exist). Microphone, Accessibility, PostEvent.
  Never Input Monitoring. Port TermTile's trusted/needsFirstGrant/grantBroken model and its tccutil
  repairer. Authority: docs/research/04 sec 4, docs/research/05.

#7 - HUD: non-activating NSPanel over full-screen apps - S0
  blocked-by: #3. `canBecomeKey = false` is load-bearing: stealing focus breaks injection, which is
  the entire product. Authority: docs/research/04 sec 7.

#8 - isPlausibleCleanup drift guard + tests - S0
  blocked-by: none. Pure function in Core, red-first. The differentiator: Handy (30k stars),
  VoiceInk (6k) and Whispering (4.7k) all fall back to raw output only on TRANSPORT errors and never
  compare content. Thresholds to start from: length ratio 0.72/1.35, Levenshtein 0.62, negation-count
  equality, token grounding, no novel content words. Authority: docs/research/06, docs/research/03.

#9 - Custom dictionary matcher + tests - S0
  blocked-by: none. Longest-match-first, NFC-normalized, fenced by \p{L}\p{N} lookarounds rather than
  \b, phrase parts joined with [\s\-]* so "CloudCode" matches. Authority: docs/research/03.

#10 - History persistence (JSONL) - S0
  blocked-by: #3, #4.

## Phase 1 - requires macOS 26 AND Xcode 26

#11 - SPIKE: does start(inputSequence:) work on this Tahoe build? - S0
  blocked-by: the upgrade. GO/NO-GO for the whole architecture. FB22149971 reports
  `_GenericObjCError ... nilError` on macOS 26.3 for the streaming path, while file-based
  transcription works on identical audio. If it reproduces, #12 becomes chunked file transcription
  and the latency budget is rewritten. Do not build on the streaming path before this runs.
  Authority: docs/research/01.

#12 - AppleSpeechEngine conforming to TranscriptionEngine - S0
  blocked-by: #11. Volatile results must REPLACE, never append - they duplicate the tail of the last
  finalized result. Wrap `transcriber.results` in a timeout; the stream hangs in the field.

#13 - SPIKE: contextualStrings with SpeechTranscriber - S0
  blocked-by: the upgrade. Documented only for DictationTranscriber and capped at 100 short phrases.
  Determines whether #9 can bias the engine or is post-pass only. Highest value per minute of any
  Phase 1 check.

#14 - FoundationModelsCleanup behind the drift guard - S0
  blocked-by: #8, #11. Permissive guardrails at construction time; `respond` not `streamResponse`;
  silent fallback to the raw transcript on all nine GenerationError cases.

#15 - Measure and publish real latency numbers - S0
  blocked-by: #12. No published SpeechAnalyzer figure exists anywhere. n>=3, spanning short/medium/
  long utterances. We cite our own numbers or none.

## Phase 2 - ship

#16 - Bump platform floor to macOS 26 - S0
  blocked-by: #12, #14. One line in Package.swift plus MIN_SYSTEM_VERSION in build-app.sh.

#17 - Sparkle EdDSA keypair + first release - S0
  blocked-by: #16. build-app.sh currently refuses to ship without SU_PUBLIC_ED_KEY in CI and warns
  locally; generate_keys puts the private half in the login Keychain.

#18 - Context-aware formatting per frontmost app - S0
  blocked-by: #14.
