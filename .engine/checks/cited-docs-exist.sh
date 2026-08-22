#!/usr/bin/env bash
# Fail-closed guard: every docs/ path cited in .engine/ must actually exist.
#
# WHY. The issue-5 commit, its PR body and BACKLOG.md all cited
# docs/verification/task5-injection.md while the file did not exist: a PreToolUse hook blocked the
# compound command that would have written it, and a blocked command runs NONE of its parts - but
# the citation had already been drafted. A path that resolves to nothing reads as evidence and sends
# the reader somewhere empty, exactly like a fabricated issue number.
set -uo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"

missing=""
while read -r path; do
	[ -z "$path" ] && continue
	[ -e "$path" ] || missing="$missing $path"
done < <(grep -rhoE 'docs/[A-Za-z0-9_/.-]+\.(md|png|log|txt)' .engine/ 2>/dev/null | sort -u)

if [ -n "$missing" ]; then
	echo "cited-docs-exist: FAIL - .engine/ cites paths that do not exist:$missing" >&2
	echo "  Write the file, or remove the citation. A dangling path reads as evidence." >&2
	exit 1
fi
echo "cited-docs-exist: OK (every docs/ path cited in .engine/ resolves)"
exit 0
