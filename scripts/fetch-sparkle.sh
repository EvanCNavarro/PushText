#!/usr/bin/env bash
# Vendors Sparkle.xcframework into Vendor/ (gitignored). Sparkle is referenced as a local
# binaryTarget because SPM's remote binary-artifact downloader hangs in some sandboxes, while a
# plain download works. Run this once after cloning (the app build script also invokes it).
#
# THE VERSION IS PINNED IN TWO PLACES and they must move together: here, for the framework the app
# links, and in .github/workflows/release.yml, for the generate_appcast CLI. Nothing derives one from
# the other, so a bump that touches only one leaves the release signing its appcast with a different
# Sparkle than the app runs.
#
# NOT VISIBLE TO ANY DEPENDENCY TOOL. Sparkle arrives as a local binaryTarget, so there is no
# manifest and no lockfile for Dependabot to read - enabling its `swift` ecosystem would not surface
# this and never will. The only thing that notices a new Sparkle is someone looking, which is why
# the version and its digest are written here in full rather than resolved at run time.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

SPARKLE_VERSION="2.9.6"
# sha256 of Sparkle-for-Swift-Package-Manager.zip for the version above, read off the downloaded
# file. Update BOTH lines together; a stale digest fails closed and says so.
SPARKLE_SHA256="8d5fb41d960b43f4a68aa14126bf62b098544ec8d191cdcc73eb14e63a8e7606"

DEST="$PROJECT_DIR/Vendor/Sparkle.xcframework"
PLIST="$DEST/macos-arm64_x86_64/Sparkle.framework/Resources/Info.plist"

# WHAT IS ON DISK DECIDES, NOT WHETHER THE DIRECTORY EXISTS. The old guard was `[ -d "$DEST" ] &&
# exit 0`, so bumping the version above changed nothing on a machine that had already vendored the
# previous one: CI got the new framework from a fresh checkout (Vendor/ is gitignored) and a
# developer kept the old one, silently, with no output saying so.
if [ -d "$DEST" ]; then
	HAVE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST" 2>/dev/null || echo unknown)"
	if [ "$HAVE" = "$SPARKLE_VERSION" ]; then
		echo "Sparkle $HAVE already vendored at $DEST"
		exit 0
	fi
	# NOT removed here. The first version of this script deleted the old framework at this point and
	# only then downloaded the new one, so a mismatched digest or a dropped connection left the
	# machine with NO Sparkle - a working checkout broken by a failed upgrade. Caught by planting a
	# wrong digest, which printed the refusal correctly and destroyed the vendor anyway.
	# The replacement happens after verification, at the bottom.
	echo "Vendored Sparkle is $HAVE, pin is $SPARKLE_VERSION - refetching"
fi

URL="https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-for-Swift-Package-Manager.zip"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
echo "Fetching Sparkle ${SPARKLE_VERSION}..."
curl -fsSL --max-time 180 "$URL" -o "$WORK/spm.zip"

# THE VERSION WAS PINNED AND THE BYTES WERE NOT. HTTPS to a GitHub release is a reasonable trust
# anchor and it is not an integrity check: it says the transport was not tampered with, never that
# the artifact is the one this project was built and tested against. Sparkle installs code on the
# user's machine, so it is the last dependency to take on trust.
GOT="$(shasum -a 256 "$WORK/spm.zip" | cut -d' ' -f1)"
if [ "$GOT" != "$SPARKLE_SHA256" ]; then
	echo "fetch-sparkle: REFUSING to vendor - sha256 mismatch for Sparkle ${SPARKLE_VERSION}" >&2
	echo "  expected $SPARKLE_SHA256" >&2
	echo "  got      $GOT" >&2
	echo "Either the pin was bumped without its digest, or the artifact is not what we expect." >&2
	exit 1
fi
echo "sha256 ok: $GOT"

unzip -q "$WORK/spm.zip" -d "$WORK/x"
STAGED="$(find "$WORK/x" -maxdepth 2 -name Sparkle.xcframework -type d | head -1)"
[ -n "$STAGED" ] || { echo "fetch-sparkle: no Sparkle.xcframework inside the archive" >&2; exit 1; }

# The archive is what the digest covered; this asserts the thing that came OUT of it is the version
# asked for, so a reorganised upstream archive cannot quietly vendor something else. Checked while
# still STAGED in the temp dir, so a wrong answer costs nothing that is already on disk.
LANDED="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
	"$STAGED/macos-arm64_x86_64/Sparkle.framework/Resources/Info.plist" 2>/dev/null || echo unknown)"
if [ "$LANDED" != "$SPARKLE_VERSION" ]; then
	echo "fetch-sparkle: unpacked framework reports $LANDED, expected $SPARKLE_VERSION" >&2
	exit 1
fi

# ONLY NOW is anything existing touched. Everything above can fail without leaving the checkout
# worse than it started.
mkdir -p "$PROJECT_DIR/Vendor"
rm -rf "$DEST"
cp -R "$STAGED" "$DEST"
echo "Vendored Sparkle $LANDED -> $DEST"
