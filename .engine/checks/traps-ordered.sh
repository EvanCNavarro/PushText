#!/usr/bin/env bash
# TRAP-7 gate: trap headings in .engine/traps.md must appear in ascending numeric
# order (new traps are appended, never inserted mid-file). Exit 1 iff out of order.
set -uo pipefail
cd "$(dirname "$0")/../.."

nums=$(grep -oE '^### TRAP-[0-9]+' .engine/traps.md | grep -oE '[0-9]+')
sorted=$(printf '%s\n' "$nums" | sort -n)

if [ "$nums" != "$sorted" ]; then
    echo "TRAP-7 violation: trap headings out of numeric order in .engine/traps.md:" >&2
    printf 'found:  %s\n' "$(echo $nums)" >&2
    printf 'expect: %s\n' "$(echo $sorted)" >&2
    exit 1
fi
exit 0
