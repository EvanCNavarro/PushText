# PushText project traps

Project-local traps discovered during cycles. When a trap proves universal (recurs across
>=2 independent stacks), PROMOTE it up to the base library at
`~/.claude/skills/locomotion/reference/traps-index.md` and leave a pointer here.

Traps marked INHERITED were not discovered here — they were carried in from
`docs/research/05-termtile-blueprint.md` before they could bite. They are recorded because the
research that found them is not read on every cycle, and the trap is.

### TRAP-1: swift-testing's #expect cannot wrap a mutating call
- what happened: `#expect(machine.apply(.hotkeyPressed))` failed to compile with
  "cannot use mutating member on immutable value: '$0' is immutable". The `#expect` macro expands
  into `Testing.__checkFunctionCall(subject.self, calling: { $0.apply($1) }, ...)`, and `$0` is a
  `let` binding, so any `mutating` method on a value type is rejected.
- warning: apply the mutation to a local first and assert the RESULT
  (`let changed = machine.apply(...)`, then `#expect(changed)`). The error text names the macro
  expansion rather than your line, so it reads like a compiler bug on first encounter.

### TRAP-2: a file-level `///` block is an orphaned doc comment and fails swiftlint --strict
- what happened: `Ports.swift` opened with a `///` block explaining the whole file before the first
  `import`. `swiftlint --strict` reported `orphaned_doc_comment` and exited non-zero — a doc comment
  must attach to a declaration. `swift build` was perfectly happy, so the failure only appeared at
  the lint gate.
- warning: file-header prose uses `//`, never `///`. Reserve `///` for the declaration directly
  beneath it. The check is not run by `swift build`, so a clean build proves nothing about it.

### TRAP-3 (INHERITED): ad-hoc signing silently resets every TCC grant
- what happened: not yet, here. Ad-hoc signing (`codesign -s -`) produces a fresh cdhash on every
  build, and TCC binds an unsigned app's grants to that hash — so each rebuild revokes every
  permission without any error, prompt, or log.
- warning: run `scripts/setup-dev-signing.sh` ONCE before granting anything. With Microphone,
  Accessibility and PostEvent all in play, forgetting costs three re-approvals per build.
  `build-app.sh` prints a WARNING when it falls back to ad-hoc.

### TRAP-4 (INHERITED): Bundle.module outside `#if DEBUG` crashes every shipped build
- what happened: not yet, here. `Bundle.module`'s generated accessor bakes in an ABSOLUTE `.build`
  path, which exists on the build machine and nowhere else — in CI that is `/Users/runner/...`.
- warning: resolve packaged resources from `Bundle.main`. `scripts/test-packaged-app.sh` carries an
  awk guard that is `#if DEBUG`-nesting-aware; do not weaken it to a plain grep.

### TRAP-5: a bare curl against rdap.org returns 302 and tells you nothing
- what happened: checking domain availability with
  `curl -s -o /dev/null -w '%{http_code}' https://rdap.org/domain/<d>` returned `302` for every
  domain — registered and unregistered alike — because rdap.org redirects to the authoritative
  registry. Read literally, every domain looked identical.
- warning: use `curl -sL` and read the FINAL status: 404 = unregistered, 200 = registered. More
  generally, any status-code probe against a redirector is measuring the redirector.

### TRAP-6: silencing a build script's stderr turns a failed build into a stale-binary "pass"
- what happened: ran `./scripts/build-app.sh >/dev/null 2>&1 && echo built` after adding a file that
  did not compile (missing `import CoreGraphics`). The build failed, `&&` skipped the echo, and the
  next command happily executed the PREVIOUS bundle still sitting in dist/. The probe then printed
  the OLD code path's output, which looked like a plausible negative result rather than a stale run.
- warning: never send a build script's stderr to /dev/null. Capture the app path from stdout
  (`APP=$(./scripts/build-app.sh 2>/dev/null | tail -1)`) and let stderr through, or check the exit
  code explicitly. A stale binary produces output that is internally consistent and entirely wrong.

### TRAP-7: a declared test target with an EMPTY directory builds locally and fails every fresh clone
- what happened: Package.swift declared `PushTextTests` while `Tests/PushTextTests/` held no files.
  Git does not track empty directories, so the directory existed on the dev machine and nowhere else.
  Every local `swift build`/`swift test` passed; CI failed on the first run with "Source files for
  target PushTextTests should be located under 'Tests/PushTextTests'".
- warning: a declared target needs a COMMITTED file, not a directory. Before trusting a green local
  build, reproduce the way CI sees it: `git clone` to a temp dir and build there. `git ls-files
  Tests/` shows what a fresh clone will actually get.

### TRAP-8: a stalled LISTEN-ONLY event tap is never disabled by the OS
- what happened: tried to exercise the tap-re-arm branch by stalling the callback 2.0s on a
  `.listenOnly` tap, chosen so a slow callback could not delay the user's real input. reEnables
  stayed 0. Nothing waits on a listen-only tap, so there is no timeout to breach.
- warning: `kCGEventTapDisabledByTimeout` is only reachable on a `.defaultTap`. Testing it therefore
  costs a real, brief, system-wide input stall - there is no safe shortcut. Measured: `.defaultTap`
  with a 1.5s stall produces reEnables=1.

### TRAP-9: a stalled defaultTap drops the key-up, and macOS's OWN flag state stays latched
- what happened: fault injection (1.5s stall, `.defaultTap`) lost the key-release in 6 of 6 runs
  (`pressed=1 released=0`), leaving ModifierGate latched down - microphone open. The first write-up
  of this trap claimed the cause was the OS DISABLING the tap and dropping events in flight, based on
  a single run showing `reEnables=1`. Re-sampled: 0 of 6 reproduced it, then 2 of 5. The disable is
  intermittent; the dropped release is not.
- the real mechanism, traced: `CGEventSource.flagsState(.combinedSessionState)` keeps reporting
  `live=0x20080040` - the right-Option bit still SET - after the up event was dropped. A
  `.defaultTap` sits AHEAD of the system's own event processing, so swallowing the key-up prevents
  macOS itself from updating modifier state. The event stream and the live flag state are then both
  wrong, in agreement.
- warning: every state-based recovery is blind here. A 250ms poll of `flagsState` was built, measured
  across 5 runs, shown to change nothing, and REMOVED - recovery correlated only with `reEnables=1`,
  never with the poll. The only defence that works is elapsed time: `AppModel.maximumCaptureDuration`
  force-closes the capture via `DictationMachine.watchdogExpired`, which depends on no flag state at
  all. Resynchronising after a tap re-arm is still kept - it is correct for the intermittent disable
  case - but it is not the primary protection.

### TRAP-10: read the FIRST compiler error, not the last
- what happened: a test file failed with three "cannot infer contextual base in reference to member"
  errors on `.pressed` / `.transcribing`. Read from `tail`, they suggested the enums were somehow
  not in scope and sent me looking at imports of the wrong modules. The FIRST error, further up, was
  `cannot find type 'TimeInterval' in scope` - a missing `import Foundation`. Everything else
  cascaded from it.
- warning: `swift test 2>&1 | tail` shows the LAST errors, which in Swift are usually cascade
  damage. Use `grep -E "error:" | head` first. The same applies to reading a failing test suite:
  the first failure is the cause, the rest are often its shadow.

### TRAP-11: a counter is not proof of recovery - assert the STATE it was supposed to restore
- what happened: the tap-recovery gate was nearly written as `reEnables >= 1`. Planting a no-op
  re-arm (increment the counter, never call `CGEvent.tapEnable(enable:true)`) still printed
  `reEnables=1` while the tap stayed dead - `enabled=false`. The counter records that the branch RAN,
  which is a different claim from the branch WORKING.
- warning: assert the post-condition, not the attempt. Here that is `isTapEnabled == true`. The
  general form: any "we handled it" counter passes on a handler that does nothing.

### TRAP-12: before building recovery machinery, check whether the existing path already fires
- what happened: the OS-triggered tap disable looked uncontrollable (roughly 2 of 11 stall runs,
  0 of 5 with a 12-event burst), so a `tapIsEnabled` health-poll timer was designed to catch a
  disable without relying on the notification event. The red-first run - fault injection with NO
  poll - showed the monitor recovering 3/3 already: disabling your own tap makes the OS deliver
  `kCGEventTapDisabledByUserInput` to your callback.
- warning: "the event might not arrive" was an assumption, and the poll would have been permanent
  complexity guarding a case that has never been observed. Run the disproof BEFORE building the
  workaround - the missing piece was a TRIGGER for the existing branch, not a second mechanism.

### TRAP-13: `swift test --filter` matches the FUNCTION name, and a miss reports "0 tests passed"
- what happened: re-sampling a flaky test with `--filter "Concurrent producer"` (its display name)
  printed `Test run with 0 tests passed` five times. Read quickly that is five greens; it is five
  runs of nothing. The filter matches the Swift function identifier
  (`concurrentProducerConsumer`), not the `@Test("...")` string.
- warning: a filtered run must report a NON-ZERO test count or it proved nothing. This is the
  vacuous-green shape in miniature: absence and success look identical in the output.

### TRAP-14: openssl-generated PKCS#12 will not import into the macOS keychain by default
- what happened: `scripts/setup-dev-signing.sh`, inherited from TermTile, died on
  `security: SecKeychainItemImport: MAC verification failed during PKCS12 import (wrong password?)`.
  Measured on OpenSSL 3.6.3: the default (AES-256-CBC keys, SHA-256 MAC) fails, and `-legacy` also
  fails because it uses RC2 for the certificate bag, which modern macOS rejects outright.
- warning: export with 3DES for BOTH bags and a SHA-1 MAC, and use a NON-EMPTY password - an empty
  one fails independently of the algorithms:
  `-keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 -passout pass:<something>`.

### TRAP-15: `security find-identity -v` hides a self-signed identity that codesign accepts
- what happened: after the import above finally succeeded, the script still reported failure. `-v`
  lists only TRUSTED identities; a self-signed cert shows as `CSSMERR_TP_NOT_TRUSTED` and is filtered
  out. codesign signs with it perfectly well - measured, `Authority=PushText Dev Signing`, exit 0.
  `build-app.sh` carried the same `-v` in its auto-detection, so it had been silently falling back to
  ad-hoc signing and resetting every TCC grant on every build.
- warning: drop the `-v` when detecting a local dev identity, and verify the real post-condition by
  actually signing a scratch file. Presence in a keychain is not proof that codesign will accept it.

### TRAP-16: a ring buffer cannot know whether a short write is a LOSS
- what happened: `AudioRingBuffer.write` counted the unwritten remainder as dropped. A test producer
  that RETRIES then reported 320 dropped frames on a run where every frame was delivered intact -
  and it was intermittent, so it looked like flakiness rather than a semantic bug.
- warning: a short write means "the ring was full", nothing more. Whether those frames are lost
  depends on whether the caller can retry, which only the caller knows - on the audio thread it
  cannot, in a loop it can. Return the count; let the caller call `recordDropped`.

### TRAP-17: a test COUNT written into prose goes stale the moment the suite changes
- what happened: the AudioRingBuffer suite was 8 tests when the memory-ordering plant was measured.
  Fixing the drop semantics added `callerReportsLoss`, making it 9 - and the "all 8 passed" claim
  survived into the source comment, the verification doc and the closing report. The `evidence-check`
  Stop hook caught it. The tests HAD run; the code changed underneath them and the old number was
  quoted, which is the exact defect that hook exists for.
- warning: when a claim depends on a count, re-run and re-read it in the same turn you write it -
  including counts already committed to a doc or a comment, because those are the ones nobody
  re-checks. Better still, phrase a durable claim so it does not carry a count at all ("the suite
  passes") and keep the number only where it is freshly measured.

### TRAP-18: restoring the clipboard too early pastes the OLD contents, silently
- what happened: a pasteboard-based injector must wait after sending Command-V before restoring the
  user's clipboard, because the target app reads the pasteboard asynchronously when it processes the
  key event. Planting `pasteSettleDelay = 0.0` made TextEdit receive `PUSHTEXT-SENTINEL-A` - the
  restored old clipboard - instead of the injected text. Nothing errors; the wrong text just lands.
- warning: the delay is a RACE, not a guarantee, and there is no observable "target has read it"
  signal. Never tune it down on the grounds that it "seems to work"; the failure is invisible to the
  injector and only visible in the destination app. Tracked as #27.

### TRAP-19: a blocked compound command runs NONE of its parts, including the harmless ones
- what happened: one command both wrote `docs/verification/task5-injection.md` (heredoc) and filed a
  GitHub issue. The `search-before-file-check` PreToolUse hook blocked it for the issue half - and a
  PreToolUse block prevents the WHOLE command, so the doc was never written. The citation to it had
  already been drafted, and shipped in BACKLOG.md, the commit message and the PR body, pointing at
  a file that did not exist.
- warning: never bundle a file write with a remote/gated action in one command; the gate cannot
  block half of it. And after any blocked command, re-check what you assumed it had done - the block
  message names the offending part, not the collateral. Caught only by reading the merge diff and
  noticing the file absent. `.engine/checks/cited-docs-exist.sh` now fails closed on it.

### TRAP-20: a wrong audio format into SpeechAnalyzer is a SIGTRAP, not a catchable error
- what happened: the #11 spike planted a format mismatch on purpose - 48 kHz buffers fed to an
  analyzer whose `bestAvailableAudioFormat` was 16 kHz mono. It did not throw and it did not
  degrade. The process died with `EXIT=133` (SIGTRAP), trapping inside Apple's own
  `Speech.SpeechRecognizerWorker.preRunRecognition()`. A separate planted failure had already
  proven the spike's `catch` reports thrown errors correctly, so this is genuinely uncatchable
  rather than a hole in the harness.
- warning: `AVAudioEngineCapture` delivers the device's native rate and the analyzer picks its own;
  they differ by default on this machine. Convert at the boundary and assert the format there, so a
  mismatch fails a test instead of killing a user's dictation. You cannot assert "did not crash"
  in-process - the assertion has to be on the converted format. Tracked as #32.

### TRAP-21: `installedLocales` says installed while `status(forModules:)` says otherwise
- what happened: `SpeechTranscriber.installedLocales` listed `en_US` among nine installed English
  locales, so the model looked ready. `AssetInventory.status(forModules:)` for the actual
  transcriber returned `.supported`, and an explicit `assetInstallationRequest(supporting:)` +
  `downloadAndInstall()` was still required before the first transcription would run.
- warning: the locale list and the module status answer different questions. Gate readiness on
  `status(forModules:)` with the real module instance. Had the spike trusted the locale list, the
  install-time failure would have surfaced from deep inside the analyzer and read exactly like the
  FB22149971 streaming bug it was there to test for - a false NO-GO on the whole architecture.

### TRAP-22: `AssetInventory.reserve(locale:)` returns false while succeeding
- what happened: `reserve(locale:)` returned `false`, and reading `AssetInventory.reservedLocales`
  back on the very next line showed `["en_US"]`. The reservation had taken effect.
- warning: do not branch on that Bool. Read `reservedLocales` back and assert the post-condition -
  the same shape as TRAP-11 (assert the post-condition, not the attempt).

### TRAP-23: `@available(macOS 26, *)` does not make a file compile against an older SDK
- what happened: AppleSpeechEngine was annotated `@available(macOS 26, *)` and built green locally
  on Xcode 26.6. CI, which runs `macos-15`, failed with `cannot find type 'SpeechTranscriber' in
  scope`. The two annotations answer different questions: `@available` gates the OS the binary RUNS
  on, `#if canImport(...)` gates the SDK it is BUILT against. SpeechAnalyzer ships with Xcode, not
  with macOS, so on the 15 SDK the symbols are simply absent and no availability annotation can
  help. Package.swift had prescribed `#if canImport(FoundationModels)` from commit one; the comment
  was read during this work and not applied.
- warning: any macOS 26 API needs BOTH gates. And battle-test the SDK gate rather than trusting it:
  temporarily point the condition at a framework that does not exist, build, and confirm the
  fallback branch compiles. Doing that here immediately caught a second defect the first fix had
  introduced - PushTextApp still called the now-gated TranscriptionProbe unconditionally, which
  would have produced a second red CI run.

### TRAP-24: a compile-time gate makes absent code look like passing code
- what happened: `#if canImport(FoundationModels)` fixed the macos-15 CI failure by compiling
  AppleSpeechEngine OUT of that job entirely. CI then goes green while never building the most
  consequential file in the repo - and a green build with the engine excluded is indistinguishable
  from a green build with the engine compiled.
- warning: when a gate excludes code from a job, add a job where the gate is OPEN, and assert the
  condition that opens it. `.github/workflows/check.yml` now runs a `macos-26` job that fails if
  `xcrun --show-sdk-version` is not 26.x, so "the engine compiled" cannot silently become "the
  engine was skipped". Same shape as the zero-checks-vs-all-green failure: absence and success must
  not render identically.

### TRAP-25: a probe with its activation variable lost launches the UI and looks like a hang
- what happened: a microphone verification run was launched as a single line that the terminal
  WRAPPED, splitting it in two. A bare `NAME=value` on its own line is a shell assignment and is
  NOT exported, so `PUSHTEXT_TRANSCRIBE_PROBE=1` never reached the process while
  `PUSHTEXT_TRANSCRIBE_PROBE_SECONDS=6` did - it was a prefix assignment on the actual command.
  `isRequested` was false, the app launched its normal menu-bar UI, and it sat in the run loop
  printing nothing. Diagnosed only by reading the running process's environment (`ps eww`) and its
  stack (`sample`, which showed NSApplicationMain rather than the probe).
- warning: every behaviour here was correct, and the result was still indistinguishable from a slow
  or hung probe - the third instance in one session of absence rendering identically to success
  (see TRAP-24, and the zero-checks-vs-all-green case). `ProbeActivation.enforceOrExit()` now exits
  78 with the cause when any probe's tuning variables are set without its activation variable. The
  map of activation-to-companions is EXPLICIT, not prefix-derived: the injection probe's companions
  are named PUSHTEXT_INJECT_TEXT rather than PUSHTEXT_INJECT_PROBE_TEXT, so a prefix rule would
  have covered three probes of four while looking complete.

### TRAP-26: a Task per callback does not preserve order across the sync-to-async boundary
- what happened: `AudioCapture.start(onBuffer:)` delivers on a serial drain queue - synchronous -
  while `TranscriptionEngine.append` is async on an actor. The obvious bridge, `Task { await
  engine.append(buffer) }` per callback, was written deliberately first and measured: 200 buffers
  arrived as `[0, 2, 1, 3, ... 34, 36, 37, 35 ...]`. Ordering is a property that exists only DURING
  the operation and leaves no trace in the end state, so a test that checks the result afterwards
  cannot see it - the assertion had to race it, with a suspension point inside the spy's `append`
  and enough buffers to make interleaving certain rather than lucky.
- warning: `AnalyzerInput.bufferStartTime` must be monotonic, and non-monotonic timestamps are one
  of the three suspected causes of FB22149971 - so this defect would have shown up as the streaming
  bug we spiked to rule out, and would have been blamed on Apple. `AudioFeed` uses one AsyncStream
  drained by exactly one task; order becomes a property of the single consumer instead of the
  scheduler. Its buffering is `.unbounded` for the same class of reason: planting
  `.bufferingNewest(10)` silently dropped 65 of 200 buffers, and dropped buffers in dictation are
  dropped words - a short transcript reads as bad recognition, not as a broken pipeline.

### TRAP-27: the hardened runtime silently refuses the microphone without an explicit entitlement
- what happened: the packaged app could never record. `AVCaptureDevice.requestAccess` returned false
  in 5 ms without showing a prompt, status went notDetermined -> denied, and PushText never appeared
  in System Settings > Privacy & Security > Microphone. Two hypotheses were wrong before the log
  settled it - TCC responsibility inherited from the launching terminal, and the request being made
  too early in `App.init()`. `tccd` states the real cause verbatim:
  "Prompting policy for hardened runtime; service: kTCCServiceMicrophone requires entitlement
  com.apple.security.device.audio-input but it is missing". `build-app.sh` signs with
  `--options runtime` always, but only wrote an entitlements file when library validation was being
  disabled, and that file never carried the audio entitlement.
- warning: this failure mode is worse than a denial. TCC does not merely refuse access, it refuses to
  PROMPT - and Microphone, unlike Accessibility, cannot be granted manually in System Settings, so
  the app can never appear in that list and the user has nothing to click. The app is permanently
  mute with no visible cause. Any hardened-runtime capability needs its entitlement present at
  signing time; check the tccd log rather than guessing, because the app-side API just returns
  false. Entitlements are now written unconditionally.

### TRAP-28: `.failed` with no way out turns one bad utterance into a dead app
- what happened: the first real key press failed with `permissionDenied`, and every subsequent press
  logged `hotkey edge=pressed` with NO state change, because `DictationMachine` had no transition
  out of `.failed`. Bobby reported it as "I don't think it works" - which was right, but the cause
  was that it had stopped working, not that it never started. Diagnosis was only possible because
  the app had just gained os_log diagnostics; before that, a working hotkey and a dead one produced
  identical evidence (nothing).
- warning: a terminal state needs an exit or it is a trap for the user, not just for the code. A key
  that silently stops working is worse than one that fails every time, because the user cannot tell
  which state they are in. `(.failed, .hotkeyPressed) -> .arming` now retries. And: a menu-bar app
  with no console, no window and no HUD (#7) is undiagnosable from the outside - diagnostics are not
  a nicety there, they are the only observability that exists.

### TRAP-29: a boundary test placed outside the boundary passes on the broken version
- what happened: `PressPatternRecognizer` rejects a backwards timestamp with `time >= lastTap`
  rather than `abs(...)`, so a wall clock stepping back cannot fake a double press. The test for it
  stepped back 1.05s against a 0.4s window - outside the window in EITHER direction - so planting
  the `abs()` version left the suite green. The test asserted nothing about the guard it existed to
  protect. Stepping back only 0.15s, inside the window, makes the plant fail immediately.
- warning: for any test of a directional or bounded rule, put the input where the two
  implementations DISAGREE, not merely where the correct one succeeds. The generic form of the
  question is the one worth asking before writing the assertion: what would still be true if the
  property were absent? Here, everything - which is why only the plant exposed it. A boundary test
  that never approaches the boundary is decoration.

### TRAP-30: asserting an intermediate state of an async pipeline is a coin flip
- what happened: "A capture that ends normally is never force-closed" asserted
  `state == .transcribing` after a 400 ms sleep. `MockTranscriptionEngine`'s default latency is also
  400 ms, so once #39 wired the pipeline the state legitimately advanced to cleaning, injecting or
  idle in that window. It passed locally and failed on CI - a genuine race, not a flake to retry,
  and `.transcribing` was never the property the test was about.
- warning: assert the INVARIANT, not the position along the way. Here that is "the watchdog did not
  force-close a normal capture" and "the watchdog was disarmed", both of which hold no matter how
  far the pipeline has advanced. Two plants were needed to establish that the new assertions still
  bite: firing the timer early did NOT fail them, because releasing the key legitimately cancels the
  watchdog first - the plant did not create the failure condition. Removing the disarm did fail
  them. A plant that does not reproduce the defect proves nothing about the test, and stopping at
  the first plant would have left a false sense of coverage.

### TRAP-31: an async start finishing after its utterance ended reopens the microphone
- what happened: `openUtterance` awaits the engine before starting capture. A quick tap goes
  arming -> idle in that window, and a cancel can land at any moment - so the in-flight task then
  opened the microphone for an utterance that no longer existed, and its capture handler clobbered
  the NEXT utterance. Surfaced as a latch test where the second utterance never produced text; the
  visible symptom was nothing to do with the cause.
- warning: any `await` between "decide to start" and "actually start" needs a re-check of the state
  it was started for. `openUtterance` now re-reads `machine.state == .arming` after the await and
  abandons otherwise. Same shape as the cancel path: `capture?.stop()` is called SYNCHRONOUSLY on
  cancel and failure rather than inside the async teardown, because a microphone left open is the
  worst outcome this app has, and "it closes a moment later, once a Task is scheduled" is not
  closing it.

### TRAP-32: Text Input Source calls TRAP off the main thread, they do not fail
- what happened: `PasteboardTextInjector.pasteKeyCode()` uses `TISCopyCurrentKeyboardLayoutInputSource`
  and `TISGetInputSourceProperty` to resolve the paste keycode. `TextInjector.inject` is not
  main-actor isolated, so `await injector.inject(text)` from AppModel runs on the cooperative pool -
  and `TSMGetInputSourceProperty` asserts its dispatch queue. The app died mid-dictation with
  SIGTRAP: `_dispatch_assert_queue_fail <- TSMGetInputSourceProperty <- pasteKeyCode()`. It had
  worked earlier in the same session, which is what made it read as "crashes if I record too long"
  rather than as a threading bug.
- warning: mark such functions `@MainActor` so the COMPILER enforces the hop rather than a comment.
  Doing that here immediately surfaced a second off-main call site in `InjectionProbe` that nobody
  knew about. And check what the hop then deadlocks against: the probe waited on a
  `DispatchSemaphore` from the main thread, so the new main-actor hop could never be serviced and
  reported as `inject=failed error=timeout`. It now pumps the run loop instead. A blocking wait on
  the main thread is incompatible with any main-actor work the awaited task needs.

### TRAP-33: I nearly filed an app bug caused by my own test instrument
- what happened: a synthetic Right Option poster, written to drive the real app, cleared
  `maskAlternate` on release but LEFT the right-side device bit `0x40` set. `ModifierGate` is
  edge-triggered and reads that bit, so it never saw a release, stayed latched down, and emitted
  nothing for subsequent presses. The symptom was that the app received no hotkey edges at all after
  the first hold - indistinguishable from the CGEventTap having been disabled by the system. I had
  written "the event tap has gone deaf", confirmed a fresh launch worked, and was about to file it
  as a serious runtime defect. Correcting the poster to clear both bits produced a complete
  pressed -> recording -> released -> transcript -> injected cycle with no app change at all.
- warning: the throwaway instrument gets trusted instantly BECAUSE you wrote it, and it is the one
  nobody plants a failure in. Before believing what a tool reports about the system, run it against
  a state whose answer you already know - here, "does a synthetic release produce a released edge?"
  was one line of log away and would have caught it immediately. A tool that fakes hardware must
  match what the hardware actually sends, not merely what makes the down-event work: `sebsto/wispr`
  and `slovo` both key off the device bit for exactly this reason (docs/research/04 sec 1).

### TRAP-34: changing a probe's output line silently disabled the gate that parses it
- what happened: adding `selfResponsible=` and `parent=` to the hotkey probe's `trusted=` line broke
  `test-packaged-app.sh`, whose extractor was `sed 's/^HOTKEY_PROBE trusted=\(.*\)$/\1/p'` - a greedy
  capture that swallowed the new fields, so `PROBE_TRUSTED` became
  "true selfResponsible=false parent=zsh(59474)", compared unequal to "true", and the tap assertion
  was SKIPPED. The gate then printed OK: "not Accessibility-trusted, tap assertion skipped" on a
  machine that is trusted. A permanent gate stopped asserting and still reported success.
- warning: a parser is a coupling, and the thing it parses is an interface. Two fixes, both needed:
  capture one token (`\([^ ]*\)`) rather than the rest of the line, and FAIL when the value is
  neither `true` nor `false` instead of falling through to the skip branch. Planting a renamed field
  now produces "could not parse 'HOTKEY_PROBE trusted=' - refusing to skip silently". The skip branch
  existed for a good reason - a CI runner has no grant - but "cannot tell" and "legitimately absent"
  had been collapsed into the same path, which is what let a parse break masquerade as an untrusted
  machine.

### TRAP-35: a negation check that only handles the spaced form catches nothing real
- what happened: `CleanupDriftGuard`'s tokeniser split on non-alphanumerics, so "don't" became
  "don" + "t" - neither of which is in the negation set. The inversion check, the single most
  valuable thing the guard does, was blind to every CONTRACTION. It passed its tests because those
  tests used "do not" and "should not", the spaced forms, which nobody dictates. One case looked
  caught but was rejected for the wrong reason entirely: an added "shouldn't" tripped
  `ungroundedContent(token: "shouldn")`, so the suite was green while the mechanism was dead.
- warning: when a check keys on a WORD LIST, test the form people actually produce, not the form
  that is convenient to write. The generic question - what would still be true if the property were
  absent? - has a specific version here: would this test pass if the tokeniser mangled the word? It
  did. Apostrophes are now stripped before splitting, both typewriter and typographic, because
  dictation output and cleaned output do not agree on which to use.

### TRAP-36: a justification comment is a claim, and two of mine were false
- what happened: `CustomDictionary` shipped with two design choices, each explained in a comment that
  asserted why it was necessary. Planting the REMOVAL of both left the suite green, so neither
  explanation was demonstrated by anything. Worse, one was measurably wrong: the comment said `\b`
  "misses (pushtext)", and swapping `\b` in leaves every punctuation test passing, because ICU's
  `\b` is Unicode-aware. The real difference is underscore, which the comment never mentioned.
  Longest-first ordering was also undemonstrated - the separator pattern rescues the test case,
  because "cloud code studio" still matches "CloudCode studio" after the shorter rule has run. It IS
  needed, but only when the short rule's replacement DESTROYS the text the longer one would match.
- warning: writing down WHY is good and this project does it everywhere - which is exactly why a
  wrong why is dangerous: it reads as evidence and gets inherited by every later reader. Plant the
  removal of anything a comment calls necessary. If the suite stays green the comment is a
  hypothesis, not a reason, and either the test or the claim has to change. Both were fixed here:
  two discriminating tests added, and the false clause replaced with the measured one.

### TRAP-37: the squash header comes from whichever input you did not check
- what happened: I measured the PR title on #64, merged, and the header that landed came from the
  single COMMIT subject. On #65 I did the reverse - a conventional commit subject, a PR title with
  no type prefix - and because that branch carried TWO commits, GitHub used the TITLE. Master now
  reads `Publish measured latency numbers and log release-to-text (#65)`, in a repo whose stated
  convention is Conventional Commits. `File backlog as GitHub issues ... (#23)` got in the same way,
  months earlier, so this is a recurring hole and not a one-off slip. The setting is
  `squash_merge_commit_title=COMMIT_OR_PR_TITLE`: ONE commit uses the commit subject, MORE THAN ONE
  uses the PR title. A check that reads either input alone looks correct on every PR that happens to
  match it, and a local commit-msg hook cannot see a PR title at all.
- warning: when a value can come from two sources depending on a condition, gate BOTH - never the
  one you happened to test with. `.engine/checks/conventional-subjects.sh` now validates the PR
  title and every commit on the branch, and reserves 8 characters because GitHub appends ` (#N)`
  AFTER the subject has cleared any local hook. Battle-testing it found a second instance of the
  same shape in the gate itself: `[ -n "${PR_TITLE:-}" ]` treated set-but-empty the same as unset,
  so a broken workflow expression would have skipped the check and reported OK. `+set` separates
  them, because a gate that passes while checking nothing is indistinguishable from a gate that
  passed.
