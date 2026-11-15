#!/bin/bash
# Wait in the foreground for a background shell task to finish, by watching the output file
# the shell tool named when it backgrounded the command ("Output is being written to: <file>").
# For a sub-agent that must not end its turn while its own command runs: a named Claude Code
# sub-agent is never woken by that command's completion.
#
# Usage: wait-task-output.sh <output-file> [max-seconds]     (default 100, under the shell tool's
# default 120s timeout, so the wait itself never gets backgrounded; short, so a message from the
# lead is read within two minutes)
# Prints one JSON line and exits 0:
#   {"file":"…","status":"done","exit_code":N}     the command exited
#   {"file":"…","status":"killed"}                 the command was stopped
#   {"file":"…","status":"running","waited":N}     still running at max-seconds: call again
# Exits 1 on bad input (missing file, bad max-seconds).
# Env (tests): WAIT_TASK_POLL_SECONDS sets the poll interval (default 5).

set -e

file=${1:?usage: wait-task-output.sh <output-file> [max-seconds]}
max=${2:-100}
case "$max" in ''|*[!0-9]*) echo "wait-task-output: max-seconds must be a whole number: $max" >&2; exit 1 ;; esac
[ -f "$file" ] || { echo "wait-task-output: no such output file: $file" >&2; exit 1; }
poll=${WAIT_TASK_POLL_SECONDS:-5}

start=$(date +%s)
echo "wait-task-output: waiting up to ${max}s for $file to finish" >&2
while :; do
  code=$(grep -E '^\[exited with code -?[0-9]+\]$' "$file" 2>/dev/null | tail -1 | sed -E 's/^\[exited with code (-?[0-9]+)\]$/\1/')
  if [ -n "$code" ]; then
    jq -cn --arg f "$file" --argjson c "$code" '{file:$f,status:"done",exit_code:$c}'
    exit 0
  fi
  if grep -qxF '[killed]' "$file" 2>/dev/null; then
    jq -cn --arg f "$file" '{file:$f,status:"killed"}'
    exit 0
  fi
  waited=$(( $(date +%s) - start ))
  if [ "$waited" -ge "$max" ]; then
    jq -cn --arg f "$file" --argjson w "$waited" '{file:$f,status:"running",waited:$w}'
    exit 0
  fi
  sleep "$poll"
done
