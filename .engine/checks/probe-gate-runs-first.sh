#!/usr/bin/env bash
# Fail-closed guard: nothing in the composition root may run before the headless probe gate.
#
# WHY. `PushTextApp.init()` opens with `runProbeIfRequested()`, and its own comment says "before any
# UI exists". That was false for one property. Swift runs every STORED-PROPERTY DEFAULT before the
# body of `init()` - verified by running it, not recalled - so
#
#     private let actions = AppActions()
#
# constructed `SPUStandardUpdaterController(startingUpdater: true)` on the way past, ahead of the
# gate. Every headless probe run therefore started Sparkle's updater, and in a bare SPM binary with
# no proper bundle it failed and put "Unable to Check For Updates ... the latest version of debug"
# on the user's screen mid-session. Bobby saw it, which is how it was found.
#
# THE RULE. Inside `struct PushTextApp`, a stored property may be DECLARED but not INITIALISED; the
# value is assigned in `init()`, after the gate.
#
# `static let` is exempt on purpose: Swift initialises type properties LAZILY, on first use, so a
# static cannot run ahead of the gate. Computed properties and property wrappers with no `=` are
# untouched - they carry no initializer expression to run.
#
# SCOPE is the `PushTextApp` struct only, not the whole file. `LaunchDelegate` lives here too and is
# constructed by AppKit long after the gate; failing on it would be firing on something that is not
# the hazard, which is how a gate gets ignored.
set -uo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
file="$root/Sources/PushText/PushTextApp.swift"

[ -f "$file" ] || { echo "probe-gate-runs-first: FAIL - $file is missing" >&2; exit 1; }

# Anchored so a COMMENTED-OUT call does not satisfy it. The first version of this check used a
# bare substring match, and commenting the gate out passed - the plant is what found that.
if ! grep -qE '^[[:space:]]*Self\.runProbeIfRequested\(\)' "$file"; then
	echo "probe-gate-runs-first: FAIL - the probe gate call is gone from the composition root" >&2
	exit 1
fi

# The struct body: from its declaration to the next line that closes at column 0.
body="$(awk '/^struct PushTextApp: App \{/ {inside=1} inside {print} inside && /^\}/ {exit}' "$file")"
if [ -z "$body" ]; then
	echo "probe-gate-runs-first: FAIL - could not find 'struct PushTextApp: App {'" >&2
	echo "  The struct was renamed or reshaped; update this check rather than deleting it." >&2
	exit 1
fi

offenders="$(printf '%s\n' "$body" \
	| grep -nE '^    (@[A-Za-z]+(\([^)]*\))? )?(private |fileprivate |internal |public )?(let|var) [A-Za-z_][A-Za-z0-9_]*[^={]*=' \
	|| true)"

if [ -n "$offenders" ]; then
	echo "probe-gate-runs-first: FAIL - stored property initialised before the probe gate:" >&2
	printf '%s\n' "$offenders" | sed 's/^/    /' >&2
	echo "  Declare it without a value and assign it in init(), after runProbeIfRequested()." >&2
	echo "  A default here runs BEFORE the gate and executes in every headless probe run." >&2
	exit 1
fi

echo "probe-gate-runs-first: OK (no stored property runs ahead of the probe gate)"
exit 0
