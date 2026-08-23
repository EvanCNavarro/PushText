#!/usr/bin/env bash
# The macOS floor is declared in FOUR places that must agree (#16), and only one of them is
# checked by an ordinary build:
#
#   1. Package.swift            .macOS(.vNN)         - the build floor
#   2. scripts/build-app.sh     MIN_SYSTEM_VERSION   - Info.plist LSMinimumSystemVersion
#   3. .github/workflows/check.yml    runs-on:       - the PR gate
#   4. .github/workflows/release.yml  runs-on:       - the tag gate
#
# Why a gate rather than a comment: a runner older than the floor cannot resolve the manifest AT
# ALL, and release.yml fires only on a tag - so that break surfaces at the first release, not in
# the PR that caused it. And an LSMinimumSystemVersion BELOW the floor is worse than a wrong
# number: Gatekeeper lets the app launch on an OS where SpeechAnalyzer does not exist, moving the
# failure off the installer and onto the user.
#
# Deliberately NOT a numeric >= comparison. These must be EQUAL: a runner newer than the floor is
# fine for compiling but would stop proving the floor is actually buildable, which is the property
# the macos-26 job was added to establish.
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0

floor="$(sed -n 's/^[[:space:]]*\.macOS(\.v\([0-9][0-9]*\)).*$/\1/p' "$root/Package.swift" | head -1)"
if [ -z "$floor" ]; then
    echo "platform-floor: could not read .macOS(.vNN) from Package.swift" >&2
    exit 1
fi
echo "platform-floor: Package.swift floor = macOS $floor"

min="$(sed -n 's/^MIN_SYSTEM_VERSION="\${MIN_SYSTEM_VERSION:-\([0-9.]*\)}".*$/\1/p' "$root/scripts/build-app.sh" | head -1)"
if [ -z "$min" ]; then
    echo "platform-floor: could not read MIN_SYSTEM_VERSION from scripts/build-app.sh" >&2
    exit 1
fi
if [ "$min" != "$floor.0" ]; then
    echo "platform-floor: build-app.sh MIN_SYSTEM_VERSION=$min but the floor is $floor.0" >&2
    fail=1
fi

for wf in check release; do
    file="$root/.github/workflows/$wf.yml"
    [ -f "$file" ] || continue
    # Every runner in the file, not just the first: check.yml has more than one job.
    bad="$(sed -n 's/^[[:space:]]*runs-on:[[:space:]]*\(macos-[0-9][0-9.]*\).*$/\1/p' "$file" \
           | grep -v "^macos-$floor$" || true)"
    if [ -n "$bad" ]; then
        echo "platform-floor: $wf.yml runs on $(echo "$bad" | tr '\n' ' ')but the floor is macOS $floor" >&2
        fail=1
    fi
done

if [ "$fail" -ne 0 ]; then
    echo "platform-floor: the floor moved in one place and not the others (#16)" >&2
    exit 1
fi
echo "platform-floor: Package.swift, build-app.sh and the workflow runners all agree"
exit 0
