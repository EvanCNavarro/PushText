#!/usr/bin/env bash
# The packaged app must never reach for Bundle.module (TRAP-4).
#
# SwiftPM's generated accessor falls back to an ABSOLUTE PATH into the build directory of the machine
# that compiled the binary, and calls fatalError when neither that nor a bundle beside the app
# exists. `build-app.sh` ships resources flattened into Contents/Resources, so a packaged app has no
# such bundle - which means unguarded Bundle.module works perfectly for whoever built it and kills
# the app for everyone else.
#
# THIS CHECK EXISTED AND DID NOT RUN WHERE IT MATTERED. It lived only inside
# scripts/test-packaged-app.sh, which needs a BUILT app and is not part of the PR gate, so #217
# merged with an unguarded Bundle.module and would have shipped the crash. Extracted here so CI runs
# it on every pull request; test-packaged-app.sh now calls this file rather than keeping a copy.
#
# Measured while extracting it: the offending build died with `Trace/BPT trap: 5`, exit 133,
# "could not load resource bundle", once its build directory was renamed to stand in for any other
# Mac. The guarded version stayed up under identical conditions.
set -euo pipefail
cd "$(dirname "$0")/../.."

# Runtime code may only touch Bundle.module inside a DEBUG-only fallback (TRAP-4).
# Comments are ignored; release code must resolve from Bundle.main. The awk is #if-nesting aware, so
# a Bundle.module inside `#if DEBUG` -> `#if os(macOS)` is still correctly seen as DEBUG-guarded.
#
# SCOPE WIDENED 2026-08-24 to include first-party DEPENDENCY sources, and that widening is the whole
# point. This guard existed, was correct, and scanned `Sources` only - our own code. The Bundle.module
# that shipped a launch crash in v0.2.0 was in MacFaceKit, a dependency, so the guard never looked at
# it (#134). A trap the project had already named, missed by one directory.
#
# Limited to 400faces checkouts: third-party packages are not ours to fix, and failing on Sparkle's
# internals would make this permanently red and therefore ignored.
# The checkout's own git remote is NOT usable here: SwiftPM points it at a LOCAL MIRROR
# (.build/repositories/MacFaceKit-a238d2cc), so matching on it silently covered nothing - the first
# version of this widening printed "covering: Sources" and looked like it had worked. Package.resolved
# carries the real URL, so read the repository names out of that instead.
GUARD_PATHS="Sources"
for REPO in $(grep -oE '"location"[^"]*"[^"]*400faces/[^"]+"' Package.resolved 2>/dev/null \
		| sed -E 's|.*400faces/||; s|\.git"$||; s|"$||'); do
	if [ -d ".build/checkouts/$REPO/Sources" ]; then
		GUARD_PATHS="$GUARD_PATHS .build/checkouts/$REPO/Sources"
	fi
done
echo "bundle-module-guarded: covering $GUARD_PATHS" >&2
if ! find $GUARD_PATHS -name '*.swift' -type f -print0 | xargs -0 awk '
	FNR == 1 {
		depth = 0
		debugDepth = 0
		delete debugGuard
	}
	/^[[:space:]]*\/\// { next }
	/^[[:space:]]*#if[[:space:]]+DEBUG([[:space:]]|$)/ {
		depth++
		debugGuard[depth] = 1
		debugDepth++
		next
	}
	/^[[:space:]]*#if[[:space:]]/ {
		depth++
		debugGuard[depth] = 0
		next
	}
	/^[[:space:]]*#elseif[[:space:]]+DEBUG([[:space:]]|$)/ {
		if (debugGuard[depth] != 1) {
			debugGuard[depth] = 1
			debugDepth++
		}
		next
	}
	/^[[:space:]]*#elseif[[:space:]]/ || /^[[:space:]]*#else([[:space:]]|$)/ {
		if (debugGuard[depth] == 1) {
			debugGuard[depth] = 0
			debugDepth--
		}
		next
	}
	/^[[:space:]]*#endif([[:space:]]|$)/ {
		if (debugGuard[depth] == 1) {
			debugDepth--
		}
		delete debugGuard[depth]
		if (depth > 0) {
			depth--
		}
		next
	}
	/Bundle[.]module/ && debugDepth == 0 {
		print FILENAME ":" FNR ": Bundle.module outside #if DEBUG"
		found = 1
	}
	END { exit found ? 1 : 0 }
'; then
	echo "bundle-module-guarded: FAIL - Bundle.module outside a DEBUG guard." >&2
	echo "  The packaged resource path would be baked in, and the app would fatalError on" >&2
	echo "  every machine except the one that built it." >&2
	exit 1
fi

echo "bundle-module-guarded: OK"
