#!/usr/bin/env bash
# probe-window-layering.sh - prove a window opened from the menu is not buried under the panel (#209).
#
# MUST be given a BUNDLED app. `MenuBarExtra` only creates its panel in a real app, and the panel is
# the whole subject: measured levels are
#
#     _TtGC7SwiftUI18MenuBarExtraWindowVS_7AnyView_   level=101
#     NSStatusBarWindow                               level=25
#     NSWindow  (the history viewer)                  level=0
#
# so no amount of activating or raising helps - 101 beats 0 and the panel has to be closed.
#
#   scripts/build-app.sh
#   scripts/probe-window-layering.sh dist/PushText.app
#
# The panel is opened by asking the status item's own button to click itself. Driving the real mouse
# was the first approach: on a multi-display Mac the status item sat at x=-4607, the mouse tool did
# not honour the negative coordinate, and the click landed on the APPLE MENU with Restart
# highlighted. There are no coordinates here to get wrong.
set -u

APP="${1:?usage: probe-window-layering.sh <path to PushText.app>}"
W="${PROBE_DIR:-$(mktemp -d)}"
mkdir -p "$W"
LOG="$W/layering.log"
rm -f "$LOG"

PUSHTEXT_DEFAULTS_SUITE="pushtext.probe.209" \
PUSHTEXT_LAYERING_PROBE="${OPEN_AFTER:-6}" \
    "$APP/Contents/MacOS/PushText" > "$LOG" 2>&1 &
PID=$!
trap 'kill $PID 2>/dev/null' EXIT

waitfor() {  # fails CLOSED: a line that never arrives is inconclusive, never success
    local needle="$1" tries="$2" i
    for i in $(seq 1 "$tries"); do
        grep -q "$needle" "$LOG" && return 0
        sleep 0.5
    done
    return 1
}

waitfor "LAYERING_PROBE panelClicked" 60 || { echo "PANEL NEVER OPENED - inconclusive"; cat "$LOG"; exit 3; }
waitfor "LAYERING_PROBE historyOpened" 60 || { echo "HISTORY NEVER OPENED - inconclusive"; exit 3; }
waitfor "LAYERING_PROBE done" 90 || { echo "PROBE NEVER FINISHED - inconclusive"; exit 3; }
kill $PID 2>/dev/null; wait $PID 2>/dev/null

panel_at()   { grep -c "t=$1 .*MenuBarExtraWindow" "$LOG"; }
history_at() { grep -c "t=$1 class=NSWindow " "$LOG"; }

# Sampled one second apart. t=2..5 is panel-only, the history window opens at OPEN_AFTER, and the
# status item is clicked again three seconds later.
OPENED="${OPEN_AFTER:-6}"
BEFORE_PANEL=$(panel_at 4)
AFTER_PANEL=$(panel_at $((OPENED + 1)))
AFTER_HISTORY=$(history_at $((OPENED + 1)))
REOPENED=$(panel_at $((OPENED + 5)))

echo "panel visible before opening a window : $BEFORE_PANEL"
echo "panel visible after opening a window  : $AFTER_PANEL"
echo "history window visible after opening  : $AFTER_HISTORY"
echo "panel visible after clicking the icon : $REOPENED"
echo

FAIL=0
# A run where the panel never opened proves nothing about dismissing it.
if [ "$BEFORE_PANEL" = "0" ]; then
    echo "SETUP FAILED - the panel was never open, so there was nothing to dismiss"
    exit 3
fi
if [ "$AFTER_PANEL" = "0" ]; then
    echo "ok     - opening a window closed the panel"
else
    echo "FAILED - the panel stayed up over the window (this is #209)"
    FAIL=1
fi
if [ "$AFTER_HISTORY" != "0" ]; then
    echo "ok     - the window itself is on screen"
else
    echo "FAILED - no window appeared, so the panel result means nothing"
    FAIL=1
fi
# The regression the first fix caused: `orderOut` hid the panel but left SwiftUI thinking it was
# open, so the next click toggled it closed and the menu-bar icon appeared dead.
if [ "$REOPENED" != "0" ]; then
    echo "ok     - clicking the icon opens the panel again"
else
    echo "FAILED - the panel did not reopen; the menu-bar icon is now dead"
    FAIL=1
fi

echo
if [ $FAIL -eq 0 ]; then
    echo "VERDICT: windows open above the panel, and the panel still works"
else
    echo "VERDICT: NOT CONFIRMED"
fi
exit $FAIL
