#!/usr/bin/env bash
# install-app.sh - build (stable identity if the dev cert is present) and install PushText.app, then
# relaunch. Installs to /Applications (the standard, reliably Spotlight-indexed + LaunchServices-known
# location - so the app is findable in Open panels / the Privacy permission pickers, exactly where a
# user who followed the README "drag to /Applications" would put it). ~/Applications is NOT reliably
# indexed, which made the app invisible in those pickers. Set PUSHTEXT_INSTALL_DIR to override.
# After copying, we force a Spotlight import + LaunchServices registration so a freshly-built bundle
# shows up immediately rather than after Spotlight eventually notices it.
set -euo pipefail
cd "$(dirname "$0")/.."
APP_NAME="${APP_NAME:-PushText}"
APP="$(./scripts/build-app.sh | tail -1)"
DEST="${PUSHTEXT_INSTALL_DIR:-/Applications}"
INSTALLED_APP="$DEST/$APP_NAME.app"
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

wait_for_app_exit() {
	for _ in 1 2 3 4 5 6 7 8 9 10; do
		if ! pgrep -x "$APP_NAME" >/dev/null 2>&1; then
			return 0
		fi
		sleep 0.2
	done
	echo "WARN: $APP_NAME was still exiting; continuing with install" >&2
}

mkdir -p "$DEST"
pkill -x "$APP_NAME" 2>/dev/null || true
wait_for_app_exit
# Clean up the old ~/Applications location if we're migrating away from it.
rm -rf "$HOME/Applications/$APP_NAME.app" 2>/dev/null || true
rm -rf "$HOME/Applications/$APP_NAME" 2>/dev/null || true
rm -rf "$INSTALLED_APP"
ditto "$APP" "$INSTALLED_APP"

# Make it immediately findable in Open/permission pickers (not after Spotlight eventually catches up).
"$LSREG" -f "$INSTALLED_APP" 2>/dev/null || true
mdimport "$INSTALLED_APP" 2>/dev/null || true

open "$INSTALLED_APP" || {
	sleep 1
	open -n "$INSTALLED_APP"
}
echo "$INSTALLED_APP"
