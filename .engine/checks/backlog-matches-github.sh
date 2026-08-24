#!/usr/bin/env bash
# Fail-closed guard: .engine/BACKLOG.md must agree with GitHub about every task it lists.
#
# BACKLOG.md states the contract itself - "GitHub is the STATE authority (open/closed); this file is
# the narrative record ... when they disagree, GitHub is right about state and this file is right
# about why." This gate is that sentence, executed.
#
# TWO ASSERTIONS.
#
#   1. RESOLVE (was backlog-ids-resolve.sh). Every id >= 4 names a real issue. These ids began as
#      file-local task numbers and stayed that way after the repo gained a GitHub remote, at which
#      point `#19` silently became a claim about GitHub issue 19. Three merged PR bodies shipped
#      literal `Closes #19` - auto-close syntax aimed at nothing. A citation that resolves to
#      nothing reads as diligence and sends the reader somewhere empty.
#
#   2. STATE. The taxonomy suffix must agree with the issue: `DONE` <-> closed, `S0|S1|S2` <-> open.
#      Added 2026-08-23 after SIX entries were found describing finished work as pending - #7, #10,
#      #17, #18, #32, #36 - including one whose stated premise the work had disproved. "What's next"
#      gets chosen off this file, so a stale entry does not merely age, it misdirects.
#
# ONE ASYMMETRY, AND IT IS DELIBERATE. Only `closed on GitHub, still marked S0` FAILS. The mirror
# case - `marked DONE, still open` - is reported and passes, because an issue closes at the MERGE.
# A PR that correctly marks its line DONE would otherwise be red before the merge and the branch
# would be red after it: green in neither state, which is a gate nobody can satisfy. Warning on the
# transient direction and failing on the durable one keeps it satisfiable without letting the lie
# through.
#
# COVERAGE IS A WARNING, NOT A FAILURE. An open issue absent from this file is incompleteness, not a
# false statement, and GitHub already tracks it. Failing here would turn every `gh issue create` into
# an instantly red branch - and a gate that fires on something nobody is going to fix on the spot is
# a gate that gets ignored, which is worse than no gate.
#
# SCOPE. Ids >= 4 only. #1..#3 predate the migration and collide with PR numbers 1..3; they are DONE
# and are documented as never-cite-bare rather than retro-filed, because inventing issues for
# finished work to satisfy a checker is the fabrication this guard exists to prevent.
#
# FAIL-OPEN ON INFRASTRUCTURE ABSENCE ONLY - no `gh`, no auth, no network. A developer offline must
# not be blocked; a disagreement must never pass silently. It says so on stderr either way.
set -uo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
backlog="$root/.engine/BACKLOG.md"

[ -f "$backlog" ] || { echo "backlog-matches-github: no BACKLOG.md - nothing to check"; exit 0; }

if ! command -v gh >/dev/null 2>&1; then
	echo "backlog-matches-github: SKIPPED - gh not installed (cannot verify)" >&2
	exit 0
fi
if ! gh auth status >/dev/null 2>&1; then
	echo "backlog-matches-github: SKIPPED - gh not authenticated (cannot verify)" >&2
	exit 0
fi

# number<TAB>state, one issue per line. Fetched once: a per-entry `gh issue view` is ~30 round trips.
issues="$(gh issue list --state all --limit 300 --json number,state \
	--jq '.[] | "\(.number)\t\(.state)"' 2>/dev/null)"
if [ -z "$issues" ]; then
	echo "backlog-matches-github: SKIPPED - could not list issues (network or permissions)" >&2
	exit 0
fi

missing=""
stale=""
early=""
listed=""

while IFS= read -r header; do
	[ -z "$header" ] && continue
	id="$(printf '%s' "$header" | sed -E 's/^#([0-9]+) - .*/\1/')"
	[ "$id" -lt 4 ] && continue
	listed="$listed $id"
	state="$(printf '%s\n' "$issues" | awk -F'\t' -v n="$id" '$1 == n { print $2 }')"
	if [ -z "$state" ]; then
		missing="$missing $id"
		continue
	fi
	# Taxonomy suffix: `- DONE` closes the line; `- S0|S1|S2` leaves it pending.
	if printf '%s' "$header" | grep -qE ' - DONE$'; then marked=DONE; else marked=OPEN; fi
	if [ "$state" = "CLOSED" ] && [ "$marked" = "OPEN" ]; then
		stale="$stale $id"
	elif [ "$state" = "OPEN" ] && [ "$marked" = "DONE" ]; then
		early="$early $id"
	fi
done < <(grep -E '^#[0-9]+ - ' "$backlog")

uncovered=""
while IFS=$'\t' read -r num st; do
	[ "$st" = "OPEN" ] || continue
	[ "$num" -lt 4 ] && continue
	printf '%s ' $listed | grep -qE "(^| )$num( |$)" || uncovered="$uncovered $num"
done <<< "$issues"

[ -n "$early" ] && echo "backlog-matches-github: NOTE - marked DONE but still open (fine mid-PR):$early" >&2
[ -n "$uncovered" ] && echo "backlog-matches-github: NOTE - open issues not listed here:$uncovered" >&2

fail=0
if [ -n "$missing" ]; then
	echo "backlog-matches-github: FAIL - backlog ids with no GitHub issue:$missing" >&2
	echo "  File them (gh issue create) so every citation resolves, or remove the entry." >&2
	fail=1
fi
if [ -n "$stale" ]; then
	echo "backlog-matches-github: FAIL - closed on GitHub, still pending here:$stale" >&2
	echo "  Mark each ' - DONE' and write what was actually delivered. GitHub owns state." >&2
	fail=1
fi
[ "$fail" -eq 1 ] && exit 1

if [ -n "$early" ] || [ -n "$uncovered" ]; then
	# Say OK without claiming agreement the NOTEs above just contradicted.
	echo "backlog-matches-github: OK - no failing disagreement (see NOTEs above)"
else
	echo "backlog-matches-github: OK (ids >= 4 resolve, and every marker agrees with GitHub)"
fi
exit 0
