#!/usr/bin/env bash
# Fail-closed guard: every task id in .engine/BACKLOG.md must resolve to a real GitHub issue.
#
# WHY. These ids began as file-local task numbers and stayed that way after the repo gained a GitHub
# remote, at which point `#19` silently became a claim about GitHub issue 19. Three merged PR bodies
# shipped literal `Closes #19` - auto-close syntax aimed at nothing. A citation that resolves to
# nothing reads as diligence and sends the reader somewhere empty.
#
# SCOPE. Ids >= 4 only. #1..#3 predate the migration and collide with PR numbers 1..3; they are DONE
# and are documented as never-cite-bare rather than retro-filed, because inventing issues for
# finished work to satisfy a checker is the fabrication this guard exists to prevent.
#
# FAIL-OPEN ON INFRASTRUCTURE ABSENCE ONLY - no `gh`, no auth, no network. A developer offline must
# not be blocked; an unresolvable id must never pass silently. It says so on stderr either way.
set -uo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
backlog="$root/.engine/BACKLOG.md"

[ -f "$backlog" ] || { echo "backlog-ids-resolve: no BACKLOG.md - nothing to check"; exit 0; }

if ! command -v gh >/dev/null 2>&1; then
	echo "backlog-ids-resolve: SKIPPED - gh not installed (cannot verify ids)" >&2
	exit 0
fi
if ! gh auth status >/dev/null 2>&1; then
	echo "backlog-ids-resolve: SKIPPED - gh not authenticated (cannot verify ids)" >&2
	exit 0
fi

existing="$(gh issue list --state all --limit 200 --json number --jq '.[].number' 2>/dev/null)"
if [ -z "$existing" ]; then
	echo "backlog-ids-resolve: SKIPPED - could not list issues (network or permissions)" >&2
	exit 0
fi

missing=""
while read -r id; do
	[ -z "$id" ] && continue
	[ "$id" -lt 4 ] && continue
	if ! printf '%s\n' "$existing" | grep -qx "$id"; then
		missing="$missing $id"
	fi
done < <(grep -oE '^#[0-9]+' "$backlog" | tr -d '#')

if [ -n "$missing" ]; then
	echo "backlog-ids-resolve: FAIL - backlog ids with no GitHub issue:$missing" >&2
	echo "  File them (gh issue create) so every citation resolves, or remove the entry." >&2
	exit 1
fi
echo "backlog-ids-resolve: OK (all ids >= 4 resolve to issues)"
exit 0
