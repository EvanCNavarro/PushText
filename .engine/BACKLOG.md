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

**SO: MARK YOUR ENTRY `DONE` IN THE PR THAT CLOSES THE ISSUE, NOT AFTERWARDS.** The asymmetry above
exists to make that safe - `DONE` here while still open upstream is only a NOTE, and it resolves the
moment the PR merges. Leaving the line `S1` for a PR that closes the issue produces the FAIL
direction on whatever PR comes next, which is a red build for someone else's change.

Recorded 2026-08-25 after doing it twice in one day (#164, then #182). Both times the gate caught it
on the FOLLOWING pull request, which is exactly the delay this instruction removes.

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

#24 - Audio capture: the interleaved-stereo branch has never executed - DONE
  (2026-08-23: the branch was unreachable because it was welded inside a realtime callback, so the
  only way to run it was to own multi-channel hardware. Every input here still measures 1 channel,
  re-measured rather than cited. The decision and the strided copy moved to Core as pure functions
  and are now driven by interleaved stereo and interleaved 5.1 fixtures with no audio device
  involved.
  Extraction exposed a SECOND defect the branch had. "channels == 1 || buffers.count > 1" describes
  layout by inference and is wrong for 4 channels delivered as 2 buffers of 2: that reads as
  non-interleaved, strides by 1, and would interleave two channels into the ring as if they were
  one. Fixed by reading AudioBuffer.mNumberChannels, which states how many channels are packed into
  THAT buffer and is right for all three shapes. The field was measured before being relied on -
  temporary instrumentation on the real capture path printed bufferCount=1 bufferChannels=1
  formatChannels=1 over two runs - and that shows it is FILLED IN, not that it reports interleaving
  correctly, since mono is the only layout available here.
  Five plants, all detected: stride always 1, infer from the format, ignore the stride in the ring,
  off by one channel, ignore the ring's free space. Channel 1 carries the negated frame index in the
  fixtures, so reading the wrong channel shows up in the VALUES rather than only in the counts.
  Real mono path unaffected: 3 runs, buffers=60 frames=144384 dropped=0 contiguous=true exit 0.
  STILL UNOBSERVED and said so: no device here delivers mNumberChannels > 1, so the interleaved path
  has never executed against real audio. It is no longer UNEXECUTABLE, which is what this issue was
  about. Evidence: docs/verification/task24-interleaved-branch.md.)
  blocked-by: hardware that does not exist on this machine. AVAudioEngineCapture's sink-node block
  has an else-branch for interleaved multi-channel input that extracts channel 0 sample by sample;
  it requires `buffers.count == 1 && channels > 1`, is written from the AudioBufferList contract
  rather than from observation, and has never run. Measured, not assumed: every input device on this
  machine reports 1 channel, so it cannot be exercised here. The device-change half of the original
  issue turned out to be a confirmed silent data-loss bug and was split out to #70; this is now only
  the coverage gap. TRIGGER: a genuinely multi-channel interleaved input device.

#124 - AudioProbe's completeness ratio trusts a wall-clock window it does not measure - DONE
  blocked-by: none. Found while re-verifying capture for #24. reportCompleteness divides frames by
  seconds * sampleRate and only fails BELOW 0.85, but RunLoop.main.run(until:) is not bounded to
  `seconds`. Three runs on a build that started Sparkle at launch gave completeness 1.394 / 2.965 /
  0.999 - 2.965 is 8.9 seconds of audio in a nominal 3-second window - and three runs on the fixed
  build gave 1.003 each time. Correlated, cause unverified: confirming it would mean re-running the
  build that puts a Sparkle failure dialog on Bobby's screen. Matters because this is the ONLY guard
  against silent truncation (#70) and it fails only in the low direction, so an inflated ratio hides
  loss.
  (2026-08-23: confirmed by INTERVENING rather than by correlation. A PUSHTEXT_AUDIO_PROBE_STALL knob
  blocks the main run loop, and with STALL=6000 a 3.000s request produced a 6.219s window and a
  2.073 ratio under the old maths. The dangerous direction demonstrated end to end: half the audio
  discarded inside a stalled window scores 0.500 and exits 4 under the measured window, where the
  requested-seconds denominator scores 1.036 and PASSES - the exact failure the guard exists to catch
  sailing through it. Fixed by measuring the window with ContinuousClock and dividing by that; both
  numbers are printed so a stretch is visible rather than folded into the ratio. The arithmetic moved
  to CaptureCompleteness in Core, because the probe and the wrong denominator agreed with each other
  and no amount of running the probe would have shown it. A zero or negative window scores 0 - for a
  truncation guard, failing closed is the only safe direction. The stall knob is PERMANENT, like
  PUSHTEXT_HOTKEY_PROBE_STALL: a guard you cannot make go red on demand is a guard nobody has tested.
  Evidence: docs/verification/task124-completeness-window.md.)

#73 - Grounding rejects inflection changes it cannot tell from invention - DONE
  (2026-08-23: grounding now accepts a token that is another token plus one inflectional ending, and
  the shape of that rule matters. A canonical STEM KEY was written first and was wrong: "building"
  minus -ing is "build" while "build" minus -d is "buil", so two forms of one word landed on
  different keys - a one-pass suffix strip is not consistent across a word's own forms. The real
  model produced exactly that pair and rejected it; reading the code had predicted a match. Replaced
  by a RELATION between the two tokens actually present, which cannot have that defect and makes
  nonsense stems free. Exact match is still tried first, so nothing previously grounded stops being
  grounded, and the matched raw token is still consumed so one raw word cannot ground two.
  The 4-character base floor is measured, not chosen: over /usr/share/dict/words, lowering it to 1
  merges 833 further pairs including an/and, ai/aid, ad/as and ami/amid, which are distinct words. It
  also refuses genuine pairs like act/acting, and that is the trade - a refusal costs the raw
  transcript, a false merge costs text the user never said. 39 of a 40-pair sample of what the
  relation admits are ordinary inflections.
  Real path, both directions: the near-miss is accepted 3/3, and of 11 runs of the guess-prone
  sentence the 5 that actually guessed were all refused, including "famishing". The other 6 returned
  the text unchanged, so the guard was not exercised in them and they are not evidence either way.
  Evidence: docs/verification/task73-inflection-grounding.md.)
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

## Requested 2026-08-24 after 0.2.0 shipped

#128 - Hotkey as a click-to-record field, and "State: Ready" may be noise - DONE
  (2026-08-24: both, from Bobby's screenshots of the shipped build.
  The recorder does NOT reopen #104. That issue rejected TermTile's recorder because it captures
  arbitrary key+modifier CHORDS, and chords would trade away the bare-modifier capability that keeps
  dictation alive under Secure Input. This one accepts only HotkeyBinding.selectable and beeps at
  anything else, so the domain constraint is untouched and only the gesture changed. It cannot reuse
  TermTile's capture code either - a bare modifier produces no keyDown, only flagsChanged - so the
  decision moved into Core as HotkeyBinding.pressed(keyCode:rawModifierFlags:), which is testable
  against integers.
  A defect was designed out rather than shipped: the event tap is global and does not care that a
  settings field has focus, so pressing Right Option to rebind would ALSO have started a dictation.
  The recorder announces capture in both directions and the composition root suspends the tap. A
  real teardown, not a flag - a flag would be read on the tap thread, and the edge it would have to
  drop is the very keypress being recorded.
  "Ready" earned the criticism; deleting the row did not. MenuContent is the ONLY surface in the app
  that renders a DictationFailure - HUDPhase has no failure case - so deleting it would have removed
  the only home for six messages including "Preparing model..." and "Permission needed". Hidden
  while idle instead, with a test driving all eleven non-idle states to prove none lost its message.
  ImageRenderer CANNOT rasterise an NSViewRepresentable - measured, the field came out as the same
  orange placeholder it gives an indeterminate ProgressView - so the snapshot case was removed
  rather than left looking like a render, and PUSHTEXT_MENU_PROBE now hosts the real MenuContent in
  a window for screencapture. Rendering earned its keep immediately: the first capture showed the
  field sitting below its own label, because RecorderLine had copied .firstTextBaseline from its
  siblings and an NSView has no text baseline. Nothing in review would have caught that.
  NOT verified: no human has pressed a key at the recorder. The capture path is driven by
  synthesized NSEvents, which exercise the view's logic but not delivery of a real flagsChanged to a
  first responder inside a MenuBarExtra popover.
  Evidence: docs/verification/task128-hotkey-recorder.md.)

#130 - In-app updates cannot work: the appcast 404s anonymously because the repo is private - DONE
  blocked-by: a decision only Bobby can make. MEASURED 2026-08-24: the feed URL baked into the app
  is stable and correct, and returns 404 to an anonymous client. Control - the SAME asset fetched
  WITH credentials returns the signed XML - so the appcast, its signature, the zip and the checksum
  are all fine; Sparkle simply sends no credentials and a private repo's release assets require
  them. Not caught before because release.yml verified the appcast SIGNATURE the way a client would
  but never the FETCH: v0.2.0 shipped a valid, signed, unreachable feed. A reachability check now
  runs at release time - failing when the repo is public, stating the situation when private - so it
  stops being invisible. The same constraint already disabled provenance attestation in #96 and
  nobody generalised it. Options: make the repo public, host the feed and the archive somewhere
  publicly readable, or accept manual updates and stop offering "Check for Updates".
  (2026-08-24: fixed by option 1 - the repository is now PUBLIC. Bobby: "if others like termtile are
  public then yes proceed logically", and the condition was verified rather than assumed:
  EvanCNavarro/TermTile and 400faces/MacFaceKit are both public. Pre-flight before an irreversible
  flip: 484 blobs across all 82 commits scanned for private keys and tokens, 0 hits, and the SCANNER
  was battle-tested - a planted RSA header plus a ghp_ token was detected and then removed - because
  a green nobody tried to make red is a rumor. No credential-shaped filename was ever committed.
  The whole chain is now anonymously fetchable, not just the feed: appcast 404 -> 200, the archive it
  points at 404 -> 200, the checksum 404 -> 200. A reachable feed pointing at an unreachable zip
  would have failed one step later. The feed carries sparkle:version 80 against the installed 72,
  minimumSystemVersion 26.0 and arm64, all satisfied here, so the update will be offered. An earlier
  grep of mine reported no version fields - it searched for XML attributes where Sparkle writes child
  elements; the feed was always right.
  Two intended side effects: provenance attestation returns on the next release, its #96 guard having
  been written so it would, and the #131 reachability check now fails CLOSED rather than merely
  reporting.
  STILL UNPROVEN: nobody has clicked "Check for Updates". Everything Sparkle needs is reachable and
  well-formed, verified by fetching it as an unauthenticated client - but the install itself,
  including the EdDSA check inside the running app, has not been observed.)

#134 - v0.2.0 crashes on launch: Bundle.module falls back to a build-machine path - DONE
  (2026-08-24: the released app died the moment the menu opened - EXC_BREAKPOINT in
  NSBundle.module's initializer, through Brand.mark -> AppIdentityCard -> MenuContent.body. SwiftPM
  generates Bundle.module as a static let that fatalErrors when it cannot find its bundle, and it
  looks in exactly two places: Bundle.main.bundleURL and an ABSOLUTE BUILD PATH baked in at compile
  time. The shipped binary carried /Users/runner/work/... So EVERY packaged build since the first
  release was broken for anyone who did not compile it themselves, v0.1.0 included; it went
  unnoticed because the only installs were on the machine that built them.
  Isolated by measurement: 0.4.2 without the resource copy exits 133 (the shipped crash), 0.4.3
  without it exits 124 surviving on the fallback icon, and 0.4.3 with it survives, signs strictly and
  shows the real mark. So MacFaceKit 0.4.3 is what stops the crash - it replaces Bundle.module with a
  total lookup, which also resurrects Brand's own fallback, dead code until then because the process
  trapped before the guard could run.
  Placement was measured three ways: at the .app root Bundle.module finds it but codesign --strict
  rejects the app; as a .bundle in Contents/Resources it signs but SwiftPM never looks there and the
  flat bundles are "unrecognized" anyway; only the files themselves in Contents/Resources satisfy
  both. One trap cost an hour - SwiftPM leaves those files read-only, cp preserves it, xattr -cr then
  failed with EACCES and set -e killed the build before it signed, which looked exactly like a
  signing bug and never was.
  WHY THE GUARDS MISSED IT, and the useful lesson: the release workflow's smoke step runs on the
  runner, where the baked path EXISTS. A smoke test that runs on the build machine cannot detect a
  build-machine dependency, by construction. build-app.sh now fails CLOSED if any SwiftPM resource is
  absent from the app, planted and confirmed.
  Verified on the PUBLISHED v0.2.1: downloaded, run on a Mac that never built it, exit 124, menu
  rendered, 0 new crash reports, and no /Users/runner string in the binary at all.)

#136 - The Accessibility notice is a dead-end sentence; TermTile gives it a button - DONE
  (2026-08-24: from Bobby's screenshot of 0.2.1. MenuContent rendered startupFailure as a bare Text -
  a sentence naming a Settings path, no button - sitting directly above PermissionRows that have one.
  Two code paths for "a grant is missing" and only one actionable.
  Read TermTile rather than recalled it: MenuBarContent switches on a three-state AccessibilityState
  and renders MacFaceKit's NoticeCard, with "Allow Accessibility" for a first grant and "Reset & Open
  Settings" for a broken one, the second calling PermissionRepairer before opening the pane. PushText
  already had the three-state probe and row-with-button rendering; what it lacked was the repair
  action and a route from a startup failure into that machinery.
  THIS REVERSES #6, and #6 was wrong. That issue declined a repairer because resetting forces the
  user to re-ADD the app, which is more work than toggling a row already present - true only if
  toggling WORKS. TCC binds a grant to the app's code identity, so after a re-sign the listed row
  belongs to a build that no longer exists and toggling it re-grants the old one. Observed the same
  day: replacing a dev-signed PushText with the Developer ID release left Accessibility asking for a
  grant already given. The old reasoning was checked against the wrong case - a revoked grant, where
  the row is current - and never considered the stale row grantBroken exists for.
  Also: a runtime failure now outranks the probe. The tap failing to arm is DIRECT evidence
  Accessibility is unusable, where AXIsProcessTrusted() is second-hand and can report granted while
  nothing works. It downgrades rather than appends, so a permission the probe already flags is not
  duplicated.
  Four plants caught, including the safety one - dropping the bundle id from tccutil reset, which
  would clear the grant for EVERY app on the machine. A fifth did not land (string mismatch) and is
  not counted.
  NOT SHOWN: no tccutil has been run against a real grant. Every test injects the runner on purpose,
  since a test that shelled out would destroy the developer's own grants - so the reset is verified
  as the right command, correctly scoped, with failures reported, NOT as clearing a real stale row.
  Evidence: docs/verification/task136-permission-fixit-row.md.)

#138 - No update indicator: TermTile marks the icon, the ellipsis and the row - DONE
  (2026-08-24: capability-grep FIRST, and it paid. MacFaceKit already had AttentionDot,
  IconButton(attention:) and an OverflowMenu that lifts the mark from any MenuAction onto the `...`
  button - PushText had simply never passed attention:. Two of the three surfaces were one flag away.
  What genuinely lived only in TermTile: the UpdateAvailability state that decides WHEN, and the
  menu-bar badge that composites the dot INTO one NSImage rather than layering it, because
  MenuBarExtra flattens and tints SwiftUI label overlays so a layered badge disappears. Both are the
  "rule for all apps" half, so both went to MacFaceKit 0.5.0 rather than into PushText.
  checking and failed deliberately do NOT mark: a dot that appears while merely checking teaches the
  user to ignore dots, and a failed check is not the same as being up to date - collapsing them would
  claim currency the app cannot know. The probe is Sparkle's non-presenting
  checkForUpdateInformation(), so a mark can appear without a dialog interrupting anyone.
  Six plants across both repos. One of them found a VACUOUS test of mine: the badge test compared
  plain and badged TIFFs and asserted they differed, which passed on an implementation that drew
  nothing - the badged canvas is wider by the inset, so the bytes differ whatever is painted.
  Rewritten to sample the corner for a warning-coloured pixel, which a resize cannot satisfy.
  SEEN: the `...` button carrying the dot, rendered and looked at. NOT SEEN: the dropdown row's mark
  (needs the popover open) and the menu-bar icon (not in the probe window) - both covered by tests,
  neither looked at in place. Evidence: docs/verification/task138-update-indicator.md.)

#142 - conventional-subjects fails on every push: a push event has no PR title - DONE
  (2026-08-24: master's push CI had been red ALL DAY - 8 of 8 runs - while every pull-request check
  was green, so watching PRs could never have shown it. Each failed in ~12s at "the PR title is
  empty".
  The script distinguished a local run from CI by whether PR_TITLE was SET, with a comment arguing
  that set-but-empty means a broken workflow expression. Sound reasoning, false premise: GitHub's
  env: block ALWAYS defines the variable, so on a push event the pull_request title expression
  evaluates to an empty string and the script read a push as a PR with a blank title.
  Keyed off GITHUB_EVENT_NAME now. The original worry is PRESERVED rather than dropped - an empty
  title on a real pull_request event still fails, because a gate that passes while checking zero
  things reads identically to green. Five cases driven: push+empty passes, pull_request+empty fails,
  pull_request+good passes, pull_request+bad fails, local passes. The commit-subject half still gates
  a push, proven by planting a bad subject on a scratch branch.
  HOW IT HID, and this is the transferable part: I had been polling `gh pr view --json
  statusCheckRollup`, which only ever returns the PULL-REQUEST runs. Push runs are a different set.
  CLAUDE.md already records "pushed 6 times and never once looked"; this is the same failure in a new
  costume - I did look, at the wrong list. It surfaced only because I listed workflow runs WITH
  DURATIONS while chasing something else, and a column of 12-second failures stood out.)

#144 - The Test step intermittently wedges: every suite starts, none completes - DONE
  (2026-08-25: CAUSE FOUND AND FIXED. `NSPasteboard(name:)` in PasteboardMarkersTests had no
  deadline; on a headless runner it blocks in CFPasteboardCreate ->
  _onqueue_CFPasteboardSetupInstance -> dispatch_mach_send_with_result_and_wait_for_reply waiting
  for a `pbs` reply that never comes. One call, ten minutes, whole job dead, ~1 run in 10.
  Bounded in #179 (BoundedWork.run): a hung pasteboard server now fails that suite in seconds,
  naming which pasteboard did not answer. Planted a 600s hang - fails in 5s.
  WHAT ACTUALLY CLOSED IT was instrumentation, not analysis. Three investigations all stopped at
  'started N, completed 0' because a hang produces no output and every instance was cancelled by
  hand first. #165's watchdog samples the process before killing it; it fired on its first real
  wedge and handed over a function name and a line number.
  THE INSTRUCTION ON THIS ISSUE WAS UNFOLLOWABLE FOR THREE DAYS: 'let one run to the job timeout'
  when no timeout was set, so the default was six hours and a human always cancelled first. It
  sounded reasonable, which is why nobody checked it. docs/verification is in the issue thread.)

#164 - No check proves a menu item is wired to the action it names - DONE
  (2026-08-25: filed after the same 'we cannot prove the button is wired' note appeared in two
  separate verification docs. AppActions.menuActions() returns [MenuAction] carrying a title, an
  icon and a closure; everything the closures CALL is covered, and the association between a title
  and its closure is covered by nothing. Pointing Delete History at confirmUninstall(), or Quit at
  the uninstall action, would pass swift test, swiftlint, all 11 .engine/checks and the packaged
  smoke. Two of those mistakes are destructive and one is silent.
  WHY IT IS NOT ALREADY COVERED: the closures call straight into AppKit - NSAlert.runModal(),
  NSWorkspace, NSApplication.terminate - so invoking one in a test either blocks forever or does
  something real. That is the actual problem to solve.
  DELIVERED 2026-08-25 in #181: the pairing is DATA now - MenuItemKind carries title/icon/destructive,
  MenuDispatch.perform is the ONE place a kind meets an effect, and a spy asserts dispatch without
  AppKit. THE MIS-WIRING APPEARED WHILE FIXING IT: naming the requirement `uninstall()` failed to
  compile because AppActions already had a PRIVATE `uninstall()` that trashes the app immediately,
  next to `confirmUninstall()` which asks first - a requirement with that name binds to the
  non-confirming path and the menu item skips its own confirmation. Renamed `beginUninstall()`.
  Five plants; four fired. The fifth exposed a TAUTOLOGY of mine: the icon assertion compared the
  built menu against the same source, so an icon change moved both sides and it could never fail.
  Re-pinned to literals. docs/verification/task164-menu-wiring.md.)

#182 - Globe fires ALONGSIDE macOS dictation instead of replacing it - DONE
  (2026-08-25: Bobby - "with whispr flow it overrides the default dictation ... it should happen
  instead of". MEASURED rather than assumed, and my first hypothesis was wrong: Wispr does NOT write
  AppleFnUsageType (nm -u across its binary and every .node/.dylib shows no FnUsageType symbol, and
  the pref still reads 3 while it runs). Its own config binds keycode 63 as "ptt" through an ordinary
  tap. The only difference was that our tap PASSED THE EVENT ON.
  Our tap was already .defaultTap - the class comment had anticipated exactly this - so consuming it
  is the change. GLOBE ONLY: consuming Right Shift would stop the user typing capitals.
  Proven on the real tap: Globe bound -> consumed=2 with pressed=1 released=1; Right Option bound
  with Globe pressed -> consumed=0.
  DELIVERED in #183: the tap consumes Globe's press AND release, scoped by suppressesSystemAction so
  every other modifier still passes through - consuming Right Shift would stop the user typing
  capitals. consumedCount is exposed because a suppressed event leaves NO other trace by
  construction, so the count is the only way to tell suppression from silence.
  STILL NEEDS A HARDWARE PRESS to confirm it defeats the WindowServer-run Globe action; the probe
  posts a synthetic event. The in-app "Press the Globe key to" notice stays as the fallback.)

#176 - The hotkey recorder refuses the Globe key - DONE
  (2026-08-25: Bobby pressed Globe and it beeped. Nothing was broken in the recorder - `selectable`
  listed five keys and Globe was not one, and the UI never said which keys it took, so a refusal
  read as a dead field. Globe was excluded by a comment claiming a tap 'never enters the event-tap
  chain at all', which fused two separate findings from our OWN docs/research/04: a tap CAN SEE Fn
  via maskSecondaryFn, and what it cannot do is SUPPRESS it. The report's recommendation was to
  offer Fn as an opt-in; 'not the default' had become 'not available'.
  Measured rather than argued, which is the rule that comment inverted: the probe armed on Globe
  reports edge=pressed and edge=released for a real flagsChanged carrying maskSecondaryFn.
  Both sides of every modifier are offered now; Globe is matched by FLAG because Apple Silicon may
  report a keycode other than 63; Globe is NOT the default because non-Apple keyboards emit nothing.
  A notice fires when AppleFnUsageType != 0 - it is 3 (Start Dictation) on this machine. The setting
  is READ, never written: the private SPI that writes it leaves the Globe key permanently dead after
  a kill -9, uninstall included. docs/verification/task176-globe-key.md.
  COST: an instrumented probe run drove the recorder against the REAL defaults and persisted a
  synthetic capture, changing Bobby's hotkey to Right Command. Restored to Right Option and
  verified. The packaged smoke isolates HOME; that ad-hoc run did not.)

#178 - NSPasteboard(name:) in tests can hang forever - DONE
  (2026-08-25: the cause of #144, split out so that issue stays the diagnosis. Fixed in #179.)

#146 - Reset leaves an empty Accessibility list: the app never registers itself - DONE
  (2026-08-24: Bobby opened the pane after pressing Reset and PushText was not in it - twenty other
  apps, nothing to switch on. The Accessibility list contains apps that have REQUESTED the
  permission, and PushText never asked. PermissionAdvice said so and drew the wrong conclusion:
  "no programmatic prompt worth using ... shows a dialog that just sends the user to Settings
  anyway". The prompt is not merely a dialog, it is the REGISTRATION step - and #136's Reset made it
  worse by removing the only row that existed.
  Measured on a throwaway bundle id with no human involved: no row before, prompt, then
  kTCCServiceAccessibility|dev.ecn.apps.pushtext-trustexp|0 - registered, not allowed. Read from the
  TCC database rather than from the Settings UI. The FIRST attempt proved nothing: run from the
  terminal it said trustedBefore=true, because TCC attributes to the responsible process and the
  binary inherited iTerm's grant (#44); launching the packaged app with open(1) gives
  trustedBefore=false and a real prompt.
  resolvePermission is now reset -> register -> open, and the order is asserted: opening the pane
  before registering lands the user somewhere with nothing to do. A first grant registers too (there
  is nothing to reset, but the list is empty without it); a denial does neither, because the user
  answered; the microphone keeps its own prompt. Three plants caught, including the exact defect and
  the wrong order.
  COST, recorded because it was mine: cleaning up two junk TCC rows my own probes created also
  removed the real dev.ecn.apps.pushtext Accessibility grant. The other 36 Accessibility rows and
  the Microphone grant were untouched. Also re-learned that tccutil resolves a bundle id through
  LaunchServices BEFORE touching TCC, so an id whose .app has been deleted cannot be reset at all -
  the cleanup needed the bundles recreated first.)

#148 - The prompt and System Settings open together; the platform expects one then the other - DONE
  (2026-08-24: Bobby saw the macOS dialog and System Settings appear at the same moment. #146 had
  made resolvePermission do reset -> register -> open, so both fired.
  RESEARCHED rather than assumed, two facts that decide the design. First, do not open Settings
  yourself: the prompt already carries an "Open System Settings" button and there is no programmatic
  route past it - "you can only ask" (Apple's AXIsProcessTrustedWithOptions docs; t8r.tech). Second,
  the prompt fires ONCE - after the user answers, Deny included, macOS never shows it again, so from
  then on Settings is the only route (jano.dev; gertrude.app).
  So the button is sequential: first press resets a stale row if there is one, records that we asked,
  and prompts - nothing else. A later press opens Settings, because a prompt-only press would do
  visibly nothing. The flag is PERSISTED, since the once-only behaviour survives relaunch, and it is
  recorded BEFORE prompting so a crash between the two cannot lose it.
  Three plants caught: prompting and opening together (the exact report), prompting forever, and
  never remembering. Four of #146's own tests had to change, and their premise is what changed -
  they asserted reset -> prompt -> open, which is the redundancy being removed.)

#150 - Uninstall leaves the transcripts, the settings and the grants behind - DONE
  (2026-08-24: Bobby asked whether quit and uninstall "work correctly, with removing references".
  Quit is fine. Uninstall trashed the app bundle and stopped. Measured on this machine, what
  survived: ~/Library/Application Support/PushText with 80 DICTATION TRANSCRIPTS and the custom
  dictionary, the preferences plist, Caches, Sparkle's HTTPStorages, and TCC rows for Accessibility
  and Microphone both at auth_value 2. For an app whose pitch is that nothing leaves this machine,
  leaving the transcripts after the user asked for it gone is a privacy defect rather than
  untidiness.
  The alert was also wrong - it said "no app can revoke its own grants", which stopped being true in
  #136 when the bundle-scoped tccutil repairer landed.
  OwnedPaths and Uninstaller ported in shape from TermTile, and the port found a gap TermTile's
  original does not have: PushText keeps its transcripts under the app NAME, not the bundle id, so a
  list derived from the bundle id alone would have missed them and looked complete. Trash rather than
  delete, so a regretted uninstall is recoverable. Absent paths skipped rather than failed. Exact
  literals, never a prefix, so a neighbouring .selftest plist can never be caught. Permissions
  cleared BEFORE the bundle is trashed, because tccutil resolves the id through LaunchServices first
  and a trashed .app makes the reset fail - learned the hard way earlier the same day.
  Four plants caught, including dropping the transcripts from the owned list. Driven on the REAL app
  path through PUSHTEXT_UNINSTALL_PROBE against an injected library root: removed=4 failed=0, files
  gone, all four recoverable in the Trash.
  A defect in MY OWN TESTS surfaced during cleanup: they used the production trash closure and had
  put 70 temp directories in Bobby's real Trash across the day. The closure is injected now, proven
  by the Trash count being identical before and after a run. A test that litters the machine it runs
  on is a test that gets disabled.
  NOT APPLICABLE: PushText registers no login item - no SMAppService anywhere - so unlike TermTile
  there is nothing to deregister. It does not offer launch at login at all, which is a separate gap.)

#152 - Permission rows never clear: a runtime failure is recorded and never removed - DONE
  (2026-08-24: Bobby granted Accessibility, saw the toggle ON, and the menu still showed three NEEDS
  ATTENTION rows. Measured three ways and all three were stale: TCC said Accessibility=2 and
  Microphone=2, and the app's OWN probe said microphone=granted accessibility=granted
  postEvent=granted allGranted=true.
  runtimeFailures was only ever inserted into - one line, AppModel.swift:75 - and nothing removed.
  #136 made a runtime failure outrank the probe, which is right while the failure is CURRENT and
  wrong once the user fixes it, so the launch-time tap failure and microphone refusal became
  permanent for the process lifetime. PermissionAdvisorTests.failureClears() sets runtimeFailures =
  [] directly and passes: it proved clearing WORKS if someone does it, and nobody did - a test
  verifying a capability the app never invokes.
  Clearing on "the probe says granted" alone would have been WORSE than the bug, because the tap
  stays dead until something re-arms it and the menu would report health the app does not have. So
  recovery RETRIES and clears only what comes back working - which also removes the relaunch the old
  copy demanded.
  Four plants, and the third exposed a vacuous test of mine: recoveryIsPerPermission had the second
  permission's probe report needsFirstGrant, so its row appeared from the PROBE whatever recovery
  did, and a planted removeAll() sailed through. Rewritten with both probes granted so the row
  depends on the runtime failure alone; the same plant now fails.
  The extraction to AppModel+Permissions.swift was botched first - it swept in an unrelated
  ModelPreparer block and broke the build - and was reverted to HEAD and redone in one pass rather
  than patched forward.)

#154 - Edit Dictionary cannot open the dictionary: .jsonl has no handler - DONE
  (2026-08-24: Bobby, on the overflow menu - "these dropdown options aren't all built out working
  ... with true editability". Edit Dictionary produced "There is no application set to open the
  document" and stopped.
  Measured rather than guessed: a .jsonl file gets the DYNAMIC UTI dyn.ah62d4rv4ge80y65tr30a because
  macOS does not know the extension, so urlForApplication(toOpen: <the file>) returns NONE - while
  urlForApplication(toOpen: .plainText) returns TextEdit.app on the same machine. The old code called
  NSWorkspace.open on the file itself, so there was nothing to open it with.
  revealHistory() was not broken but was a dead end: it revealed in Finder, the user double-clicked,
  and hit the identical wall. Renamed to Open History File and it opens the transcripts.
  PlainTextOpener opens the file AS PLAIN TEXT and falls back to revealing when no editor resolves -
  the fallback being the part with a right and wrong answer, and the part the tests assert. Verified
  on the real machine: TextEdit.app resolved, file opened, TextEdit running with it.
  Three plants: no fallback (the original bug), always reveal, and resolve-nothing. The third did NOT
  fire, correctly - the tests inject the resolver so they never launch TextEdit, which means the
  production default is not covered by them BY DESIGN. That plant is what drove the real run.)

#156 - The dictionary is a JSONL file handed to TextEdit, not an editor - DONE
  (2026-08-24: Bobby - "what about those things being editable in a popup proper ui". #154 made the
  file OPEN, which is not the same as editable: the user had to know the format, keep the JSON valid,
  and not break the app with a mistyped brace.
  A real editor now - one row per rule, add and delete, saving as you type. A WINDOW rather than a
  popover, and not as a preference: the menu-bar popover dismisses the moment focus moves and a text
  field takes focus, so an editor inside it would close on the first keystroke. TermTile runs its
  uninstall alerts in their own window for the same reason.
  The rules live in a testable model because they have right and wrong answers: a blank row is never
  written; a row with a spoken form but NO written form is never written either, because it would
  rewrite the user's word to nothing and silently delete what they just dictated; whitespace is
  trimmed, since a trailing space stops the rule ever matching; order is preserved, because the file
  is the user's document and CustomDictionary sorts longest-first when it matches anyway. Four
  plants, all caught.
  RENDERING caught two things no test would: Add Entry used LinkButton, the EXTERNAL-LINK affordance,
  which stretched full-width and drew a trailing arrow reading as "this leaves the app"; and the view
  repeated the window's own title. Both found by looking at the screenshot.
  STILL OPEN: the history is read-only and still opens in a text editor. A viewer with search is the
  same shape of work and is not in this change. TRACKED as #161 and CLOSED by it - the note sat here
  as prose for a day, which is exactly how a gap stops being findable.)

#158 - The release smoke never opens the menu, so the v0.2.0 crash class is untested - DONE
  (2026-08-24: test-packaged-app.sh decides whether a build ships, and it drove the audio and hotkey
  probes, checked launch survival and codesigning, and never evaluated MenuContent.body - which is
  exactly where v0.2.0's crash lived. The app launched, survived the full 8-second window, the smoke
  printed OK, and it died on the first click of the menu bar icon.
  PUSHTEXT_MENU_PROBE existed but rendered forever, so no script could use it. Bounded with
  PUSHTEXT_MENU_PROBE_SECONDS, and layoutSubtreeIfNeeded() forces the pass that actually evaluates
  body - constructing the hosting view is not enough, and without the forced layout a trap inside
  body goes unnoticed while the probe reports success.
  Battle-tested both ways: a planted fatalError fails the smoke with exit 133, the clean build
  reports rendered and exited cleanly. The FIRST plant proved nothing - its message contained the
  literal Bundle.module, so the source guard fired first. A gate going red is not evidence until you
  know which gate went red.
  Every defect in the 0.2.x series was found by a person using the app, not by this script.)

  DELETE HISTORY, driven in the same audit and with no issue of its own: clear() removes the FILE
  rather than truncating it, so the next dictation appends to a path that does not exist, and only
  the atomic-write fallback keeps recording alive. Covered now.
  A HYPOTHESIS DIED HERE, recorded so it does not cost a second afternoon: AppActions built its own
  JSONLHistoryStore to delete through, so two NSLocks guarded one file and a delete could be clicked
  mid-dictation. That reads like a torn-file bug. 200 concurrent appends racing a clear, 5 rounds,
  reported ZERO torn lines with or without a shared instance - removeItem unlinks the name while the
  writer holds the inode, so a racing append vanishes rather than tears, and vanishing is what Delete
  means. No fix was made. docs/verification/task158-delete-history.md.)

#161 - History is read-only and opens in a text editor - it needs a viewer - DONE
  (2026-08-24: #154 made the FILE open, which gave the user the FORMAT rather than their content.
  A window with search, readable timestamps and per-transcript copy; read-only, because history is a
  record of what was said and what was typed and an editable record is a worse one. The raw file is
  still one click away inside it.
  Six plants, one per model claim. FIVE FIRED. The sixth did not, and it is the useful one: the
  search-the-encoding test looked for "1970" and "T00:", and a plant searching the ENTIRE record
  sailed through, because neither string appears in a record's description - green against the exact
  regression it was written to catch. Re-needled with "2023", "durationSeconds", "+0000" it fires.
  The test was wrong; the code was already right.
  RENDERING caught four things reading could not, again: a search field over a history with nothing
  in it; "0 dictations" printed directly under "No dictations recorded yet"; two arrows on Open File,
  an arrow glyph in front of the trailing arrow LinkButton already draws; and Open File offered after
  a delete had removed the file it opens. Three are one rule - hasHistory, deliberately NOT "anything
  is visible", because a search that found nothing must keep the field that undoes it.
  docs/verification/task161-history-viewer.md.)

#162 - PushText cannot launch at login - there is no SMAppService anywhere - DONE
  (2026-08-24: recorded since #150 as an aside inside the uninstall entry - "it does not offer launch
  at login at all, which is a separate gap" - and never tracked. A push-to-talk utility that has to be
  started by hand after every reboot is one the user stops reaching for.
  DEPENDENCY: Uninstaller must deregister it in the same change. Today's uninstall is correct ONLY
  because there is nothing to deregister; the moment this lands, the note at line 727 becomes wrong
  and uninstall starts leaving a login item behind.
  DELIVERED 2026-08-25: SMAppService.mainApp behind a GENERAL toggle, read THROUGH to the system
  rather than cached, with three states rather than a Bool - requiresApproval is real and would
  otherwise draw as ON while the app never starts. Uninstall deregisters first; three plants, all
  fire. The dependency was correct.
  ONE PLANT FIRST PROVED NOTHING: removing the do/catch left an orphaned catch, the build failed, and
  a grep for FAILED tests found none - a compile error read as "no test failed".
  docs/verification/task162-launch-at-login.md.)

#199 - No long-form dictation has been run end to end - DONE
  (2026-08-25: #197 raised the ceiling to 1200s on two code READS; the longest capture this app had
  ever produced was 95.3s. Measured now, through PUSHTEXT_TRANSCRIBE_PROBE_FILE with a numbered
  script so truncation would be visible rather than plausible.
  CAPACITY: 2391s (~40 min) unpaced -> 33,640 chars, markers first to last, no gap, exit 0. Twice the
  ceiling with nothing accumulating.
  FIDELITY: 930.6s (15.5 min) with REALTIME=1 -> 13,472 chars, 48 of 48 sections, exit 0.
  THE UNPACED RUN ALONE WOULD HAVE MISLED: finalize was 41,367ms unpaced versus 94.4ms paced. Pushing
  a whole file at once leaves a backlog to chew at the end; paced delivery does the work as audio
  arrives. The false conclusion available from the convenient harness was "a long dictation takes 41
  seconds to finalise", which would have argued for a progress indicator or a lower ceiling. Real
  answer: a 15-minute dictation returns its text in ~94ms on release.
  STILL NOT SHOWN: the 1200s ceiling itself. TranscriptionProbe has zero mentions of CaptureWatchdog,
  so this measures the ENGINE at length and not the timer; the transcribe-rather-discard behaviour is
  proven at 0.2s in AppModelTests and the constant is asserted separately. Synthesised speech, so
  word accuracy is visibly imperfect - irrelevant to a length measurement.
  docs/verification/task199-long-form-measured.md.)

#197 - A dictation past 120s is DISCARDED, not transcribed - DONE
  (2026-08-25: Bobby - "i just recorded for a long time and it seems like it just died out? and i
  lost all of that information i was talking on." Confirmed and it was BY DESIGN: the watchdog fired
  at 120s, transitioned to .failed(.cancelled), and teardown called feed.cancel(token) - nothing
  transcribed, nothing in history, every word gone.
  A TEST ASSERTED THE DATA LOSS. watchdogClosesStuckCapture expected .failed(.cancelled), and a
  second test in AppModelTests did the same, so the behaviour was pinned in place by the suite. Both
  had to be rewritten before the bug could be fixed - which is the tell that it was chosen rather
  than overlooked.
  NOT RECOVERABLE, and checked rather than assumed: audio never touches disk, history.jsonl ends at
  20:26:11 with the 95.3s entry that survived by being UNDER the ceiling, no temp artifacts, nothing
  in the unified log.
  Expiry now TRANSCRIBES from .recording and still cancels from .arming (nothing captured yet).
  Ceiling raised to 1200s after checking what actually constrains length: the ring is a ~2s transport
  window, and TranscriptFinisher returns raw text on every cleanup failure path. Nothing structural
  wanted 120. The transcript card now says it was cut short, because "it just died out" described
  silence rather than a crash.
  Three plants, all caught. docs/verification/task197-watchdog-data-loss.md.
  NOT SHOWN: no twenty-minute dictation has been run end to end; the longest observed is 95s.)

#188 - Silence the Mac's audio output while dictating - DONE
  (2026-08-25: Bobby - "can you have thing deafen ... like to deafen the computer while recording".
  On a laptop the speakers are inches from the microphone, so whatever is playing becomes part of
  what the transcriber is asked to make sense of.
  THE FEATURE IS THREE LINES AND THE HAZARD IS EVERYTHING ELSE: an app that mutes the Mac and is
  killed leaves it silent with no visible cause, which is the same shape as the Globe SPI this repo
  refuses to write (#176) except that WE own the restore. Three defences - restore on EVERY exit
  including cancel, restore the PRIOR state rather than "unmuted", and write the intent to disk
  BEFORE muting so a crash is repaired at the next launch.
  Six plants, five fired. THE SIXTH FOUND A GAP IN THE TESTS rather than the code: reversing the
  write-then-mute order only matters if the process dies in that window, and nothing kills a process
  mid-call, so every assertion held. Fixed by asserting the SEQUENCE - the fake output reads the flag
  at the moment the speaker is muted. Its key is duplicated in the test rather than imported, because
  importing it would make the test agree with whatever the code does (the #164 tautology).
  Default OFF, unlike the cues: silencing someone's audio unasked is a surprise.
  NOT VERIFIED: CoreAudioOutput itself is never exercised - muting the real device in a test would
  silence the developer's Mac and a crashed test would leave it that way. And nobody has measured
  whether muting actually keeps music out of a transcript.
  docs/verification/task188-silence-while-dictating.md.)

#185 - HOME isolation does not isolate preferences - DONE
  (2026-08-25: found while rendering #162's toggle, which changed Bobby's real dictation hotkey - the
  SECOND time in one day, and the first under the isolation meant to prevent it. cfprefsd serves the
  logged-in user's domain regardless of HOME and CFFIXED_USER_HOME: the redirected home received NO
  plist at all while the real domain changed. HOME isolates FILES and never isolated preferences, so
  every probe in this repo had been writing the user's real settings, and test-packaged-app.sh used
  the same ineffective approach.
  PUSHTEXT_DEFAULTS_SUITE names a separate domain; UserDefaultsSettingsStore(suiteName:) already
  existed unused. Proven: seed the suite with 63, run the probe, real domain stays 61 and the suite
  reads 63. The smoke exports a per-run suite and deletes it on exit - measured before=61 after=61.
  The trust latch used UserDefaults.standard directly and was writing real grantLatch keys.)


#202 - The history window is a snapshot, so a dictation made while it is open never appears - DONE
  (2026-08-25: Bobby opened Dictation History, dictated, and nothing arrived - his screenshot read
  "22 dictations" while LAST TRANSCRIPT showed a dictation that was not in the list.
  `HistoryViewerModel` held `private let records`, loaded once. The comment above
  `HistoryViewerWindow.show` had already named the hazard - "a viewer showing a stale copy of a file
  the app is actively appending to is worse than no viewer" - and closed only the REOPEN half of it.
  A second defect the obvious fix would have added: `Row.id` was the index into DISPLAY order, so
  prepending renumbered every row and `TranscriptRow`'s per-row `@State copied` checkmark would jump
  to a different transcript. Ids now count from the oldest record, which does not move.
  THE POLL THAT LOOKED BROKEN AND WAS NOT. First design polled once a second; every model test
  passed and the real path produced two byte-identical screenshots, SHA-256 4a95271546fbcb17 both.
  The timer fired ZERO times while its arm site reported main=true, RunLoop.main,
  kCFRunLoopDefaultMode. The explanation reached for was App Nap and it was WRONG - written into two
  code comments before `sample` showed the main thread parked in [NSAlert runModal] under
  SPUStandardUpdaterController. Sparkle cannot check for updates from an unbundled SPM binary, and a
  modal run loop starves default-mode timers AND the main dispatch queue, so Timer and
  DispatchQueue.main.asyncAfter failed identically. Every render probe in this repo had been
  screenshotting an app whose main thread was blocked; they survived on only ever needing one frame.
  ProbeActivation.isProbeProcess now keeps Sparkle out of any probe. The refresh became a
  NOTIFICATION on its merits - instant, free when idle, no timer alive for a window open for hours -
  not because polling was disproved in production, which it was not.
  Measured on the real path: append THROUGH JSONLHistoryStore inside the app, window redraws, third
  transcript on top, footer 2 dictations -> 3 dictations. The probe fails closed - when the in-app
  append had not happened it printed "verdict is inconclusive, not negative" and exited 1.
  Four planted defects, four caught. The notification test first counted FOUR posts for one append -
  parallel suites, unattributed broadcast - so the post now carries its store.
  docs/verification/task202-history-viewer-live-refresh.md.)

#207 - The history viewer's become-key refresh is wired but never exercised - DONE
  (2026-08-25: #202 shipped two refresh paths and measured one. This measured the other.
  MY OWN FILED DEPENDENCY WAS WRONG. #207 said moving key focus "likely needs cliclick or an
  NSApplication activation hook" - inferred, never checked. The menu probe window uses
  orderFrontRegardless(), which does NOT take key, so the viewer had held key through every earlier
  probe; the app can steal key from itself with an ordinary NSWindow. One read of the probe code.
  AN UNBUNDLED BINARY CANNOT BE TESTED FOR THIS. Against .build/debug/PushText: "MAKEKEY before:
  isKey=false appActive=false / after: isKey=false", no delegate callback - an inactive app cannot
  make a window key and an SPM binary has no bundle to activate. The probe said NOT CONFIRMED, which
  was true of the environment and false about the code, and would have sent someone to fix a working
  delegate. scripts/probe-history-become-key.sh refuses the binary in its header for that reason.
  THE INSTRUMENT WAS WRONG TWICE. A whole-window pixel hash called the control failed because the
  TITLE BAR had dimmed on losing key - content was identical at 2 rows. Then the crop meant to fix
  it, `sips -c 824 1120 --cropOffset 80 0`, exited 0, printed the output path, and returned an image
  still 904px tall; the cropped hashes came back byte-identical to the uncropped ones, which is the
  only reason it was caught. The verdict now reads the model's row count, which is the quantity the
  question is about.
  Measured: 2 rows while unkeyed after an outside edit, 3 once key returned. Control is load-bearing
  - the edit is a raw append, not through JSONLHistoryStore, so nothing is posted.
  Planted: refresh() removed from windowDidBecomeKey -> 2 and 2, RESULT FAILED, control still ok.
  Restored byte-identical. docs/verification/task207-become-key-refresh.md.)

#209 - The update dialog opens behind the menu panel, covering its Install button - DONE
  (2026-08-26: Bobby hit it twice - the Sparkle alert with Install covered, then Dictation History
  behind the same panel. MEASURED: MenuBarExtraWindow level=101, NSStatusBarWindow 25, our windows 0.
  activate() and makeKeyAndOrderFront decide key and front WITHIN a level, so neither could ever have
  fixed it; the panel has to close. Sparkle's own header says the same for background apps: the alert
  is shown "behind other running applications or behind the app's own windows".
  THE FIRST FIX WAS WORSE THAN THE BUG. orderOut() hid the panel and left SwiftUI thinking it was
  open, so the next click on the icon toggled it closed - measured, panel gone at t=6, icon clicked
  at t=9, no panel for the rest of the run. A dead menu-bar icon beats a mis-ordered window. Now it
  clicks the status item, toggling the state SwiftUI already tracks, guarded on the panel being open
  because clicking while closed would OPEN it.
  NEAR-MISS worth keeping: the first probe drove the real mouse to the status item, which on this
  multi-display Mac is at x=-4607. cliclick did not honour the negative coordinate and the click
  landed on the APPLE MENU with Restart highlighted. Escape was sent, nothing was clicked, and the
  approach was dropped - the probe now asks the status button to click itself, in process, with no
  coordinates to get wrong.
  All six presenting actions dismiss the panel, not just the update path.
  scripts/probe-window-layering.sh; docs/verification/task209-window-layering.md.)
#210 - The app icon carries a bottom line that nothing else in the app draws - DONE
  (2026-08-26: the menu-bar SF Symbol `waveform` and the HUD's capsules are bars alone; only the app
  icon had a 602px bar under them, meant as inserted text and reading as an underline. Removed.
  RECENTRING WAS FORCED BY THE REMOVAL: the bars had been balanced against the LINE, not the
  squircle - centred on y=421 where the squircle centres on 512, per the SVG's own comment about the
  97px balance. All five moved down 91px; the mark now spans 252..772 with 188px above and below.
  One source, everything derived: SVG -> AppIcon.png -> AppIcon.icns -> Dock, Finder, Sparkle dialog,
  and the menu panel tile (which resolves applicationIconImage, so no code changed). Verified by
  unpacking the built .icns with iconutil and looking at it.
  THE REAL GAP: no script rendered the SVG to the PNG - the step lived in a comment inside the SVG,
  so an edit without a re-render would ship the old icon silently. scripts/render-icon.sh does it
  now, --check compares the RENDER not bytes, and .engine/checks/icon-render-current.sh gates it.
  Battle-tested both ways; the FIRST plant was bad - a comment after </svg> renders identically and
  correctly did not trip it. docs/verification/task210-icon-single-mark.md.)
#211 - The README describes a Phase 0 scaffold that has not existed for 22 releases - DONE
  (2026-08-26: not ordinary staleness - the central claim was FALSE. "Status: Phase 0 scaffold ...
  Speech recognition is a mock" against TranscriptionEngineFactory.makeDefault() returning
  AppleSpeechEngine; an entire section "Why it doesn't transcribe yet" about an upgrade that happened
  and an Apple bug task11 records as not reproducing; "Fn ... cannot be suppressed" which
  ModifierGate.swift itself calls a misreading (#176); and a flat "no network" where SECURITY.md
  correctly says no network EXCEPT the update check - overclaiming privacy in the direction that
  costs trust.
  It also broke the project's own rule on its front page: RELEASING.md forbids telling a reader what
  does not work, in Bobby's words about the 0.2.0 notes.
  Zero of ten shipped features were mentioned; no install path for an app that ships notarized
  releases; no permissions section; and the macOS 26 requirement appeared nowhere.
  Numbers re-measured, not copied: 46 tests -> 443, ~9,400 research lines -> 10,054, "one field
  today" -> five. Defaults read out of AppSettings.defaults.
  HANDOFF.md marked superseded rather than deleted - it is the only record of several pre-upgrade
  assumptions that turned out wrong. GitHub: ten topics where there were none, homepage set, and the
  description's "no network" softened to match the truth.
  docs/verification/task211-docs-accuracy.md.)

#216 - The menu-bar icon is an SF Symbol that does not match the app icon - DONE
  (2026-08-26: the menu bar drew SF `waveform` - varied wavy strokes, a different logo from the app
  icon's five tiles - and `waveform.circle.fill` when active, a circle where the icon uses a
  squircle. Both replaced with the icon's own geometry scaled: tiles 86 wide on a 129 pitch, heights
  170/350/520/350/170, from AppIconSource.svg.
  INVERSION RATHER THAN A COLOUR because both ship as TEMPLATE images: macOS gets only the alpha and
  tints for light or dark itself, so the app never picks a colour - and "active" therefore cannot BE
  one. The active mark is the same tiles knocked out of a filled squircle, corner ratio 205/896.
  PNG NOT PDF, and the measurement decided it. TermTile ships PDF and vector is better artwork, but
  rsvg's PDF output is NOT deterministic (two renders of an unchanged SVG differ by 122 bytes) and
  sips rasterising a PDF is not either. With no stable comparison a --check could only assert the
  file EXISTS, which passes on a stale asset - the exact divergence render-icon.sh exists to catch.
  rsvg's PNG output is byte-stable, so all three assets use the same real check.
  The badge is composited locally because MacFaceKit.MenuBarBadge takes a symbol NAME with no image
  overload and is a separate pinned package; Tokens still supply the dot so the vocabulary is shared.
  Tests read ALPHA off the raster rather than comparing images: centre opaque when idle and
  transparent when active, and the reverse in the gap between bars. Two marks could differ in every
  byte and both read as bars. Both plants caught.
  NOT VERIFIED: a photo of it in the live menu bar - the probe's status item landed in the hidden
  overflow of Bobby's menu-bar manager. docs/verification/task216-menu-bar-glyph.md.)

#219 - The menu glyph loaded via Bundle.module and would crash every machine but the build one - DONE
  (2026-08-26: #217 loaded the menu-bar artwork with Bundle.module. SwiftPM's accessor looks in two
  places - a bundle beside the app, and an ABSOLUTE PATH INTO THE BUILD DIRECTORY OF THE COMPILING
  MACHINE - and fatalErrors when neither exists. build-app.sh flattens resources into
  Contents/Resources, so a packaged app has no such bundle: it works for whoever built it and traps
  for everyone else. v0.2.0 shipped this once already carrying /Users/runner/work/PushText/...
  MEASURED both ways: the offending .app with its build dir renamed died with Trace/BPT trap: 5,
  exit 133, "could not load resource bundle"; the guarded build stayed alive under identical
  conditions.
  THE GUARD ALREADY EXISTED AND DID NOT RUN WHERE IT MATTERED. test-packaged-app.sh has carried a
  TRAP-4 scan since v0.2.0 and it caught this instantly when pointed at the code
  (MenuBarGlyph.swift:84) - but it needs a BUILT app and the PR gate runs .engine/checks, swift test
  and swiftlint, so #217 went green and merged with the crash in it. Extracted to
  .engine/checks/bundle-module-guarded.sh, run by CI on every PR; test-packaged-app.sh delegates to
  it rather than keeping a copy.
  NO UNIT TEST COULD HAVE CAUGHT IT: 451 passed before and after, because under swift test the DEBUG
  path is the one that works. The defect exists only in a configuration the suite never runs in.
  0.6.5 was never affected - the glyph landed after that tag and 0.6.6 was not cut.
  docs/verification/task219-bundle-module-crash.md.)

#206 - Measure what the Globe key actually does on macOS 26, at the keyboard - DONE
  (DONE means CLOSED NOT PLANNED - the taxonomy has no other closed marker. 2026-08-26: three
  observations needing a human at the keyboard - hold Globe, double-press Globe,
  and a reboot to see whether launch-at-login actually STARTS the app rather than merely registering.
  Bobby's call: "it's not worth the time for reboot etc for now - if something pops up as an error
  then we'll address it."
  CLOSING IS SAFE BECAUSE NOTHING SHIPPED DEPENDS ON THE ANSWER, and that was checked rather than
  assumed. #182 already reworded the Globe notice from "when you press Globe, macOS acts first" -
  which rested on docs/research/04's unmeasured WindowServer claim - to "macOS also uses the Globe
  key for X", which is what System Settings itself says. task182's write-up records the gap in those
  words, so the repo says "unmeasured" rather than asserting either answer. And suppression itself IS
  measured: the tap consumes the Globe flag, with three plants on the policy. What is unmeasured is
  only whether macOS ALSO acts, never whether PushText does.
  REOPENS ON A SYMPTOM, not a schedule: Apple's dictation panel appearing while PushText dictates, or
  PushText not running after a restart with Launch at login on. Neither has been observed.)

#222 - The history file grows without bound, and reading it costs the whole file - DONE
  (2026-08-26: found by building an instrument for Bobby's "what is bloated, what is inefficient, and
  how can we tell?" rather than guessing. MEASURED: load() costs 0.34ms at 23 records, 6.19 at 500,
  25.15 at 5,000, 88.10 at 20,000 - scaling with the FILE while decoded stays pinned at 500, because
  the trim happened in memory and was never written back. changeStamp() is FLAT at 0.07ms throughout,
  so #202's cheap check does exactly what it was built for.
  Fixed by compacting in append() past 512 KB with an atomic write - in the WRITE path, because the
  viewer reaches the store through HistoryReading precisely so it cannot rewrite the file. The
  trigger is a stat, not a read; reading the file on every append to decide would BE the cost.
  THE AFTER-MEASUREMENT NEARLY MEANT NOTHING. Re-running the size table gave identical numbers,
  correctly - it writes files DIRECTLY and never calls append(), so compaction never fires and it
  cannot distinguish fixed from unfixed. Driving the write path instead: after 20,000 real appends
  the file is 289,665 bytes rather than 4,088,890, and load() is 9.93ms rather than 88.10.
  One test had to be rewritten before it meant anything - "keeps the newest records" asserted on
  load(), which has always trimmed in memory, so it passed with no compaction at all. Both plants
  caught. docs/verification/task222-history-growth.md.)

#224 - Memory has no baseline, so no number about it can mean anything - DONE
  (2026-08-26: measured 33 MB footprint, 41.9 MB peak, 18 MB MALLOC_SMALL plus ~4 MB graphics - and
  the point is that the number alone is UNANSWERABLE. 33 MB is meaningful only against a baseline or
  a trend, and neither existed.
  THE OBVIOUS INSTRUMENT LIES: ps RSS said 89.8 MB for the same process, 2.7x over, because RSS counts
  the shared AppKit/SwiftUI pages every app maps. Reporting it would have sent someone optimising
  nothing. `footprint -p` is the honest one.
  test-packaged-app.sh now records footprint on every packaged run - RECORDED, NOT ASSERTED, because
  a threshold needs a baseline this project does not have and a limit picked by feel gets raised the
  first time it fires.
  A PARSE BUG THAT WOULD HAVE SHIPPED SILENTLY: a positional awk produced "footprint=64-bit
  Footprint:" - a value-shaped string that would have sat in every release smoke without ever looking
  wrong. Now splits on the label and validates the shape, falling back to "unavailable".
  Measured: 16 MB fresh vs 33 MB after hours with the menu opened.
  docs/verification/task224-footprint-baseline.md.)

#224 - Launch to menu-bar ready, measured (the third dimension #224 left open) - DONE
  (2026-08-26: the third dimension named in #224's "still not covered". Exec to a clickable status
  item: debug 894/585/570 ms, release 834/569/578 ms - three samples each, first is cold.
  DEBUG AND RELEASE ARE INDISTINGUISHABLE, which is the finding. Release optimises our Swift and
  debug does not, so if our code dominated launch the columns would differ. They do not, placing the
  time in dyld and framework init rather than anything this project wrote. Nothing here to optimise.
  No permanent gate: recording it every run would need a readiness marker in PRODUCTION code, since
  the measurement borrows #209's probe-only status-item poll - real cost for a regression that is
  unlikely and partly covered by the footprint line and the existing liveness poll.
  Does NOT measure login-to-ready, which includes SMAppService's own scheduling - macOS's, not ours.
  docs/verification/task224-launch-to-ready.md.)

#228 - Version the app icon so designs can be compared, and draft a p-mark variant - DONE
  (2026-08-28: Bobby asked for the mark rearranged into a lowercase "p" - stem plus the waveform
  hanging off it - and for the old design kept.
  MY FIRST READING WAS WRONG. I rebuilt it as a stem plus a "bowl" of top-aligned tiles and threw the
  waveform away; rendered against two alternatives it was the best of a bad set, and read as a bar
  chart. His sketch changes ONE thing: column one keeps its top at 427 and runs to 950 instead of
  597, columns two to five untouched. Measured off his image, bars 2-5 matched v1 within a few px.
  WHY 950 NOT 985: the squircle's bottom-left corner (r=205, centre 269,755) puts the boundary at
  y=952 under x=212, so a longer stem is sliced at an angle and reads as a mistake.
  THE MENU BAR WAS A SCALING PROBLEM, NOT A DESCENDER PROBLEM. Scaling the icon into the 18pt box
  shrinks every tile from 2.29pt to 1.95pt - measured, visibly thinner - which is what made the
  earlier attempt look unusable there. Moving the waveform UP 1.2pt instead frees the room the stem
  needs and keeps every tile full width, so the p ships everywhere rather than in the Dock only.
  Verified in ALPHA not by eye: at row 32 of 36 the stem is opaque and the tallest tile transparent.
  Planted a stem shortened to match the others - caught. Chain checked SVG -> PNG -> .icns unpacked
  from the built bundle; all four menu states rendered.
  docs/verification/task228-p-mark.md.)

#231 - The menu-bar mark is 38% taller than TermTile's and reads as oversized - DONE
  (2026-08-28: Bobby saw the two apps side by side in his own menu bar. MEASURED against
  ~/Developer/termtile/Resources/TermTileMenuGlyph.svg rather than his screenshot: TermTile's mark is
  14 wide x 12 tall, tiles 2 wide rx 1 on a pitch of 3; ours was 16 x 16.5 with 2.286 tiles. The
  width was close, the HEIGHT was 38% over, and that is what read as oversized.
  THE GRID WAS NEVER WRONG. Both marks descend from the same five-column icon grid, so at TermTile's
  tile width of 2 our columns land exactly on its pitch of 3 and the mark is exactly 14 wide. Only
  the vertical extent changed - the waveform plus descender scaled by 12/698 to span y 3..15. Column
  one bottoms at 15.00 against the tallest other tile at 11.94, so the descender survives the shrink.
  THE ACTIVE STATE HAD TO SHRINK TOO: a full-box squircle beside a 12-tall idle mark makes listening
  twice the resting weight - the same oversizing moved elsewhere. Now 14x14 inset by 2, mark at 0.7.
  Two plants, two catches, including a NEW assertion that the active glyph's corner is transparent so
  a full-box squircle cannot creep back. App icon untouched - this was menu-bar only.
  docs/verification/task231-glyph-scale.md.)

#234 - The pasteboard suite takes 7 named boards at once and CI wedges on some - DONE
  (2026-08-28: a docs-only PR went red. Three tests in "Pasteboard conceal markers" timed out
  acquiring a named pasteboard, while master ran the IDENTICAL Swift sources green two minutes
  earlier and a rerun of the same commit went green. Same bytes, two answers.
  THE BOUND FROM #179 IS FINE; THE LOAD IS NOT. NSPasteboard(name:) reaches the pasteboard server
  over mach, and on a headless runner that server is intermittently unresponsive - #144. #179 turned
  the ten-minute hang into a ten-second failure and did not change how MANY boards the suite takes:
  one per test, seven, fired concurrently at a serial setup path. Four returned; the other three
  timed out at the same instant, 10.835s.
  Correlation, cause unverified - the wedge does not reproduce on a Mac with a live window server,
  so there is no local red to turn green. The exposure is what is verifiable: one board now, in a
  static let, suite .serialized.
  THE FIRST GUARD WAS VACUOUS AND THE PLANT IS WHAT SHOWED IT. Count acquisitions, assert 1 - it
  PASSED on the broken version, because the counting test ran first and saw only its own. Deleted,
  not shipped. Replaced by .engine/checks/one-test-pasteboard.sh, which counts acquisition SITES and
  has no ordering dependency - and which reported 2 sites on a clean tree until string literals and
  comments were stripped. Four states run: baseline green, planted site red, prose green, restored
  green. docs/verification/task234-one-test-pasteboard.md.
  MERGED as #235. CI ran the new gate (ok - 1 acquisition site) and the suite passed in 0.390s,
  where the failing run had it blocked for ~11s on acquisitions. One healthy-server run, not proof
  the wedge is gone - that only accumulates across future runs.)

#237 - Sparkle sits at 2.9.3 through two upstream security releases, unwatched - DONE
  (2026-08-31: asked for a status check, found nothing open and this. Shipped 2.9.3; upstream 2.9.6
  since 2026-08-17. 2.9.5 hardens delta-patch symlinks, 2.9.6 fixes a privilege escalation and
  rejects pkg installs whose signature failed - both security.
  EXPOSURE IS LOW AND SAYING OTHERWISE WOULD BE AS WRONG AS IGNORING IT: the privesc needs a root
  process and we are not one, 2.9.5 is delta-patch code and our appcast ships a plain zip with no
  deltas, the pkg fix needs a pkg. What remains is the updater being three releases behind.
  NO GATE WAS WRONG; NONE WAS LOOKING. Sparkle is a local binaryTarget with no manifest and no
  lockfile, so Dependabot cannot see it and its `swift` ecosystem would not change that.
  THREE MORE DEFECTS FOUND WHILE CONFIRMING IT: pinned twice in two files with nothing tying them
  together (framework vs the generate_appcast CLI that SIGNS the appcast); no checksum on the
  download, so the version was pinned and the bytes were not; and `[ -d "$DEST" ] && exit 0`, so the
  bump would have taken in CI and silently not on this machine.
  TWO MORE IN MY OWN FIX, BOTH FOUND BY PLANTING. The first version deleted the old framework before
  downloading the new one - a bad digest printed the right refusal and left the machine with NO
  Sparkle; restructured to verify first, replace last. And the new gate exited 1 with NO OUTPUT on
  the pre-change tree, because set -e killed it at a non-matching grep before the explaining branch.
  Only running it against the PRE-change baseline shows that.
  Gate battle-tested over five states; an earlier run returned 126 on all five (copy not executable)
  and the three RED rows "passed" - only the GREEN rows failing exposed the broken harness.
  Real path driven: dist/PushText.app launches with 2.9.6 embedded, alive 8/8, tap armed, audio
  verified. NOT proven: an end-to-end Sparkle update install under 2.9.6, which only a real user
  taking a real update executes. docs/verification/task237-sparkle-2-9-6.md.
  MERGED as #238; CI ran the new gate green. Shipped in v0.6.10.
  PROCESS NOTE: this entry was written S1 pre-merge and needed a follow-up commit, for the second
  time in one session. Unnecessary - backlog-matches-github.sh deliberately PASSES the 'marked DONE,
  still open' direction precisely so a PR can mark its own line DONE. Write DONE in the PR.)
