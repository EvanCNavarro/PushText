#!/usr/bin/env bash
# Runs `swift test` and, when it WEDGES (#144), samples the process before killing it.
#
# WHY THIS EXISTS. Roughly one CI run in ten never finishes the suite: every suite announces itself
# and NONE completes, against a healthy baseline of 70-140 seconds. Both earlier observations were
# cancelled by hand at ~15 minutes, so two things were never established - whether the process is
# hung or dead, and what it is waiting on. "started 192, completed 0" is exactly where the last two
# investigations stopped.
#
# A bare `swift test` cannot answer that. With no `timeout-minutes` the job default is SIX HOURS, so
# in practice a human cancels it, and a cancellation uploads no diagnostics.
#
# So: bound it, and SAMPLE BEFORE KILLING. The sample is the entire point of this script - a stack
# says whether it is blocked on a lock, a socket, or a launchd handshake. Without it this would just
# be a faster way to learn nothing.
set -uo pipefail

limit="${PUSHTEXT_TEST_TIMEOUT_SECONDS:-600}"
work="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
log="$work/swift-test.log"
: >"$log"

swift test >"$log" 2>&1 &
test_pid=$!

# Stream, so a healthy run still shows its progress in the CI log rather than going silent for two
# minutes and then printing everything at once.
tail -f "$log" 2>/dev/null &
tail_pid=$!
cleanup_tail() { kill "$tail_pid" 2>/dev/null; wait "$tail_pid" 2>/dev/null; }

deadline=$((SECONDS + limit))
while kill -0 "$test_pid" 2>/dev/null; do
	if [ "$SECONDS" -ge "$deadline" ]; then
		sleep 1   # let tail flush what it has
		cleanup_tail
		echo ""
		echo "=============================================================="
		echo "#144 REPRODUCED: swift test exceeded ${limit}s and was killed."
		echo "=============================================================="
		echo "--- last 40 lines of output ---"
		tail -40 "$log"
		echo "--- process tree ---"
		ps -Ao pid,ppid,stat,etime,command | grep -E 'swift|xctest|PushText' | grep -v grep
		# Sample every candidate: which process holds the wedge is precisely what is unknown.
		for pid in $(pgrep -f 'xctest|PushTextPackageTests|swift-testing|swift-build' 2>/dev/null); do
			echo "--- sample $pid ---"
			if /usr/bin/sample "$pid" 5 -file "$work/sample-$pid.txt" >/dev/null 2>&1; then
				sed -n '1,120p' "$work/sample-$pid.txt"
			else
				echo "  sample failed for $pid"
			fi
		done
		kill -9 "$test_pid" 2>/dev/null
		exit 124
	fi
	sleep 5
done

wait "$test_pid"
status=$?
sleep 1
cleanup_tail
exit "$status"
