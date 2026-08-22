#!/usr/bin/env bash
# Fail-closed: cycle_close.py reads cwc.config.json at project root (NOT .engine/config.json).
# Without it, the Row-8 PROVE gate is blind to Swift live surfaces and closes cycles on "N/A".
# Exit non-zero iff the config is missing or lacks a Sources/**.swift subprocess glob.
set -u
root="$(cd "$(dirname "$0")/../.." && pwd)"
cfg="$root/cwc.config.json"
[ -f "$cfg" ] || { echo "FAIL: cwc.config.json missing at project root (Row-8 PROVE gate blind)"; exit 1; }
grep -q 'Sources/\*\*/\*\.swift' "$cfg" || { echo "FAIL: cwc.config.json lacks Sources/**/*.swift subprocess glob"; exit 1; }
exit 0
