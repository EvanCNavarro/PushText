# PushText backlog

Taxonomy: `#N - title - S0|S1|S2|DONE` (S0 captured, S1 stoke-planned, S2 brutally audited).
Dependencies are explicit; do not start a task whose `blocked-by` is not DONE.

**`#N` IS THE GITHUB ISSUE NUMBER.** Every id from #4 up was filed as a real issue on
`EvanCNavarro/PushText` and the numbers align exactly. GitHub is the STATE authority (open/closed);
this file is the narrative record — the reasoning, the measurements, the disproved hypotheses. Keep
them consistent; when they disagree, GitHub is right about state and this file is right about why.

**#1, #2 and #3 predate that migration and COLLIDE with PRs #1, #2 and #3.** They are done and must
never be cited bare — write "backlog item 3", not "#3". `.engine/checks/backlog-matches-github.sh`
enforces the rest: every id ≥ 4 resolves, and every `DONE`/`S0` marker agrees with the issue's state.
It fails closed on `closed upstream, still pending here` — the direction that misdirects "what's
next" — and only NOTEs the transient mirror, since an issue closes at the merge and a PR that marks
its own line `DONE` would otherwise be red before the merge and after it.

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

#4 - AudioCapture: AVAudioSinkNode - DONE
  (2026-08-22: AudioRingBuffer in Core - lock-free SPSC, red-first, 4 planted defects of which 3
  caught and the memory-ordering one explicitly NOT, recorded rather than implied.
  AVAudioEngineCapture in Kit on AVAudioSinkNode, chosen because installTapOnBus's own header caps
  bufferSize at [100, 400] ms. Proven on the real mic: 80 buffers, 192000 frames at 48 kHz in 4.0s
  = exactly 4.0s, dropped=0, silent=false, timestamps monotonic AND contiguous by construction.
  Both timestamp assertions planted and caught independently. Fixed two inherited signing bugs on
  the way (TRAP-14, TRAP-15) and one semantic bug the concurrency test exposed (TRAP-16).
  Evidence: docs/verification/task4-audio.md. Gaps: #24.)

#5 - TextInjector: pasteboard + synthetic Command-V, change-count-guarded restore - DONE
  (2026-08-22: ClipboardRestore policy in Core, red-first; PasteboardTextInjector in Kit. Paste
  keycode resolved via UCKeyTranslate WITH cmdKey rather than hard-coded, because Dvorak-QWERTY-Cmd
  reverts to QWERTY only while Command is held. Proven end to end into TextEdit - marker arrived
  intact AND the clipboard was restored - plus both policy branches exercised against the live
  NSPasteboard. The settle delay was PLANTED to 0.0 and the run then pasted the restored sentinel
  instead of the text, so the delay is load-bearing by measurement. Evidence:
  docs/verification/task5-injection.md. Gaps: #27.)

#6 - Permission probes + three-state recovery UX - DONE
  (2026-08-23: the probe and the menu rows shipped earlier; this closes the recovery half. One
  defect fixed and one specified component deliberately NOT built.
  The defect: SystemPermissionProbe derives BOTH needsFirstGrant and grantBroken for the microphone
  from AVAuthorizationStatus.notDetermined - the latch that separates them is ours, not TCC's - and
  requestAccess prompts whenever the status is .notDetermined. So the app can ask in both cases, by
  construction. The menu instead sent a broken microphone grant to System Settings, where, with no
  TCC entry recorded, there is nothing to act on. It now offers "Allow Again..." and prompts, while
  keeping the different diagnosis in the copy. Accessibility and PostEvent are the opposite case -
  their entry IS in the list, ticked and ineffective - so they keep the Settings route, and the
  asymmetry is asserted in both directions so a later "make it consistent" edit cannot hand them a
  button that does nothing.
  NOT built: TCCPermissionRepairer. For the microphone it is unnecessary - a broken grant is
  .notDetermined, so there is nothing to reset. For Accessibility and PostEvent it would make
  recovery WORSE: resetting removes the entry, neither has a prompt the app can raise, and the user
  must then re-ADD PushText with `+` rather than toggle an entry that was already there. That holds
  regardless of privilege, so the sudo question never decides anything.
  Measured, and reported as inconclusive rather than as a disproof: tccutil reset succeeded WITHOUT
  sudo for all three services against a throwaway bundle id, which contradicts docs/research/04 sec
  4.2 - but that id held no grants, so "Successfully reset" may be a no-op that never touched the
  root-owned system database. The claim stands unverified in both directions. Trap found on the way:
  tccutil validates the bundle id against LaunchServices BEFORE any privilege check, so an
  unregistered id returns exit=64 / OSStatus -10814 for every service, which looks exactly like a
  permission failure and is not one.
  Evidence: docs/verification/task6-permission-recovery.md.)
  Original note, blocked-by: #3, #5 (nothing to probe for until they exist). Microphone,
  Accessibility, PostEvent. Never Input Monitoring. Port TermTile's trusted/needsFirstGrant/
  grantBroken model and its tccutil repairer. Authority: docs/research/04 sec 4, docs/research/05.

#7 - HUD: non-activating NSPanel over full-screen apps - DONE
  (2026-08-23: superseded by #46 and delivered in PR #50/#54/#56. DictationHUDPanel is a
  .nonactivatingPanel with canBecomeKey and canBecomeMain both false, shown with
  orderFrontRegardless rather than makeKeyAndOrderFront; .canJoinAllSpaces + .fullScreenAuxiliary +
  .stationary put it over full-screen apps where a plain window would not appear. The focus
  requirement - the whole reason this issue existed, since a HUD that took focus would receive the
  injected Command-V instead of the user's document - was VERIFIED rather than assumed: with the HUD
  on screen, the frontmost app was iTerm2 and PushText's AXFocusedWindow read `missing value` while
  it owned one window. Original note kept because it is still the load-bearing constraint:
  `canBecomeKey = false` breaks injection if it ever flips. Authority: docs/research/04 sec 7.)

#8 - isPlausibleCleanup drift guard + tests - DONE
  blocked-by: none. Pure function in Core, red-first. The differentiator: Handy (30k stars),
  VoiceInk (6k) and Whispering (4.7k) all fall back to raw output only on TRANSPORT errors and never
  compare content. Thresholds to start from: length ratio 0.72/1.35, Levenshtein 0.62, negation-count
  equality, token grounding, no novel content words. Authority: docs/research/06, docs/research/03.

#9 - Custom dictionary matcher + tests - DONE
  blocked-by: none. Longest-match-first, NFC-normalized, fenced by \p{L}\p{N} lookarounds rather than
  \b, phrase parts joined with [\s\-]* so "CloudCode" matches. Authority: docs/research/03.

#10 - History persistence (JSONL) - DONE
  (2026-08-23: PR #85. Greenfield - a capability-grep found no history, no JSONL and no Application
  Support code anywhere - so the model, the store AND the wiring shipped together, deliberately:
  three components in this repo already had tests and zero call sites, and a fourth was not worth
  adding. JSONL because appending is one write of one line, so a crash mid-write costs the last
  entry, where a JSON array is read-parse-mutate-rewrite per utterance and can lose everything. The
  same property governs reads, which is why decodeFile SKIPS unparseable lines rather than throwing:
  a decoder that gave up on the first bad line would return an empty history and discard the exact
  durability the format was chosen for. Trimming keeps the newest and happens on READ, not on
  append, so the cap never reintroduces the whole-file write on the latency-sensitive path. Split
  per ADR-0001: record + codec are pure Foundation in Core; JSONLHistoryStore sits in Kit behind a
  port so AppModel never touches a file. Six plants, one of which lied and was rebuilt.)

## Phase 1 - requires macOS 26 AND Xcode 26

#11 - SPIKE: does start(inputSequence:) work on this Tahoe build? - DONE
  (2026-08-22: GO. FB22149971 does NOT reproduce on macOS 26.6.2 / Xcode 26.6 / SDK macosx26.5 -
  the radar was filed against 26.3. A standalone spike ran an A/B over identical audio holding
  locale, preset, buffers and chunk size constant, varying ONLY the entry point:
  analyzeSequence(_:) and start(inputSequence:) both returned the same final text, with volatile
  partials arriving during the feed. 10/10 streaming runs succeeded across 512/1024/2048/4096/8192
  frames per buffer - including both sub-4096 sizes the radar suspects. The verdict was
  battle-tested before it was believed: a planted missing-file failure proved the failure path
  prints, so STREAMING_OK is not a never-exercised default. #12 is therefore a conformer against
  the streaming path, not a pivot to chunked file transcription.
  Found on the way: a format mismatch is an uncatchable SIGTRAP inside Speech.framework (#32);
  Apple Intelligence reports restricted/assetIsNotReady, which gates #14 (#33);
  installedLocales disagreed with status(forModules:) (TRAP-21); reserve(locale:) returned false
  while succeeding (TRAP-22). NOT established: the real-microphone path, transcription accuracy,
  long sessions. Evidence: docs/verification/task11-streaming-spike.md; re-runnable spike at
  docs/verification/spikes/11-streaming/.)

#12 - AppleSpeechEngine conforming to TranscriptionEngine - DONE
  (2026-08-22: AppleSpeechEngine actor on the streaming path, CONSTRUCTED in PushTextApp via
  TranscriptionEngineFactory - constructed, not invoked. An earlier version of this entry said
  "wired into PushTextApp", which overstated it: AppModel holds the engine and never calls
  beginUtterance/append/finishUtterance, and the app builds no capture, hotkey or injector at all.
  Assembling the pipeline is #39. Corrected rather than left standing, because a wrong fact reads
  as truth and this one would have made the next session think the app dictates. The conversion boundary #32 demands is its own tested type,
  AudioFormatConverter, because the gap is wider than a resample: capture emits mono Float32 at the
  hardware rate (48 kHz) and bestAvailableAudioFormat returned 16 kHz mono INT16 - commonFormat 3
  per AVAudioFormat.h - so a rate-only fix would still trap. Red-first: the suite was run against a
  non-converting stub and failed on sampleRate 48000!=16000, commonFormat 1!=3 and frameLength
  24000!=~8000, which is the assertions failing rather than the harness. Two plants confirmed the
  suite is not vacuous - emitting silence failed ONLY the signal test (peak 0 > 8000), proving the
  format assertions are blind to silence on their own, and a 'rates match, nothing to do' shortcut
  failed only the same-rate test; restoration verified byte-identical by diff.
  Proven on the real SpeechAnalyzer through TranscriptionProbe with file audio, at production
  pacing: 77 buffers, 183296 frames at 48 kHz in, delivered 3.82s, engine=ok, exit 0.
  The mock is NOT the fallback for unsupported systems - it returns canned phrases and this app
  types its output into whatever window has focus, so UnsupportedTranscriptionEngine refuses
  instead. Volatile results are dropped rather than accumulated; only isFinal text is kept.
  Gated on the SDK as well as the OS: `#if canImport(FoundationModels)` + `@available(macOS 26, *)`
  answer different questions, and CI's macos-15 runner proved it by failing with "cannot find type
  SpeechTranscriber" on an @available-only version (TRAP-23). Because that gate compiles the engine
  OUT on macos-15, check.yml gained a macos-26 job that asserts the SDK is 26.x - otherwise a green
  CI would never have built the engine at all (TRAP-24).
  NOT established: the real microphone path (#35) and cold-start model download (#36).
  Gaps: #35, #36.) Volatile results must REPLACE, never append - they duplicate the tail of the last
  finalized result. Wrap `transcriber.results` in a timeout; the stream hangs in the field.

#13 - SPIKE: contextualStrings with SpeechTranscriber - DONE
  (2026-08-22: it does NOTHING. An A/B holding audio, preset, locale and chunking constant and
  differing only in AnalysisContext.contextualStrings[.general] produced byte-identical transcripts
  on 3/3 runs, with none of the three bias words appearing. The recognizer mangled all three
  targets without the bias - "push, text", "and rail a", "Cubanies" - so there was maximum room for
  an effect and there was none. docs/research/01 sec 1.6 predicted this off two REPORTS; it is now
  measured. #9's dictionary stays a post-pass, which is how it was already built, so no shipped code
  changed. docs/verification/task13-contextual-strings.md.)

#14 - FoundationModelsCleanup behind the drift guard - DONE
  blocked-by: #8, #11. Permissive guardrails at construction time; `respond` not `streamResponse`;
  silent fallback to the raw transcript on all nine GenerationError cases.

#15 - Measure and publish real latency numbers - DONE
  (2026-08-22: finalize is the only term the user waits on, because transcription streams while
  they are still speaking. 5 runs each at 2.03s / 9.97s / 46.25s, paced to realtime, through the
  packaged .app: median 49.4 / 120.8 / 205.4 ms. Strongly sub-linear - 23x the audio costs 4.2x the
  finalize, so a paragraph is not meaningfully worse than a sentence. begin is flat at 115-155 ms
  and lands at press. Pasteboard work is 2-3 ms and flat with length; the injector's 120 ms settle
  delay is NOT user-visible, it is waited after the key is posted. The instrument was checked first:
  paced deliver=2173ms vs unpaced 3.1ms on the same 2.03s clip. STILL UNMEASURED: end to end inside
  the app - the only datum is #42's n=1 221 ms, leaving ~170 ms unaccounted for, so AppModel now
  emits releaseToText=<n>ms rather than requiring arithmetic on two log timestamps.
  docs/verification/task15-latency.md.)

## Phase 2 - ship

#16 - Bump platform floor to macOS 26 - DONE
  (2026-08-22: the issue said one line plus MIN_SYSTEM_VERSION; it was four. swift-tools-version had
  to go 6.0 -> 6.2 because .v26 does not exist in PackageDescription 6.0, and BOTH workflows ran on
  macos-15, which cannot resolve a v26 manifest at all - release.yml fires only on a tag, so that
  break would have surfaced at the first release. platform-floor-consistent.sh now gates all four,
  and each disagreement was planted and confirmed detected before the gate was trusted. check-macos26
  folded into check: it existed only because the macos-15 build compiled the engine OUT via
  #if canImport(FoundationModels). That scaffolding is gone with no behaviour change - every gate was
  a whole-file wrap with no #else, and @available(macOS 26, *) is a no-op at a v26 target.
  UnsupportedTranscriptionEngine went with it; its two construction sites were version gates that can
  no longer be reached, and unsupported HARDWARE was never a version question - AppleSpeechEngine
  already throws EngineError.unavailable for it.)

#17 - Sparkle EdDSA keypair + first release - DONE
  (2026-08-23: v0.1.0 published. The keypair half needed NO keypair, and generating one would have
  been actively harmful: Sparkle keeps one key at a single well-known Keychain slot, one was already
  there, and `generate_keys -p` (lookup only) printed a value byte-identical to the SUPublicEDKey
  that /Applications/TermTile.app already ships - so a careless generate_keys here could have broken
  update signing for every installed TermTile user. This entry's own premise, "generate_keys puts
  the private half in the login Keychain", implied one had to be generated and was wrong.
  Verified against the DOWNLOADED artifact rather than the build log: shasum -a 256 -c OK; chain
  Developer ID Application -> Developer ID CA -> Apple Root, team XG9SBNWNXT; stapler validate finds
  the ticket; Gatekeeper accepted, source=Notarized Developer ID; the appcast signature verifies
  against the SUPublicEDKey compiled into the shipped app.
  The certificate was obtained the long way round. The login keychain's password no longer unlocks
  it - the dialog wants the Mac login password and that credential no longer matches - so `security
  export` could not produce a .p12 however many times it was attempted. Routed around rather than
  fought: a fresh key generated locally with openssl, a CSR through developer.apple.com, and a NEW
  Developer ID Application certificate issued against it (G2 Sub-CA, expires 2031-08-24). The
  private half was therefore never in the keychain and needed no export, and the earlier certificate
  is untouched, so TermTile is unaffected. Backup: ~/Downloads/pushtext-signing-backup/ - Apple
  cannot reissue a private key, so if that folder and the GitHub secret are both lost the only
  remedy is another certificate.
  Two defects found on the way: #96, provenance attestation can never work on a user-owned private
  repo and ran AFTER notarization, so the first v0.1.0 run spent a real Apple notary submission and
  died one step before publishing; and #95, release notes describing a build from months ago, whose
  claim-by-claim check also surfaced #94.)

#18 - Context-aware formatting per frontmost app - DONE
  (2026-08-23: WITHDRAWN unbuilt, PR #120 - the one problem it ever named does not occur. Its whole
  specification was PLAN.md's "terminal -> no smart quotes, etc." plus a blocked-by on #14, closed
  long before. Measured: SpeechTranscriber emits STRAIGHT quotes - 7 straight, 0 curly across 80
  real transcripts in history.jsonl, and zero curly quotes, en dashes, em dashes or ellipses in any
  of them. On-device cleanup returns pure ASCII, checked at code-point level rather than by eye
  because the two apostrophes are near-indistinguishable in a terminal. And the receiving app does
  not convert them either: macOS smart-quote substitution is enabled here but applies to TYPED
  input, and did not fire on a pasted control - which was the last mechanism by which a curly quote
  could reach a user's document, since PushText injects by pasteboard. Closed rather than re-scoped
  because nothing in the issue, the backlog or the plan named a second case, and building the
  framework would have meant inventing requirements for it. NOT ruled out: another locale, or a
  future recognizer that formats differently - all 80 transcripts are en-US on one machine.
  Evidence: docs/verification/task18-context-formatting.md.)

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

## Gaps left open by #11

#32 - Format mismatch into SpeechAnalyzer is an uncatchable SIGTRAP, not an error - DONE
  (2026-08-23: PR #37, alongside #12. Corrected first, off the SDK rather than inferred: the
  mismatch is not merely a different RATE. bestAvailableAudioFormat(compatibleWith:) returned
  16000 Hz ch=1 common=3, and AVAudioFormat.h defines 3 as AVAudioPCMFormatInt16, while
  AVAudioEngineCapture emits 48 kHz Float32 - so a resample-only fix would have handed the analyzer
  a format it did not ask for and, by the evidence below, trapped anyway. AppleSpeechEngine
  .beginUtterance now derives the target from bestAvailableAudioFormat and builds AudioFormatConverter
  from it; append cannot bypass the converter; AudioFormatConverterTests asserts sampleRate == 16000
  AND commonFormat == .pcmFormatInt16, both, per that correction. Battle-tested rather than trusted:
  a converter planted to emit SILENCE failed ONLY the signal test - every format assertion still
  passes on a silent converter, so without that test silent and working are indistinguishable - and
  a planted "rates match, nothing to do" shortcut, the exact shape this issue warns about, failed
  only the same-rate test.)
  Original note, blocked-by: none; constraint on #12. Planted deliberately during the #11 spike:
  48 kHz buffers fed
  to an analyzer whose bestAvailableAudioFormat was 16 kHz mono produced EXIT=133 (SIGTRAP) inside
  Speech.SpeechRecognizerWorker.preRunRecognition(), with no throw to catch. AVAudioEngineCapture
  delivers the device's native rate, so the two differ by default - #12 must convert at the boundary
  and assert the format there. TRAP-20.

#33 - Apple Intelligence reports restricted/assetIsNotReady - DONE
  blocked-by: none; GO/NO-GO input for #14 the way #11 was for #12. The crash report from the #11
  spike carried appleIntelligenceStatus state=restricted reasons=[assetIsNotReady]. FoundationModels
  is present in the SDK and compiles; whether SystemLanguageModel.availability returns .available
  here was NOT measured - it was read off a crash report, not called. Probe it before writing #14,
  or the cleanup stage ships untestable.

## Gaps left open by #12

#35 - AppleSpeechEngine has never been driven by the real microphone - DONE
  (2026-08-22: Bobby spoke into the probe. 100 buffers, 239616 frames at 48 kHz = 4.992s delivered,
  transcribed in 0.27s, engine=ok, non-empty text from a human voice. No TCC prompt appeared, so
  the microphone grant survived the macOS 26 upgrade on a path that actually transcribes. The
  conversion boundary held on live hardware audio. Accuracy NOT asserted - that is #15. The
  converter was separately checked as a suspect for poor text and exonerated: chunked per-buffer
  conversion and whole-file conversion returned byte-identical transcripts on identical audio.
  What this did NOT prove moved to #39: the probe collects buffers then feeds them (realtime=false),
  so appending WHILE capture runs has still never executed.)

#36 - First utterance can block on a model download inside beginUtterance - DONE
  (2026-08-23: PR #77. Installation moved to TranscriptionEngine.prepare(), called detached at
  launch; the dictation path now REFUSES instead of downloading - EngineError.modelNotReady ->
  DictationFailure.modelNotReady -> "Preparing model...". Refusing in milliseconds is the point:
  "Transcription failed" sends the user looking for a fault that does not exist when the honest
  answer is that waiting fixes it. prepare() has a protocol default of no-op so no other engine
  implements it, and launch never blocks either. Two injectable seams, neither a convenience: the
  not-installed state CANNOT occur on this machine - AssetInventory exposes reserve/release/status/
  assetInstallationRequest and no uninstall - so without a seam "beginUtterance no longer downloads"
  could only be re-read, never run; and CI supplied the second, since the macos-26 runner has no
  Neural Engine and throws .unavailable before any model check. Still NOT measured, then or now: the
  download's DURATION and the user's view of it, because this machine has been warm since #11.)
  Original note, blocked-by: none. ensureModelInstalled awaits downloadAndInstall on a machine
  where the asset is absent, and push-to-talk means the user is already speaking. The download path
  was OBSERVED during the #11 spike (status supported -> installed inside one run).

#39 - The dictation pipeline is never assembled - the app cannot dictate - DONE
  (2026-08-22: AudioFeed carries capture buffers across the sync-to-async boundary in order via one
  AsyncStream drained by one task; AppModel drives the effects from STATE changes rather than key
  edges, so a duplicate key-down from the tap cannot start a second utterance; the composition root
  builds the tap, capture and injector and surfaces a missing Accessibility grant in the menu
  instead of crashing. Both hazards were planted and caught: Task-per-buffer reordered 200 buffers
  to [0,2,1,3,...] and a bounded buffer dropped 65 of 200 (TRAP-26). Pipeline breaks planted too -
  skipping injection failed 3 tests, dropping audio failed exactly the one asserting buffers reach
  the engine. NOT proven: the real key-to-text loop on hardware, which needs a human (#42).)


#42 - The key-to-text loop has never run on real hardware - DONE
  (2026-08-22: Bobby held Right Option and spoke; text landed in the focused window. Read off the
  app's own log: pressed -> capture started -> recording -> released -> transcript chars=34
  duration=2.43s -> injected chars=34 -> idle. 221 ms from key release to text on screen, the
  project's first real latency figure - #15 still owns proper numbers.
  Getting there took three fixes, and the first two failures were invisible without diagnostics:
  the hardened runtime refuses the microphone without com.apple.security.device.audio-input and
  will not even PROMPT, so the app could never appear in the Microphone list (TRAP-27); .failed had
  no exit so the first error bricked dictation until relaunch (TRAP-28); and the app never requested
  the mic at all, every prior capture having come from terminal-parented probes inheriting the
  terminal's grant (#44).)

## Requested 2026-08-22 after the first working dictation

#46 - Double-press to latch recording, with a HUD that can cancel or commit - DONE
  (2026-08-22: latch/cancel/end modelled in Core; PressPatternRecognizer turns edges into a double
  press with the thresholds as testable parameters (0.4s window, 0.3s tap limit - the tap limit is
  what stops a dictation followed by a quick correction from silently latching); AudioLevelMeter
  drives the waveform from REAL samples, verified by planting a constant 0.5 which the monotonicity
  test caught; DictationHUDPanel is a non-activating NSPanel proven not to take focus - with the HUD
  on screen, frontmost was still iTerm2 and PushText's AXFocusedWindow was `missing value`, which is
  what keeps the synthetic Command-V landing in the user's document. Two races found by the
  integration tests: cancel closed the mic asynchronously, and an in-flight openUtterance reopened
  it for an utterance that had already ended (TRAP-31). Redesigned mid-build on Bobby's direction:
  HORIZONTAL rather than vertical, and hanging from the menu-bar item as a slim dropdown rather than
  floating on screen. The anchor is the real status-item window, found by class name with a
  fallback, because MenuBarExtra does not expose its NSStatusItem and a private class name is not a
  contract. Screenshot-verified under the icon: anchor=1051,1084.)
  blocked-by: none. Supersedes #7, whose non-activating NSPanel mechanics remain the hard part - the
  panel must not take key focus or the injected Command-V lands in the HUD instead of the document.
  Order: interaction model in Core (DONE) -> double-press recogniser (pure, testable: the timing is a
  product decision and must not be buried in an event-tap callback) -> the panel, which needs
  rendered verification -> level metering from the existing capture buffers so the waveform shows
  REAL audio; a decorative animation would move while a dead capture path delivers nothing, which is
  the exact failure AudioProbe exists to catch.

#47 - MacFaceKit is linked but never used - the UI is unstyled SwiftUI - DONE
  (2026-08-22: the menu is now AppIdentityCard + SectionCard + Tokens, matching TermTile so the two
  apps read as one family; the ... overflow carries the same three actions TermTile has - Check for
  Updates via a real Sparkle SPUStandardUpdaterController, Quit, and a destructive Uninstall that
  confirms first and says plainly that macOS keeps the TCC grants because no app can revoke its own.
  The HUD was restyled onto the same tokens - Tokens.field surface, Tokens.line hairline,
  warning-tinted cancel - so it reads as part of the menu rather than a foreign widget.
  Screenshot-verified: menu, overflow dropdown, and HUD during a live hold.)
  blocked-by: none. `grep -rn MacFaceKit Sources/` returns nothing while Package.swift both declares
  and links it, so the app pays the dependency cost and looks like a prototype. Do it with #46 so
  the HUD is built from the same components rather than adding a second visual language.

## Filed on GitHub after this file stopped being the capture surface

Later work went straight to `gh issue create` and to `docs/verification/`, so these two never got a
line here. They are OPEN, and this section exists so the file stops disagreeing with GitHub about
that. The narrative for each lives in the issue.

#24 - Audio capture: the interleaved-stereo branch has never executed - S0
  blocked-by: hardware that does not exist on this machine. AVAudioEngineCapture's sink-node block
  has an else-branch for interleaved multi-channel input that extracts channel 0 sample by sample;
  it requires `buffers.count == 1 && channels > 1`, is written from the AudioBufferList contract
  rather than from observation, and has never run. Measured, not assumed: every input device on this
  machine reports 1 channel, so it cannot be exercised here. The device-change half of the original
  issue turned out to be a confirmed silent data-loss bug and was split out to #70; this is now only
  the coverage gap. TRIGGER: a genuinely multi-channel interleaved input device.

#73 - Grounding rejects inflection changes it cannot tell from invention - S0
  blocked-by: none. Residual of #68, which fixed the numeral false positives and measured the rest.
  Measured in shadow mode over 20 real SpeechTranscriber transcripts x 3 model runs
  (docs/verification/task68-cleanup-shadow-mode.md): after the numeral fix, 4 of 60 runs still
  reject, and one of them is not drift - the model changed "fails" to "fail" for subject-verb
  agreement against a plural subject, which is a grammatical correction rather than invented
  content, and grounding cannot tell them apart because it compares surface tokens. The others ARE
  correct rejections: "faming" -> "failing" is the model guessing at a misrecognition. That
  distinction - inflection of a word that IS present, versus substitution of a word that is not - is
  the whole issue, and closing it needs a stemmer. LOW priority: the fallback is the raw transcript,
  which is already punctuated and capitalised.
