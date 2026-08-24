#!/usr/bin/env bash
# build-app.sh - assemble the SPM binary into a signed distributable PushText.app.
#
# Adapted from TermTile's build-app.sh (see docs/research/05-termtile-blueprint.md sec 4). Everything is
# env-overridable so CI and local e2e reuse the SAME build path with no drift. Menu-bar-only
# (LSUIElement); Sparkle is embedded, so signing is an inside-out pass with the hardened runtime
# enabled and NO --deep on sign operations (--deep corrupts nested Sparkle signatures), then
# verified --deep --strict. CFBundleVersion is the monotonic commit count, NEVER dots-stripped
# (0.10.1 -> 0101 collides with 0.1.01).
set -euo pipefail

APP_NAME="${APP_NAME:-PushText}"
BUNDLE_ID="${BUNDLE_ID:-dev.ecn.apps.pushtext}"
CONFIGURATION="${CONFIGURATION:-release}"
# NOT a release number. Release CI passes the tag (SHORT_VERSION="${GITHUB_REF_NAME#v}"), so this
# default is only ever seen by a LOCAL build - and it used to be "0.1.0", which meant every dev
# build claimed to be the shipped release. Bobby had 0.1.0 (72) on screen while 0.1.0 (59) and
# 0.2.0 (80) were the only two releases that exist; the only way to tell was the build number.
SHORT_VERSION="${SHORT_VERSION:-0.0.0-dev}"
DIST_DIR="${DIST_DIR:-dist}"
ICON_SRC="${ICON_SRC:-Sources/PushText/Resources/AppIcon.png}"
# LSMinimumSystemVersion, and it must TRACK Package.swift's platform floor (#16). A value below
# the floor is worse than a wrong number: Gatekeeper would let the app launch on an OS where
# SpeechAnalyzer does not exist, so the failure lands on the user as a broken app rather than on
# the installer as a refusal.
MIN_SYSTEM_VERSION="${MIN_SYSTEM_VERSION:-26.0}"
# Sparkle appcast URL (Info.plist SUFeedURL).
#
# MEASURED 2026-08-24: this URL returns 404 to an anonymous client, and will keep doing so while the
# repository is PRIVATE - GitHub release assets on a private repo need authentication, and Sparkle
# sends none. The appcast itself is fine: the same asset fetched WITH credentials returns the signed
# XML. So in-app updates cannot work until the repo is public or the feed is hosted somewhere
# publicly readable. Same constraint that already disabled provenance attestation (#96).
#
# The old comment here said it "404s until the first release publishes appcast.xml", which was true
# and incomplete - two releases exist now and it still 404s.
SU_FEED_URL="${SU_FEED_URL:-https://github.com/EvanCNavarro/PushText/releases/latest/download/appcast.xml}"
# Sparkle EdDSA PUBLIC key - safe to commit, and REQUIRED before the first release: generate with
# Sparkle's generate_keys, which stores the private half in the login Keychain. Set below,
# and an empty value is checked below so a release cannot ship unsigned updates by accident.
# The EdDSA PUBLIC key that verifies Sparkle updates. Safe to commit - it is the public half.
#
# NOT newly generated, and generating one would have been the wrong move. Sparkle's own
# `generate_keys --help`: "You only need one signing key, no matter how many apps you embed Sparkle
# in", and "If a private key was already generated in your Keychain, that key will be used and not
# overridden." A key was already there, and `generate_keys -p` printed this value - byte-identical
# to the SUPublicEDKey that /Applications/TermTile.app already ships. Same developer, same machine,
# one key, exactly as Sparkle intends.
#
# The consequence worth stating: ONE private key now signs updates for two shipped products, so
# losing or leaking it affects both. That is Sparkle's recommended model, not an accident of this
# repo, and the alternative - a per-app key via `--account` - buys isolation at the cost of a second
# secret to protect. Revisit only if the two apps stop sharing an owner.
SU_PUBLIC_ED_KEY="${SU_PUBLIC_ED_KEY:-mIAUkTNj+kRPNqkAX1Z1EaqFqyLaFQ37pwEIGduj4Zs=}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Monotonic build number from commit count - never dots-stripped.
if [ -n "${PUSHTEXT_BUILD_NUMBER:-}" ]; then
	if [ "${GITHUB_ACTIONS:-false}" = "true" ]; then
		echo "PUSHTEXT_BUILD_NUMBER is local-only and cannot be used in GitHub Actions" >&2
		exit 1
	fi
	[[ "$PUSHTEXT_BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || {
		echo "PUSHTEXT_BUILD_NUMBER must be a positive integer (got: $PUSHTEXT_BUILD_NUMBER)" >&2
		exit 1
	}
	BUILD_NUMBER="$PUSHTEXT_BUILD_NUMBER"
else
	BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
fi

# Build, then locate the product via --show-bin-path - never a hardcoded path. The flag must ride
# the SAME -c invocation or it prints the debug dir.
swift build -c "$CONFIGURATION" --product "$APP_NAME" >&2
BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
BINARY="$BIN_DIR/$APP_NAME"
[ -x "$BINARY" ] || { echo "built binary not found at $BINARY" >&2; exit 1; }

APP="$DIST_DIR/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/$APP_NAME"

# Info.plist (heredoc -> plutil -lint gate).
#
# NSMicrophoneUsageDescription is required - the app records audio. Accessibility
# (AXIsProcessTrusted) needs no usage string. NSSpeechRecognitionUsageDescription is deliberately
# ABSENT: it gates the legacy SFSpeechRecognizer, and docs/research/01 found a shipping SpeechAnalyzer
# binary (yap, via Homebrew) doing live dictation with no Info.plist at all. Add it only if a real
# Tahoe run proves it is needed - Phase 1 test S2.
PLIST="$APP/Contents/Info.plist"
cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key><string>$APP_NAME</string>
	<key>CFBundleDisplayName</key><string>$APP_NAME</string>
	<key>CFBundleExecutable</key><string>$APP_NAME</string>
	<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>$SHORT_VERSION</string>
	<key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
	<key>LSMinimumSystemVersion</key><string>$MIN_SYSTEM_VERSION</string>
	<key>LSUIElement</key><true/>
	<key>NSPrincipalClass</key><string>NSApplication</string>
	<key>NSHighResolutionCapable</key><true/>
	<key>NSMicrophoneUsageDescription</key><string>PushText records audio only while you hold the dictation key, and transcribes it on this Mac.</string>
	<key>SUFeedURL</key><string>$SU_FEED_URL</string>
	<key>SUEnableAutomaticChecks</key><false/>
PLIST_EOF
if [ -n "$SU_PUBLIC_ED_KEY" ]; then
	printf '\t<key>SUPublicEDKey</key><string>%s</string>\n' "$SU_PUBLIC_ED_KEY" >> "$PLIST"
elif [ "${GITHUB_ACTIONS:-false}" = "true" ]; then
	echo "SU_PUBLIC_ED_KEY is empty - a release build must ship a Sparkle public key" >&2
	exit 1
else
	echo "build-app.sh: no SU_PUBLIC_ED_KEY set - local build, Sparkle updates will not verify" >&2
fi
printf '</dict>\n</plist>\n' >> "$PLIST"
plutil -lint "$PLIST" >&2

# Optional icon - a menu-bar app has no dock icon, so this is cosmetic. No-op when absent.
if [ -f "$ICON_SRC" ]; then
	ICONSET="$(mktemp -d)/AppIcon.iconset"; mkdir -p "$ICONSET"
	for sz in 16 32 128 256 512; do
		sips -z "$sz" "$sz" "$ICON_SRC" --out "$ICONSET/icon_${sz}x${sz}.png" >&2
		sips -z $((sz*2)) $((sz*2)) "$ICON_SRC" --out "$ICONSET/icon_${sz}x${sz}@2x.png" >&2
	done
	iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns" >&2
	/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$PLIST" >&2 || true
	cp "$ICON_SRC" "$APP/Contents/Resources/AppIcon.png" >&2
fi

# Embed Sparkle.framework - REQUIRED whenever the binary links Sparkle: a linked
# @rpath/Sparkle.framework with nothing in Contents/Frameworks dyld-crashes at launch.
# `ditto` preserves the framework's version symlinks.
SPARKLE_FRAMEWORK="$ROOT/Vendor/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
[ -d "$SPARKLE_FRAMEWORK" ] || "$ROOT/scripts/fetch-sparkle.sh" >&2
[ -d "$SPARKLE_FRAMEWORK" ] || { echo "Sparkle.framework missing (run scripts/fetch-sparkle.sh)" >&2; exit 1; }
FRAMEWORKS_DIR="$APP/Contents/Frameworks"
SPARKLE_DST="$FRAMEWORKS_DIR/Sparkle.framework"
SPARKLE_V="$SPARKLE_DST/Versions/B"
mkdir -p "$FRAMEWORKS_DIR"
ditto "$SPARKLE_FRAMEWORK" "$SPARKLE_DST"

# Signing identity. A STABLE keychain identity keeps the app's code identity constant across
# rebuilds, so macOS TCC grants survive. Ad-hoc ("-") gets a fresh cdhash every build and silently
# resets EVERY grant - with Microphone + Accessibility + PostEvent in play that means re-approving
# three prompts after every single build. Resolution order: explicit PUSHTEXT_SIGN_IDENTITY wins;
# else the local "PushText Dev Signing" identity if scripts/setup-dev-signing.sh has been run;
# else ad-hoc.
DEFAULT_DEV_IDENTITY="PushText Dev Signing"
if [ -n "${PUSHTEXT_SIGN_IDENTITY:-}" ]; then
	SIGN_IDENTITY="$PUSHTEXT_SIGN_IDENTITY"
# No -v: a self-signed dev identity is untrusted (CSSMERR_TP_NOT_TRUSTED) and -v hides it, which
# silently dropped us back to ad-hoc signing and reset every TCC grant on each build.
elif security find-identity -p codesigning 2>/dev/null | grep -q "$DEFAULT_DEV_IDENTITY"; then
	SIGN_IDENTITY="$DEFAULT_DEV_IDENTITY"
else
	SIGN_IDENTITY="-"
	echo "build-app.sh: WARNING - ad-hoc signing. TCC grants will reset on every rebuild." >&2
	echo "build-app.sh: run scripts/setup-dev-signing.sh once to fix this." >&2
fi
echo "build-app.sh: signing with identity: $SIGN_IDENTITY" >&2
xattr -cr "$APP"

DISABLE_LIBRARY_VALIDATION="${PUSHTEXT_DISABLE_LIBRARY_VALIDATION:-auto}"
case "$DISABLE_LIBRARY_VALIDATION" in
	auto)
		case "$SIGN_IDENTITY" in
			"Developer ID Application:"*) DISABLE_LIBRARY_VALIDATION=0 ;;
			*) DISABLE_LIBRARY_VALIDATION=1 ;;
		esac
		;;
	1|true|TRUE|yes|YES) DISABLE_LIBRARY_VALIDATION=1 ;;
	0|false|FALSE|no|NO) DISABLE_LIBRARY_VALIDATION=0 ;;
	*)
		echo "PUSHTEXT_DISABLE_LIBRARY_VALIDATION must be auto, 1, or 0 (got: $DISABLE_LIBRARY_VALIDATION)" >&2
		exit 1
		;;
esac

# Entitlements are ALWAYS written now, because we always sign with --options runtime and the
# hardened runtime REFUSES the microphone without an explicit entitlement. Measured, from tccd:
#
#   Prompting policy for hardened runtime; service: kTCCServiceMicrophone requires entitlement
#   com.apple.security.device.audio-input but it is missing
#
# The consequence is worse than a denial: TCC will not even PROMPT, so the app can never appear in
# System Settings > Privacy & Security > Microphone, and there is no manual way to add it there the
# way Accessibility allows. The app is then permanently unable to record with no user-visible cause.
ENTITLEMENTS="$APP/Contents/Resources/PushText.entitlements"
{
	echo '<?xml version="1.0" encoding="UTF-8"?>'
	echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
	echo '<plist version="1.0">'
	echo '<dict>'
	echo '	<key>com.apple.security.device.audio-input</key>'
	echo '	<true/>'
	if [ "$DISABLE_LIBRARY_VALIDATION" = "1" ]; then
		echo '	<key>com.apple.security.cs.disable-library-validation</key>'
		echo '	<true/>'
	fi
	echo '</dict>'
	echo '</plist>'
} > "$ENTITLEMENTS"
plutil -lint "$ENTITLEMENTS" >&2
if [ "$DISABLE_LIBRARY_VALIDATION" = "1" ]; then
	echo "build-app.sh: disabling library validation for local embedded Sparkle load" >&2
else
	echo "build-app.sh: keeping hardened-runtime library validation enabled" >&2
fi

sign_code() {
	codesign --force --options runtime --sign "$SIGN_IDENTITY" "$1" >&2
}
sign_app_code() {
	if [ -n "$ENTITLEMENTS" ]; then
		codesign --force --options runtime --entitlements "$ENTITLEMENTS" --sign "$SIGN_IDENTITY" "$1" >&2
	else
		codesign --force --options runtime --sign "$SIGN_IDENTITY" "$1" >&2
	fi
}

# Inside-out: deepest nested Sparkle code FIRST, then the framework, then the app binary, then the
# bundle. NO --deep on any sign operation.
sign_code "$SPARKLE_V/XPCServices/Downloader.xpc"
sign_code "$SPARKLE_V/XPCServices/Installer.xpc"
sign_code "$SPARKLE_V/Autoupdate"
sign_code "$SPARKLE_V/Updater.app"
sign_code "$SPARKLE_DST"
sign_app_code "$APP/Contents/MacOS/$APP_NAME"
sign_app_code "$APP"
# --deep --strict is VERIFY-only and is correct here; it is the sign path that must never see --deep.
codesign --verify --deep --strict "$APP" >&2

# Last stdout line = the .app path, so callers can `tail -1`.
echo "$APP"
