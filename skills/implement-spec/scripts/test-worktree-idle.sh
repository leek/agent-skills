#!/bin/bash
# Offline test for worktree-idle.sh with a 3-second limit and a 1-second poll.
# Usage: test-worktree-idle.sh    (prints one "ok <case>" line per case; exits 1 on the first failure)

set -e

here=$(cd "$(dirname "$0")" && pwd)
script="$here/worktree-idle.sh"
T=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$T"' EXIT
export WORKTREE_IDLE_LIMIT_SECONDS=3 WORKTREE_IDLE_POLL_SECONDS=1

fail() { echo "FAIL $1" >&2; [ ! -f "$T/err" ] || sed 's/^/  stderr: /' "$T/err" >&2; exit 1; }
eq() { [ "$2" = "$3" ] || fail "$1: got '$2', want '$3'"; }

# untouched worktree: alarms once the limit passes
mkdir "$T/quiet"
start=$(date +%s)
out=$(bash "$script" "$T/quiet" 2>"$T/err") || fail "quiet: exit $?"
eq "quiet status" "$(printf '%s' "$out" | jq -r .status)" idle
eq "quiet worktree" "$(printf '%s' "$out" | jq -r .worktree)" "$T/quiet"
[ $(( $(date +%s) - start )) -ge 3 ] || fail "quiet: alarmed before the limit"
echo "ok quiet worktree alarms after the limit"

# a worktree written every second for 5 seconds: no alarm until the writes stop
mkdir "$T/busy"
( for i in 1 2 3 4 5; do echo "$i" > "$T/busy/f$i"; sleep 1; done ) &
writer=$!
start=$(date +%s)
out=$(bash "$script" "$T/busy" 2>"$T/err") || fail "busy: exit $?"
wait "$writer"
eq "busy status" "$(printf '%s' "$out" | jq -r .status)" idle
[ $(( $(date +%s) - start )) -ge 7 ] || fail "busy: alarmed while files were still changing"
echo "ok steady writes hold the alarm off"

# writes under .git only: still idle
mkdir -p "$T/gitonly/.git"
( for i in 1 2 3 4 5; do echo "$i" > "$T/gitonly/.git/f$i"; sleep 1; done ) &
writer=$!
start=$(date +%s)
out=$(bash "$script" "$T/gitonly" 2>"$T/err") || fail "gitonly: exit $?"
wait "$writer"
[ $(( $(date +%s) - start )) -lt 6 ] || fail "gitonly: .git writes held the alarm off"
echo "ok .git writes are ignored"

# worktree removed mid-watch: reports gone
mkdir "$T/gone"
( sleep 1; rm -rf "$T/gone" ) &
out=$(bash "$script" "$T/gone" 2>"$T/err") || fail "gone: exit $?"
wait
eq "gone status" "$(printf '%s' "$out" | jq -r .status)" gone
echo "ok removed worktree reports gone"

# bad input exits 1
if bash "$script" "$T/missing" 2>"$T/err"; then fail "missing dir accepted"; fi
if bash "$script" "$T/quiet" 2x 2>"$T/err"; then fail "bad minutes accepted"; fi
echo "ok bad input exits 1"
