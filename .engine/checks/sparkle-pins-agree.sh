#!/usr/bin/env bash
# Sparkle is pinned in TWO files and they must name the same version.
#
#   scripts/fetch-sparkle.sh      the framework the app links and ships
#   .github/workflows/release.yml the generate_appcast CLI that SIGNS the appcast
#
# Nothing derives one from the other. Bump only the first and the release signs its appcast with a
# different Sparkle than the app runs; bump only the second and the shipped framework silently stays
# behind - which is how 2.9.3 sat here through two upstream security releases with every gate green.
#
# NO DEPENDENCY TOOL COVERS THIS. Sparkle arrives as a local binaryTarget with no manifest and no
# lockfile, so Dependabot cannot see it even with its `swift` ecosystem enabled. This file is the
# only thing in the repo that will notice the two halves drifting apart.
#
# It deliberately does NOT check that the pin is CURRENT. That would need a network call on every
# run and would go red the moment upstream released, turning a correctness gate into a nag - and a
# gate nobody can satisfy on the spot is a gate that gets ignored.
set -euo pipefail
cd "$(dirname "$0")/../.."

FETCH="scripts/fetch-sparkle.sh"
RELEASE=".github/workflows/release.yml"

# Anchored at line start so the version named in a comment cannot answer for the real assignment.
#
# `|| true` because grep exits 1 when it matches nothing, and under `set -e` that killed the script
# AT THIS LINE - exit 1 with no output at all. Found by running this against the pre-change tree,
# which has no SPARKLE_CLI_VERSION: it failed closed, correctly, and said nothing about why. The
# missing-pin branch below is the message that was being skipped.
FRAMEWORK_VERSION="$(grep -E '^SPARKLE_VERSION=' "$FETCH" | head -1 | cut -d'"' -f2 || true)"
CLI_VERSION="$(grep -E '^[[:space:]]*SPARKLE_CLI_VERSION=' "$RELEASE" | head -1 | cut -d'"' -f2 || true)"

# An unreadable pin must never look like agreement: two empty strings are equal.
if [ -z "$FRAMEWORK_VERSION" ] || [ -z "$CLI_VERSION" ]; then
	echo "sparkle-pins-agree: FAIL - could not read a pin" >&2
	echo "  $FETCH   SPARKLE_VERSION='$FRAMEWORK_VERSION'" >&2
	echo "  $RELEASE SPARKLE_CLI_VERSION='$CLI_VERSION'" >&2
	exit 1
fi

if [ "$FRAMEWORK_VERSION" != "$CLI_VERSION" ]; then
	echo "sparkle-pins-agree: FAIL - the two Sparkle pins disagree" >&2
	echo "  $FETCH   framework $FRAMEWORK_VERSION" >&2
	echo "  $RELEASE CLI       $CLI_VERSION" >&2
	echo "" >&2
	echo "Bump both, and update the sha256 beside each - a stale digest fails closed." >&2
	exit 1
fi

# The digests are what make the pins mean anything; a pin without one is a version number, not an
# integrity check.
for pair in "$FETCH:SPARKLE_SHA256" "$RELEASE:SPARKLE_CLI_SHA256"; do
	file="${pair%%:*}"; var="${pair##*:}"
	digest="$(grep -E "^[[:space:]]*$var=" "$file" | head -1 | cut -d'"' -f2 || true)"
	if ! printf '%s' "$digest" | grep -qE '^[0-9a-f]{64}$'; then
		echo "sparkle-pins-agree: FAIL - $file has no usable $var (got '$digest')" >&2
		exit 1
	fi
done

echo "sparkle-pins-agree: ok - both pins at $FRAMEWORK_VERSION, both digests present"
