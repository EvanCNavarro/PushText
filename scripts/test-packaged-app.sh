#!/usr/bin/env bash
# test-packaged-app.sh - prove the packaged .app is well-formed AND actually launches.
#
# Adapted from TermTile's script (docs/research/05-termtile-blueprint.md sec 4). Asserts the bundle
# invariants (plist keys, signature, no stray Bundle.module resource path), then launches the bundled
# inner executable and polls liveness with `kill -0` - a foreign-path launch proof, because a
# locally-built .app can look healthy while a packaged resource is missing.
#
# SAFETY: only ever `kill`s the ONE pid it spawned - never pkill/killall.
#
# Beyond liveness, this asserts the hotkey probe's stdout markers - a liveness poll alone cannot
# tell a working app from one that launched and did nothing. The tap assertion is CONDITIONAL on
# Accessibility trust, because a CI runner is never trusted and an unconditional assert would make
# the gate permanently red there (and therefore ignored).
set -euo pipefail

APP="${1:-${APP:-dist/PushText.app}}"
APP_NAME="${APP_NAME:-PushText}"
BUNDLE_ID="${BUNDLE_ID:-dev.ecn.apps.pushtext}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() { echo "FAIL: $*" >&2; exit 1; }

PID=""
WORK="$(mktemp -d)"
LAUNCH_LOG="$WORK/launch.log"
SMOKE_HOME="$WORK/home"
mkdir -p "$SMOKE_HOME"

stop_launched_app() {
	if [ -n "$PID" ]; then
		kill "$PID" 2>/dev/null || true
		wait "$PID" 2>/dev/null || true
		PID=""
	fi
}

cleanup() {
	local status=$?
	trap - EXIT
	stop_launched_app
	rm -rf "$WORK" || echo "WARN: failed to remove $WORK" >&2
	exit "$status"
}
trap cleanup EXIT

# --- Structural invariants -------------------------------------------------------------------
[ -d "$APP" ] || fail "bundle not found: $APP"
BIN="$APP/Contents/MacOS/$APP_NAME"
[ -x "$BIN" ] || fail "bundle executable missing/not executable: $BIN"

PLIST="$APP/Contents/Info.plist"
[ "$(plutil -extract CFBundleIdentifier raw "$PLIST")" = "$BUNDLE_ID" ] \
	|| fail "CFBundleIdentifier != $BUNDLE_ID"
[ "$(plutil -extract LSUIElement raw "$PLIST")" = "true" ] \
	|| fail "LSUIElement must be true (menu-bar only)"
plutil -extract CFBundleVersion raw "$PLIST" >/dev/null || fail "CFBundleVersion missing"
plutil -extract SUFeedURL raw "$PLIST" >/dev/null || fail "SUFeedURL missing"
# The app records audio; without this key macOS kills the process on first mic access.
plutil -extract NSMicrophoneUsageDescription raw "$PLIST" >/dev/null \
	|| fail "NSMicrophoneUsageDescription missing (mic access would terminate the app)"

# Sparkle's public key is required for any build that real users install. A local dev build may
# legitimately lack it; a release build may not.
if [ "${REQUIRE_SPARKLE_KEY:-0}" = "1" ]; then
	plutil -extract SUPublicEDKey raw "$PLIST" >/dev/null \
		|| fail "SUPublicEDKey missing - updates would not verify"
fi

# Signature must verify strict. Local/dev smoke may accept ad-hoc; release smoke sets
# REQUIRE_STABLE_CODESIGN=1 so public artifacts cannot regress to TCC-breaking cdhash-only identity.
codesign --verify --deep --strict "$APP" || fail "codesign --verify --deep --strict failed"
if [ "${REQUIRE_STABLE_CODESIGN:-0}" = "1" ]; then
	SIGNATURE_INFO="$(codesign -dv --verbose=4 "$APP" 2>&1)"
	DESIGNATED_REQ="$(codesign -d -r- "$APP" 2>&1)"
	if echo "$SIGNATURE_INFO" | grep -q "Signature=adhoc"; then
		fail "stable signing required, but app is ad-hoc signed"
	fi
	if ! echo "$SIGNATURE_INFO" | grep -q "Authority="; then
		fail "stable signing required, but app signature has no certificate authority"
	fi
	if echo "$DESIGNATED_REQ" | grep -q "cdhash H\""; then
		fail "stable signing required, but designated requirement is cdhash-only"
	fi
	if [ "${REQUIRE_DEVELOPER_ID_CODESIGN:-0}" = "1" ]; then
		APP_ENTITLEMENTS="$(codesign -d --entitlements :- "$APP" 2>/dev/null || true)"
		if ! echo "$SIGNATURE_INFO" | grep -Fq "Authority=Developer ID Application:"; then
			fail "Developer ID signing required, but signature is not Developer ID Application"
		fi
		test -n "${REQUIRE_CODESIGN_TEAM_ID:-}" || fail "REQUIRE_CODESIGN_TEAM_ID is required"
		if ! echo "$SIGNATURE_INFO" | grep -Fq "TeamIdentifier=$REQUIRE_CODESIGN_TEAM_ID"; then
			fail "Developer ID signing required, but TeamIdentifier != $REQUIRE_CODESIGN_TEAM_ID"
		fi
		if echo "$APP_ENTITLEMENTS" | grep -Fq "com.apple.security.cs.disable-library-validation"; then
			fail "Developer ID signing required, but app disables hardened-runtime library validation"
		fi
	fi
fi

# Regression guard (TRAP-4): runtime code may only touch Bundle.module inside a DEBUG-only fallback.
# Comments are ignored; release code must resolve from Bundle.main. The awk is #if-nesting aware, so
# a Bundle.module inside `#if DEBUG` -> `#if os(macOS)` is still correctly seen as DEBUG-guarded.
if ! find Sources -name '*.swift' -type f -print0 | xargs -0 awk '
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
	fail "Bundle.module used outside a DEBUG guard - packaged resource path would be baked in"
fi

# --- Launch proof ----------------------------------------------------------------------------
CRASH_DIR="$HOME/Library/Logs/DiagnosticReports"
before="$(ls "$CRASH_DIR" 2>/dev/null | grep -c "^$APP_NAME" || true)"

env HOME="$SMOKE_HOME" CFFIXED_USER_HOME="$SMOKE_HOME" "$BIN" >"$LAUNCH_LOG" 2>&1 &
PID=$!

# Poll liveness ~4s (an accessory menu-bar app runs indefinitely; a crash makes kill -0 fail).
alive=0
for _ in 1 2 3 4 5 6 7 8; do
	if kill -0 "$PID" 2>/dev/null; then alive=$((alive+1)); else break; fi
	sleep 0.5
done
if [ "$alive" -lt 8 ]; then
	sed 's/^/launch: /' "$LAUNCH_LOG" >&2 || true
	fail "$APP_NAME died within ~4s (alive=$alive/8)"
fi
stop_launched_app

after="$(ls "$CRASH_DIR" 2>/dev/null | grep -c "^$APP_NAME" || true)"
[ "$after" -le "$before" ] || fail "a new crash report appeared for $APP_NAME"

# --- Hotkey probe ------------------------------------------------------------------------------
# Runs the real CGEvent tap path headlessly and reports machine-readable markers.
PROBE_LOG="$WORK/probe.log"
env HOME="$SMOKE_HOME" CFFIXED_USER_HOME="$SMOKE_HOME" \
	PUSHTEXT_HOTKEY_PROBE=1 PUSHTEXT_HOTKEY_PROBE_SECONDS=2 \
	"$BIN" >"$PROBE_LOG" 2>&1 || true

grep -q "HOTKEY_PROBE binding=" "$PROBE_LOG" || {
	sed 's/^/probe: /' "$PROBE_LOG" >&2 || true
	fail "hotkey probe produced no binding marker"
}
grep -q "HOTKEY_PROBE finished" "$PROBE_LOG" || {
	sed 's/^/probe: /' "$PROBE_LOG" >&2 || true
	fail "hotkey probe did not finish"
}

PROBE_TRUSTED="$(sed -n 's/^HOTKEY_PROBE trusted=\(.*\)$/\1/p' "$PROBE_LOG")"
if [ "$PROBE_TRUSTED" = "true" ]; then
	grep -q "HOTKEY_PROBE tap=armed" "$PROBE_LOG" || {
		sed 's/^/probe: /' "$PROBE_LOG" >&2 || true
		fail "process is Accessibility-trusted but the event tap did not arm"
	}
	# Deterministic recovery check: kill the tap the way the OS would, and require the monitor to
	# bring it back. Asserts enabled=true, NOT reEnables - a planted no-op re-arm still reports
	# reEnables=1, so the counter alone cannot tell recovery from a dead tap.
	KILL_LOG="$WORK/killtap.log"
	env HOME="$SMOKE_HOME" CFFIXED_USER_HOME="$SMOKE_HOME" \
		PUSHTEXT_HOTKEY_PROBE=1 PUSHTEXT_HOTKEY_PROBE_KILLTAP=1 PUSHTEXT_HOTKEY_PROBE_SECONDS=1 \
		"$BIN" >"$KILL_LOG" 2>&1 || true
	grep -q "HOTKEY_PROBE killtap=killed enabled=false" "$KILL_LOG" || {
		sed 's/^/killtap: /' "$KILL_LOG" >&2 || true
		fail "fault injection did not actually disable the tap - the recovery check proves nothing"
	}
	grep -q "HOTKEY_PROBE killtap=after enabled=true" "$KILL_LOG" || {
		sed 's/^/killtap: /' "$KILL_LOG" >&2 || true
		fail "tap was disabled and never came back"
	}
	PROBE_NOTE="tap armed, recovered from forced disable"
else
	# Not a failure: an untrusted process (CI, a fresh machine) legitimately cannot arm a tap.
	PROBE_NOTE="not Accessibility-trusted, tap assertion skipped"
fi

# --- Audio probe -------------------------------------------------------------------------------
# Conditional on the microphone grant for the same reason as the hotkey tap: a CI runner has none,
# and an unconditional assert would make the gate permanently red and therefore ignored.
AUDIO_LOG="$WORK/audio.log"
env HOME="$SMOKE_HOME" CFFIXED_USER_HOME="$SMOKE_HOME" \
	PUSHTEXT_AUDIO_PROBE=1 PUSHTEXT_AUDIO_PROBE_SECONDS=2 \
	"$BIN" >"$AUDIO_LOG" 2>&1 || true

grep -q "AUDIO_PROBE micAuthorized=" "$AUDIO_LOG" || {
	sed 's/^/audio: /' "$AUDIO_LOG" >&2 || true
	fail "audio probe produced no authorization marker"
}

if grep -q "AUDIO_PROBE micAuthorized=true" "$AUDIO_LOG"; then
	grep -q "AUDIO_PROBE capture=started" "$AUDIO_LOG" || {
		sed 's/^/audio: /' "$AUDIO_LOG" >&2 || true
		fail "microphone is authorized but capture never started"
	}
	# Monotonic AND contiguous timestamps: non-monotonic bufferStartTime is one of the suspected
	# causes of FB22149971, so it is asserted at the source rather than discovered on Tahoe.
	grep -q "AUDIO_PROBE timestampsMonotonic=true contiguous=true" "$AUDIO_LOG" || {
		sed 's/^/audio: /' "$AUDIO_LOG" >&2 || true
		fail "capture produced non-monotonic or non-contiguous buffer timestamps"
	}
	# Frames must actually have arrived - "started" plus silence is a dead capture path.
	grep -qE "AUDIO_PROBE buffers=[1-9][0-9]* frames=[1-9]" "$AUDIO_LOG" || {
		sed 's/^/audio: /' "$AUDIO_LOG" >&2 || true
		fail "capture started but delivered no audio frames"
	}
	AUDIO_NOTE="capture verified, timestamps monotonic+contiguous"
else
	AUDIO_NOTE="microphone not authorized, capture assertions skipped"
fi

echo "OK: $APP launched and stayed alive (alive=$alive/8, crash-reports ${before}->${after}); hotkey probe: ${PROBE_NOTE}; audio probe: ${AUDIO_NOTE}"
