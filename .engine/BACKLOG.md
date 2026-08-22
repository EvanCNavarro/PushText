# PushText backlog

Taxonomy: `#N - title - S0|S1|S2|DONE` (S0 captured, S1 stoke-planned, S2 brutally audited).
Dependencies are explicit; do not start a task whose `blocked-by` is not DONE.

**`#N` IS THE GITHUB ISSUE NUMBER.** Every id from #4 up was filed as a real issue on
`EvanCNavarro/PushText` and the numbers align exactly. GitHub is the STATE authority (open/closed);
this file is the narrative record — the reasoning, the measurements, the disproved hypotheses. Keep
them consistent; when they disagree, GitHub is right about state and this file is right about why.

**#1, #2 and #3 predate that migration and COLLIDE with PRs #1, #2 and #3.** They are done and must
never be cited bare — write "backlog item 3", not "#3". `.engine/checks/backlog-ids-resolve.sh`
enforces the rest.

*Why this exists:* these ids were originally file-local, and stayed file-local after the repo gained
a GitHub remote — at which point `#19` silently became a claim about a GitHub issue that did not
exist. Three merged PR bodies shipped literal `Closes #19` auto-close syntax pointing at nothing.
Caught by the `citation-resolve-check` Stop hook, not by me.

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

#3 - HotkeyMonitor: CGEventTap on .flagsChanged, held Right-Option - DONE
  (2026-08-22: ModifierGate in Core - 9 tests, red-first, 3 planted defects all caught including the
  union-mask bug; CGEventTapHotkeyMonitor in Kit; proven on the real tap via HotkeyProbe - bound key
  1 pressed / 1 released, LEFT Option negative control 0/0. Constants read from IOLLEvent.h and
  Events.h. Evidence: docs/verification/task3-hotkey.md. Gaps tracked as #19, #20, #21.)

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

## Gaps left open by #3

#19 - Confirm real hardware sets NX_DEVICERALTKEYMASK - DONE
  (2026-08-22: Bobby pressed the physical key with the probe listening. pressed=2 released=1, from a
  gate that reads ONLY bit 0x40 - nothing else could have produced those edges, so real hardware does
  set NX_DEVICERALTKEYMASK. This was the last inference in the hotkey path; every earlier edge came
  from a synthetic CGEvent whose device bit this code had set itself. Caveat kept rather than tidied
  away: one press had no matching release inside the 20s window, consistent with the key still being
  held at expiry, but the balancing release was never OBSERVED. Two later runs recorded 0 edges - no
  keys were pressed during them, so they are not counter-evidence.)

#20 - Reproduce the Secure Input claim - DONE
  (2026-08-22: reproduced directly rather than waiting on a password field. The probe calls
  EnableSecureEventInput() itself, asserts IsSecureEventInputEnabled()==true as the control - without
  it the run would prove nothing - posts a bare modifier, and observes 1 pressed / 1 released while
  Secure Input is ACTIVE. Secure Input released cleanly afterwards. Evidence:
  docs/verification/task3-hotkey.md. Residual: synthetic HID-level events, not hardware - folded
  into #19.)

#21 - Exercise the tap re-arm branch - DONE
  (2026-08-22: built a stallInCallback fault-injection seam and drove the branch. Findings all
  re-sampled rather than taken from one run: a LISTEN-ONLY stalled tap is never disabled (TRAP-8);
  a stalled .defaultTap drops the key-release in 6/6 runs while the OS disable is INTERMITTENT
  (0/6, then 2/5); and macOS's own flagsState stays latched at 0x20080040, so every state-based
  recovery is blind (TRAP-9). A 250ms flagsState poll was built, measured over 5 runs, shown to
  change nothing, and REMOVED. Landed instead: resynchronise-after-re-arm for the intermittent
  disable case, plus AppModel.maximumCaptureDuration - a time-based force-close, the only signal
  that cannot be corrupted this way. 4 tests; both planted defects caught.)

#22 - Make the tap-disable fault injection deterministic - DONE
  (2026-08-22: solved by finding the right TRIGGER, not by building recovery machinery. Two
  hypotheses died first: raising event pressure with a 12-event burst reached the disable branch in
  0/5 runs; and I was about to add a tapIsEnabled health poll when the red-first run showed the
  monitor ALREADY recovered 3/3 - calling CGEvent.tapEnable(enable:false) on our own tap makes the
  OS deliver kCGEventTapDisabledByUserInput to the callback, so the existing branch was reachable
  all along (TRAP-12). Landed forceDisableTapForTesting() + isTapEnabled + lastDisableReason; 5/5
  deterministic. Now a permanent gate in test-packaged-app.sh asserting enabled=true rather than
  reEnables - a planted no-op re-arm still reports reEnables=1 while the tap stays dead, so the
  counter cannot tell recovery from a corpse (TRAP-11). Both plants caught. The health poll was NOT
  built: no evidence it is needed.)
