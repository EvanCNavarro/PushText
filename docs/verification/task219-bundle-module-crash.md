# The menu glyph would have crashed every machine but this one (#219)

#217 shipped the menu-bar mark and loaded it with `Bundle.module`. On the machine that built it, that
works. On any other machine the app dies on its first menu-bar draw.

## Measured, both directions

The offending build, packaged into a `.app` and run with its build directory renamed to stand in for
any other Mac:

```
Trace/BPT trap: 5          exit 133
Fatal error: could not load resource bundle: from
  .../PushText.app/PushText_PushText.bundle or
  .../wt-master/.build/arm64-apple-macosx/debug/PushText_PushText.bundle
```

The same app with `Bundle.module` guarded stayed alive under identical conditions. The check
discriminates, so neither result is an accident of the harness.

## Why it works locally and nowhere else

SwiftPM generates an accessor that looks in exactly two places:

```swift
let mainPath  = Bundle.main.bundleURL.appendingPathComponent("PushText_PushText.bundle").path
let buildPath = "/Users/evancnavarro/Developer/pushtext/.build/.../PushText_PushText.bundle"
guard let bundle = Bundle(path: mainPath) ?? Bundle(path: buildPath) else { Swift.fatalError(...) }
```

The second is an absolute path on the COMPILING machine. `build-app.sh` ships resources flattened
into `Contents/Resources` - the only placement that both signs cleanly and is actually found - so a
packaged app has no `PushText_PushText.bundle` at all. For the developer, `buildPath` resolves and
everything looks perfect. For everyone else, both fail and the app traps.

**v0.2.0 shipped exactly this**, carrying `/Users/runner/work/PushText/...` from CI.

## The guard existed. It did not run where it mattered.

`scripts/test-packaged-app.sh` has carried a TRAP-4 regression guard since v0.2.0 - an `#if`-nesting
aware scan asserting `Bundle.module` appears only inside `#if DEBUG`. It was correct, and it caught
this defect the moment it was pointed at the code:

```
Sources/PushText/MenuBarGlyph.swift:84: Bundle.module outside #if DEBUG
```

It never ran, because it needs a BUILT app and the PR gate runs `.engine/checks`, `swift test` and
`swiftlint`. #217 went green through CI and merged with the crash in it.

**A gate that only runs somewhere the change does not go is not a gate.** It is now
`.engine/checks/bundle-module-guarded.sh`, called by CI on every pull request AND by
`test-packaged-app.sh`, which delegates rather than keeping a second copy.

## The fix

`Bundle.main` in shipped code; `Bundle.module` only inside `#if DEBUG`, where `swift test` needs it
because there the main bundle is the test runner and the build path genuinely exists. That is the
inverse of the packaged app, which is why one fallback covers both without either reaching a
`fatalError`.

## What this says about the tests

All 451 passed, before and after. They load through the same `load()` and cannot tell the two bundles
apart, because under `swift test` the DEBUG path is the one that works. **No unit test in this shape
could have caught it** - the defect only exists in a configuration the test suite never runs in. The
evidence had to be a packaged app on a machine that did not build it.

Bobby's installed 0.6.5 was never affected: the glyph code landed after that tag, and 0.6.6 had not
been cut.
