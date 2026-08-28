#!/usr/bin/env bash
# The test suite may acquire exactly ONE named pasteboard (#234).
#
# NSPasteboard(name:) reaches the pasteboard server over mach, and on a headless CI runner that
# server is intermittently unresponsive. That is the #144 wedge: unbounded, it took the Test job down
# for ten minutes at a time; #179 bounded it, so it now fails loudly in ten seconds instead. The
# bound was the right fix for the hang and is not what this guards.
#
# What #179 left in place was the LOAD. PasteboardMarkersTests took a distinct named board per test,
# and Swift Testing runs tests in parallel, so seven acquisitions hit that serial setup path at once.
# Run 33174982445: four returned, the other three all timed out at the same instant, on a docs-only
# PR whose Swift sources were byte-identical to a green master run two minutes earlier.
#
# WHY A SOURCE GATE AND NOT A TEST. The obvious runtime guard - count acquisitions, assert 1 - was
# written first and planted against. It PASSED on the broken version: with the suite serialized the
# counting test ran first, saw its own single acquisition, and reported green while every later test
# took another board. A verdict that depends on execution order cannot say no. Counting SITES in the
# source has no such dependency.
#
# WHAT THIS CANNOT SEE, stated because a gate's blind spot is part of its result: it counts textual
# call sites, so one site inside a loop would still acquire many boards. The single site lives in a
# `static let`, which Swift initialises exactly once, and that structure is what makes one site mean
# one acquisition.
set -euo pipefail
cd "$(dirname "$0")/../.."

# STRING LITERALS AND COMMENTS ARE STRIPPED BEFORE COUNTING, and both exclusions were bought by
# running this against the unchanged baseline first. Prose writes the symbol as `NSPasteboard(name:)`,
# which contains the call pattern; and the acquisition passes its own name to BoundedWork as the
# label "NSPasteboard(name: \(name.rawValue))". The first draft counted both and reported 2 sites on
# a tree that has 1 - a gate red on correct code, which is the kind nobody keeps.
SITES=$(find Tests -name '*.swift' -type f -print0 \
	| xargs -0 sed -E 's|"[^"]*"||g' \
	| sed -E 's|^[[:space:]]*||' \
	| grep -v '^//' \
	| grep -c 'NSPasteboard(name:' || true)

if [ "$SITES" != "1" ]; then
	echo "one-test-pasteboard: FAIL - $SITES acquisition sites in Tests/, expected exactly 1" >&2
	echo "" >&2
	echo "Each site is another concurrent mach round trip to a server that stalls under exactly" >&2
	echo "that load (#234, #144). Share the suite's existing pasteboard instead of taking another." >&2
	echo "" >&2
	find Tests -name '*.swift' -type f -print0 \
		| xargs -0 grep -n 'NSPasteboard(name:' \
		| grep -v ':[[:space:]]*//' >&2 || true
	exit 1
fi

echo "one-test-pasteboard: ok - 1 acquisition site in Tests/"
