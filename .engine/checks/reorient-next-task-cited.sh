#!/bin/bash
# TRAP-10: gate parsers read only the first physical line - every "Next task:" line in
# reorient.md must carry its "←" source citation ON THAT LINE. Exit non-zero iff a
# Next-task line lacks one. Absent file/lines = pass (nothing to violate).
set -u
FILE="$(dirname "$0")/../state/reorient.md"
[ -f "$FILE" ] || exit 0
BAD=$(grep -n "^Next task:" "$FILE" | grep -v "←" || true)
if [ -n "$BAD" ]; then
  echo "TRAP-10 violation: Next-task line(s) missing same-line ← citation:"
  echo "$BAD"
  exit 1
fi
exit 0
