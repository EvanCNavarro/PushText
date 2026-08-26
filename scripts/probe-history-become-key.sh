#!/usr/bin/env bash
# probe-history-become-key.sh - prove the history viewer re-reads when it BECOMES KEY (#207).
#
# The notification path (#202) covers anything PushText itself writes. This covers the other half:
# a change made from OUTSIDE the app, which posts nothing and is only ever noticed when the user
# comes back to the window.
#
# MUST be given a BUNDLED app, not the SPM binary. An unbundled binary cannot activate, an inactive
# app cannot make a window key, and `makeKeyAndOrderFront` is then a silent no-op - measured while
# writing this, as "MAKEKEY before: isKey=false appActive=false / after: isKey=false" with no
# delegate callback at all. Run against the binary and you get a failing verdict about working code.
#
#   scripts/build-app.sh
#   scripts/probe-history-become-key.sh dist/PushText.app/Contents/MacOS/PushText
#
# The verdict comes from the row counts the app reports, NEVER from screenshot hashes. A whole-window
# hash cannot separate "the list gained a row" from "the title bar dimmed because the window lost
# key" - on the first run it read that dimming as a failed control.
set -u

BIN="${1:?usage: probe-history-become-key.sh <path to PushText.app/Contents/MacOS/PushText>}"
W="${PROBE_DIR:-$(mktemp -d)}"
mkdir -p "$W"
HIST="$W/history.jsonl"
LOG="$W/app.log"

cat > "$HIST" <<'JSONL'
{"durationSeconds":12.4,"recordedAt":"2026-08-25T19:10:00Z","text":"The first dictation, on disk before the window opened."}
{"durationSeconds":8.1,"recordedAt":"2026-08-25T19:20:00Z","text":"The second dictation, also there at open time."}
JSONL

export PUSHTEXT_HISTORY_FILE="$HIST"
export PUSHTEXT_DEFAULTS_SUITE="pushtext.probe.207"
export PUSHTEXT_MENU_PROBE=1
export PUSHTEXT_MENU_PROBE_HISTORY=live
export PUSHTEXT_HISTORY_PROBE_REKEY="${REKEY_AFTER:-7}"

"$BIN" > "$LOG" 2>&1 &
APP=$!
trap 'kill $APP 2>/dev/null' EXIT

waitfor() {  # fails CLOSED: a line that never arrives is inconclusive, never success
    local needle="$1" tries="$2" i
    for i in $(seq 1 "$tries"); do
        grep -q "$needle" "$LOG" && return 0
        sleep 0.5
    done
    return 1
}

waitfor "HISTORY_PROBE window=" 60 || { echo "NO WINDOW - inconclusive"; cat "$LOG"; exit 3; }
echo "viewer open, $(grep -c . "$HIST") records on disk"

waitfor "HISTORY_PROBE keystolen" 30 || { echo "KEY WAS NEVER STOLEN - inconclusive"; exit 3; }
echo "key taken away - the viewer is no longer key"

# The external edit. A raw append, NOT through JSONLHistoryStore, so nothing is posted.
echo '{"durationSeconds":30.0,"recordedAt":"2026-08-25T22:30:00Z","text":"THIRD - written outside PushText while the window was unkeyed."}' >> "$HIST"
echo "edited from outside; $(grep -c . "$HIST") records on disk"

waitfor "HISTORY_PROBE rekeyed" 40 || { echo "NEVER REKEYED - inconclusive"; exit 3; }
kill $APP 2>/dev/null; wait $APP 2>/dev/null

BEFOREKEY=$(grep -o 'rows_before_key=[-0-9]*' "$LOG" | head -1 | cut -d= -f2)
AFTERKEY=$(grep -o 'rows_after_key=[-0-9]*' "$LOG" | head -1 | cut -d= -f2)
echo
echo "rows while unkeyed, after the outside edit : ${BEFOREKEY:-MISSING}"
echo "rows once the window became key           : ${AFTERKEY:-MISSING}"

if [ -z "${BEFOREKEY:-}" ] || [ -z "${AFTERKEY:-}" ]; then
    echo "A SAMPLE IS MISSING - inconclusive, not a result"
    exit 3
fi

FAIL=0
if [ "$BEFOREKEY" = "2" ]; then
    echo "CONTROL ok     - an outside edit alone did NOT update the list"
else
    echo "CONTROL FAILED - expected 2 rows while unkeyed, got $BEFOREKEY, so something"
    echo "                 other than becoming key refreshed it and the result below means nothing"
    FAIL=1
fi
if [ "$AFTERKEY" = "3" ]; then
    echo "RESULT  ok     - becoming key re-read the file and picked up the new record"
else
    echo "RESULT  FAILED - expected 3 rows after becoming key, got $AFTERKEY"
    FAIL=1
fi

echo
if [ $FAIL -eq 0 ]; then
    echo "VERDICT: become-key refresh CONFIRMED"
else
    echo "VERDICT: NOT CONFIRMED"
fi
exit $FAIL
