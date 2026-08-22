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
