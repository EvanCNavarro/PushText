#!/usr/bin/env bash
# TRAP-18 fail-closed guard: shell scripts must be pure ASCII.
#
# A non-ASCII byte (arrow, em-dash, smart quote) glued to a `$var` under `set -u` in a UTF-8 locale
# makes Bash fold the byte into the identifier -> "unbound variable" at RUN time, invisible to any
# text-invariant test. Keep scripts/*.sh 7-bit ASCII; use ${var} braces + ASCII (-> , --).
#
# Exit non-zero iff any scripts/*.sh contains a byte > 0x7F. Uses perl (always present on macOS);
# BSD grep has no -P.
set -euo pipefail
export LC_ALL=C
export LANG=C
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

shopt -s nullglob
offenders=0
for f in scripts/*.sh; do
	if perl -ne 'exit 1 if /[^\x00-\x7F]/' "$f"; then
		: # clean
	else
		echo "FAIL: non-ASCII byte in $f (TRAP-18: breaks \$var under set -u)" >&2
		perl -ne 'print "  line $.: $_" if /[^\x00-\x7F]/' "$f" >&2 || true
		offenders=$((offenders+1))
	fi
done

if [ "$offenders" -gt 0 ]; then
	exit 1
fi
echo "scripts-ascii-only: OK ($(ls scripts/*.sh 2>/dev/null | wc -l | tr -d ' ') scripts pure ASCII)"
