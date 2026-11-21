#!/bin/bash
# Offline test for wait-until.sh: the three verdicts and the usage-error exit, which must not
# collide with them (2 is "failed", 3 is "timeout"). Fast: every check passes or fails at once.
# Prints one `ok <case>` line per case; exits non-zero on the first failed assertion.
set -e

here="$(cd "$(dirname "$0")" && pwd)"
wait_sh="$here/wait-until.sh"
command -v jq >/dev/null 2>&1 || { echo "test-wait-until.sh: jq is required" >&2; exit 2; }

fail() {
  echo "FAIL $1" >&2
  exit 1
}

run() {  # run <args...>: sets rc and out
  rc=0
  out="$(bash "$wait_sh" "$@" 2>/dev/null)" || rc=$?
}

run --interval 0 --timeout 5 -- true
[ "$rc" = 0 ] || fail "passed: exit $rc"
[ "$(printf '%s' "$out" | jq -r '.result')" = passed ] || fail "passed: $out"
echo "ok a check that exits 0 passes"

run --interval 0 --timeout 5 -- bash -c 'echo closed; exit 2'
[ "$rc" = 2 ] || fail "failed: exit $rc"
[ "$(printf '%s' "$out" | jq -c '[.result, .detail]')" = '["failed","closed"]' ] || fail "failed: $out"
echo "ok a check that exits 2 fails with its last line as detail"

for args in "--interval" "--interval x -- true" "--timeout -1 -- true" "--bogus -- true" "--interval 0"; do
  # shellcheck disable=SC2086  # each case is a word list on purpose
  run $args
  [ "$rc" = 64 ] || fail "usage error ($args): exit $rc, want 64"
  [ -z "$out" ] || fail "usage error ($args) printed a verdict: $out"
done
echo "ok a usage error exits 64, never a verdict's code"
