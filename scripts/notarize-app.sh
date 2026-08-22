#!/usr/bin/env bash
# notarize-app.sh - submit a signed .app to Apple Notary, staple, validate, and Gatekeeper-assess it.
set -euo pipefail

APP="${1:-${APP:-}}"
[ -n "$APP" ] || { echo "usage: scripts/notarize-app.sh path/to/App.app" >&2; exit 2; }
[ -d "$APP" ] || { echo "notarize-app.sh: app bundle not found: $APP" >&2; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/notary-auth.sh
source "$ROOT/scripts/lib/notary-auth.sh"

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

TIMEOUT="${PUSHTEXT_NOTARY_TIMEOUT:-60m}"
pushtext_notary_prepare_auth "$WORK"

ZIP="$WORK/$(basename "${APP%.app}")-notary.zip"
RESULT_JSON="$WORK/notary-submit.json"
ditto -c -k --keepParent "$APP" "$ZIP"

set +e
xcrun notarytool submit "$ZIP" \
	"${PUSHTEXT_NOTARY_ARGS[@]}" \
	--wait \
	--timeout "$TIMEOUT" \
	--output-format json | tee "$RESULT_JSON"
SUBMIT_STATUS="${PIPESTATUS[0]}"
set -e

STATUS="$(python3 - "$RESULT_JSON" <<'PY'
import json
import sys
try:
    with open(sys.argv[1], encoding="utf-8") as fh:
        print(json.load(fh).get("status", ""))
except Exception:
    print("")
PY
)"
JOB_ID="$(python3 - "$RESULT_JSON" <<'PY'
import json
import sys
try:
    with open(sys.argv[1], encoding="utf-8") as fh:
        print(json.load(fh).get("id", ""))
except Exception:
    print("")
PY
)"
if [ "$SUBMIT_STATUS" -ne 0 ]; then
	if [ -n "$JOB_ID" ]; then
		xcrun notarytool info "$JOB_ID" \
			"${PUSHTEXT_NOTARY_ARGS[@]}" || true
		xcrun notarytool log "$JOB_ID" \
			"${PUSHTEXT_NOTARY_ARGS[@]}" || true
	fi
	echo "notarize-app.sh: notarization did not complete (exit=$SUBMIT_STATUS, status=${STATUS:-unknown}, id=${JOB_ID:-unknown})" >&2
	exit "$SUBMIT_STATUS"
fi

if [ "$STATUS" != "Accepted" ]; then
	if [ -n "$JOB_ID" ]; then
		xcrun notarytool log "$JOB_ID" \
			"${PUSHTEXT_NOTARY_ARGS[@]}" || true
	fi
	echo "notarize-app.sh: notarization failed with status: $STATUS" >&2
	exit 1
fi

xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=4 "$APP"
