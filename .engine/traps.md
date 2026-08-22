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
