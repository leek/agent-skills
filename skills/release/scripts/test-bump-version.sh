#!/bin/bash
# Offline test for bump-version.sh. Fixtures live in mktemp -d; nothing touches a real repo.
# Usage: bash test-bump-version.sh      (prints one "ok <case>" line per case; exits 1 on the first failure)
set -e
set -o pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/bump-version.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
cd "$T"

fail() { echo "FAIL: $1" >&2; exit 1; }
ok() { echo "ok $1"; }

# run <args...>: stdout in $out, exit code in $code
run() {
  code=0
  out="$(bash "$SCRIPT" "$@" 2>"$T/stderr")" || code=$?
}

printf '{"name": "x", "version": "1.2.3"}\n' > a.json
printf '{"metadata": {"version": "1.2.3"}}\n' > b.json
run 1.2.3 1.3.0 a.json b.json
[ "$code" -eq 0 ] || fail "two files: exit $code"
[ "$(printf '%s' "$out" | jq -c .)" = '{"changed":["a.json","b.json"]}' ] || fail "two files: output $out"
grep -q '"version": "1.3.0"' a.json || fail "two files: a.json not bumped"
grep -q '"version": "1.3.0"' b.json || fail "two files: b.json not bumped"
ok "bumps every file and lists them"

printf '{"version": "1.2.3"}\n' > good.json
printf '{"version": "9.9.9"}\n' > nomatch.json
before="$(cat good.json)"
run 1.2.3 1.2.4 good.json nomatch.json
[ "$code" -eq 1 ] || fail "no match: exit $code, want 1"
[ "$(cat good.json)" = "$before" ] || fail "no match: good.json was written"
[ "$(printf '%s' "$out" | jq -c .)" = '{"changed":[],"refused":[{"path":"nomatch.json","matches":0}]}' ] || fail "no match: output $out"
ok "refuses when one of two files has no match and leaves the other untouched"

printf '{"version": "1.2.3", "dependencies": {"left-pad": "1.2.3"}}\n' > twice.json
before="$(cat twice.json)"
run 1.2.3 1.2.4 twice.json good.json
[ "$code" -eq 1 ] || fail "two matches: exit $code, want 1"
[ "$(cat twice.json)" = "$before" ] || fail "two matches: twice.json was written"
grep -q '"1.2.3"' good.json || fail "two matches: good.json was written"
[ "$(printf '%s' "$out" | jq -r '.refused[0].matches')" = 2 ] || fail "two matches: output $out"
ok "refuses a file with two matches"

run 1.2.3 1.2.4 good.json missing.json
[ "$code" -eq 1 ] || fail "missing file: exit $code, want 1"
grep -q '"1.2.3"' good.json || fail "missing file: good.json was written"
ok "refuses a missing file"

printf 'lib 11.2.3\nlib 1.2.30\nlib 1.2.3.4\nversion v1.2.3\n' > VERSION
run 1.2.3 1.2.4 VERSION
[ "$code" -eq 0 ] || fail "standalone: exit $code"
[ "$(cat VERSION)" = "$(printf 'lib 11.2.3\nlib 1.2.30\nlib 1.2.3.4\nversion v1.2.4')" ] || fail "standalone: $(cat VERSION)"
ok "matches the version only when it stands alone"

printf 'a1b2c3 and 1.2.3\n' > dots.txt
run 1.2.3 2.0.0 dots.txt
[ "$code" -eq 0 ] && [ "$(cat dots.txt)" = 'a1b2c3 and 2.0.0' ] || fail "literal dots: $(cat dots.txt)"
printf '1x2x3\n' > regex.txt
run 1.2.3 2.0.0 regex.txt
[ "$code" -eq 1 ] || fail "literal dots: 1x2x3 matched as a regex"
ok "treats the version as a literal string"

chmod 640 good.json
run 1.2.3 1.2.4 good.json
[ "$code" -eq 0 ] || fail "mode: exit $code"
[ "$(ls -l good.json | cut -c1-10)" = "-rw-r-----" ] || fail "mode: $(ls -l good.json)"
ok "keeps the file mode"

run 1.2.3 1.2.4
[ "$code" -eq 2 ] || fail "usage (no file): exit $code, want 2"
run 1.2.4 1.2.4 good.json
[ "$code" -eq 2 ] || fail "usage (old = new): exit $code, want 2"
grep -q '"1.2.4"' good.json || fail "usage: good.json changed"
ok "usage errors exit 2"
