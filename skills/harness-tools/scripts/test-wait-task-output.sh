#!/bin/bash
# Offline test for wait-task-output.sh with a 1-second poll.
# Usage: test-wait-task-output.sh    (prints one "ok <case>" line per case; exits 1 on the first failure)

set -e

here=$(cd "$(dirname "$0")" && pwd)
script="$here/wait-task-output.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export WAIT_TASK_POLL_SECONDS=1

fail() { echo "FAIL $1" >&2; [ ! -f "$T/err" ] || sed 's/^/  stderr: /' "$T/err" >&2; exit 1; }
eq() { [ "$2" = "$3" ] || fail "$1: got '$2', want '$3'"; }

# finished before the call: returns at once with the exit code
printf 'line\n{"tool":"pest","result":"failed"}\n\n[exited with code 2]\n' > "$T/done.output"
out=$(bash "$script" "$T/done.output" 5 2>"$T/err") || fail "done: exit $?"
eq "done status" "$(printf '%s' "$out" | jq -r .status)" done
eq "done code" "$(printf '%s' "$out" | jq -r .exit_code)" 2
echo "ok finished task returns its exit code"

# finishes while waiting: returns once the marker lands, before max-seconds
printf 'running\n' > "$T/late.output"
( sleep 2; printf '\n[exited with code 0]\n' >> "$T/late.output" ) &
start=$(date +%s)
out=$(bash "$script" "$T/late.output" 20 2>"$T/err") || fail "late: exit $?"
wait
eq "late status" "$(printf '%s' "$out" | jq -r .status)" done
eq "late code" "$(printf '%s' "$out" | jq -r .exit_code)" 0
[ $(( $(date +%s) - start )) -lt 10 ] || fail "late: did not return when the marker landed"
echo "ok task finishing mid-wait returns promptly"

# killed task
printf 'output\n\n[killed]\n' > "$T/killed.output"
out=$(bash "$script" "$T/killed.output" 5 2>"$T/err") || fail "killed: exit $?"
eq "killed status" "$(printf '%s' "$out" | jq -r .status)" killed
echo "ok killed task reports killed"

# a line that only mentions the marker mid-text does not count
printf 'echo "[exited with code 0]" in a log line\n' > "$T/mention.output"
out=$(bash "$script" "$T/mention.output" 2 2>"$T/err") || fail "mention: exit $?"
eq "mention status" "$(printf '%s' "$out" | jq -r .status)" running
echo "ok marker must be its own line"

# still running at max-seconds: reports running so the caller waits again
printf 'running\n' > "$T/slow.output"
out=$(bash "$script" "$T/slow.output" 2 2>"$T/err") || fail "slow: exit $?"
eq "slow status" "$(printf '%s' "$out" | jq -r .status)" running
[ "$(printf '%s' "$out" | jq -r .waited)" -ge 2 ] || fail "slow: waited less than max-seconds"
echo "ok still-running task reports running at max-seconds"

# bad input exits 1
if bash "$script" "$T/missing.output" 2>"$T/err"; then fail "missing file accepted"; fi
if bash "$script" "$T/done.output" 9x 2>"$T/err"; then fail "bad max-seconds accepted"; fi
echo "ok bad input exits 1"
