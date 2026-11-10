#!/bin/bash
# Offline test for failed-jobs.sh: a stub `gh` first on PATH returns canned JSON and logs per
# subcommand (applying the script's --jq filters with jq) and fails the calls GH_FAIL (a
# regex) matches.
# Prints one `ok <case>` line per case and exits non-zero on the first failed assertion.
set -e

here=$(cd "$(dirname "$0")" && pwd)
script="$here/failed-jobs.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/fix"
export GH_FIX="$work/fix" GH_LOG="$work/gh.log"

cat > "$work/bin/gh" <<'STUB'
#!/bin/bash
args="$*"
printf '%s\n' "$args" | tr '\n' ' ' >> "$GH_LOG"; echo >> "$GH_LOG"
if [ -n "${GH_FAIL:-}" ] && [[ "$args" =~ $GH_FAIL ]]; then
  echo "HTTP 403: Resource not accessible by integration (stub)" >&2; exit 1
fi
jqf=""; job=""; prev=""
for a in "$@"; do
  case "$prev" in --jq|-q) jqf=$a ;; --job) job=$a ;; esac
  prev=$a
done
emit() { if [ -n "$jqf" ]; then jq -rc "$jqf" "$1"; else cat "$1"; fi; }
case "$args" in
  "pr view "*) emit "$GH_FIX/pr-view.json" ;;
  "run list "*) emit "$GH_FIX/run-list.json" ;;
  "run view --job "*) [ -f "$GH_FIX/log-$job.txt" ] || { echo "log not found (stub)" >&2; exit 1; }
                      cat "$GH_FIX/log-$job.txt" ;;
  "run view "*) emit "$GH_FIX/run-$3.json" ;;
  *) echo "stub gh: unexpected call: $args" >&2; exit 97 ;;
esac
STUB
chmod +x "$work/bin/gh"
PATH="$work/bin:$PATH"

fail() { echo "FAIL $1" >&2; exit 1; }
ok() { echo "ok $1"; }
eq() { [ "$2" = "$3" ] || fail "$1: expected '$3', got '$2'"; }
run() { rc=0; : > "$GH_LOG"; out=$(env GH_FAIL="${GH_FAIL:-}" bash "$script" "$@" 2> "$work/stderr") || rc=$?; }

sha=0123456789abcdef0123456789abcdef01234567
echo "{\"headRefOid\":\"$sha\"}" > "$GH_FIX/pr-view.json"
# tests: newest run failed. lint: failed earlier, passed since. deploy: only cancelled runs.
cat > "$GH_FIX/run-list.json" <<JSON
[{"databaseId":100,"workflowName":"tests","conclusion":"failure","headSha":"$sha","createdAt":"2026-01-03T00:00:00Z","url":"https://github.com/o/r/actions/runs/100"},
 {"databaseId":90,"workflowName":"tests","conclusion":"success","headSha":"$sha","createdAt":"2026-01-01T00:00:00Z","url":"https://github.com/o/r/actions/runs/90"},
 {"databaseId":101,"workflowName":"lint","conclusion":"success","headSha":"$sha","createdAt":"2026-01-03T00:00:00Z","url":"https://github.com/o/r/actions/runs/101"},
 {"databaseId":91,"workflowName":"lint","conclusion":"failure","headSha":"$sha","createdAt":"2026-01-01T00:00:00Z","url":"https://github.com/o/r/actions/runs/91"},
 {"databaseId":102,"workflowName":"deploy","conclusion":"cancelled","headSha":"$sha","createdAt":"2026-01-03T00:00:00Z","url":"https://github.com/o/r/actions/runs/102"}]
JSON
cat > "$GH_FIX/run-100.json" <<'JSON'
{"jobs":[{"databaseId":555,"name":"phpunit","conclusion":"failure","url":"https://github.com/o/r/actions/runs/100/job/555"},
         {"databaseId":556,"name":"pint","conclusion":"success","url":"https://github.com/o/r/actions/runs/100/job/556"}]}
JSON
printf 'phpunit\tRun tests\t2026-01-03T00:00:01.0000000Z display_errors=On\n' > "$GH_FIX/log-555.txt"
printf 'phpunit\tRun tests\t2026-01-03T00:00:02.0000000Z   FAILED  Tests\\ExportTest > it exports\n' >> "$GH_FIX/log-555.txt"
printf 'phpunit\tRun tests\t2026-01-03T00:00:03.0000000Z Failed asserting that 2 matches expected 3.\n' >> "$GH_FIX/log-555.txt"
printf 'phpunit\tRun tests\t2026-01-03T00:00:04.0000000Z ##[error]Process completed with exit code 1.\n' >> "$GH_FIX/log-555.txt"

expect_runs() { # <case>: the same shape whichever way the runs were picked
  eq "$1 exit" "$rc" 0
  eq "$1 workflows" "$(echo "$out" | jq -c '[.[] | [.workflow, .run_id, .conclusion, (.jobs | length)]] | sort')" '[["deploy",null,"all_cancelled",0],["tests",100,"failure",1]]'
  eq "$1 run keys" "$(echo "$out" | jq -c '.[] | select(.workflow == "tests") | keys')" '["conclusion","head_sha","jobs","run_id","url","workflow"]'
  eq "$1 job" "$(echo "$out" | jq -c '.[] | select(.workflow == "tests") | .jobs[0] | [.id, .name, .url]')" '[555,"phpunit","https://github.com/o/r/actions/runs/100/job/555"]'
  eq "$1 first_errors" "$(echo "$out" | jq -c '.[] | select(.workflow == "tests") | .jobs[0].first_errors')" '["FAILED  Tests\\ExportTest > it exports","Failed asserting that 2 matches expected 3."]'
  eq "$1 log on disk" "$(echo "$out" | jq -r '.[] | select(.workflow == "tests") | .jobs[0].log')" "$work/logs/555.log"
  [ -s "$work/logs/555.log" ] || fail "$1: log file missing"
  eq "$1 head_sha" "$(echo "$out" | jq -r '.[] | select(.workflow == "tests") | .head_sha')" "$sha"
}

# --- a branch, as before ---
run main --out "$work/logs"
expect_runs "branch"
grep -q '^run list --branch main --status completed --limit 100 ' "$GH_LOG" || fail "branch: run list call"
[ "$(grep -c '^pr view' "$GH_LOG" || true)" = 0 ] || fail "branch: no PR read"
ok "branch"

# --- --pr pins to the PR's head commit ---
rm -rf "$work/logs"; run --pr 7 --out "$work/logs"
expect_runs "pr"
grep -q '^pr view 7 --json headRefOid' "$GH_LOG" || fail "pr: head read"
grep -q "^run list --commit $sha --status completed --limit 100 " "$GH_LOG" || fail "pr: run list pinned to the head commit"
[ "$(grep -c -- '--branch' "$GH_LOG" || true)" = 0 ] || fail "pr: must not filter by branch"
ok "--pr"

# --- --commit ---
rm -rf "$work/logs"; run --commit "$sha" --out "$work/logs" --lines 1
eq "commit exit" "$rc" 0
grep -q "^run list --commit $sha " "$GH_LOG" || fail "commit: run list call"
[ "$(grep -c '^pr view' "$GH_LOG" || true)" = 0 ] || fail "commit: no PR read"
eq "commit --lines" "$(echo "$out" | jq -c '.[] | select(.workflow == "tests") | .jobs[0].first_errors | length')" 1
ok "--commit"

# --- nothing failed ---
cp "$GH_FIX/run-list.json" "$work/run-list.all"
jq 'map(select(.workflowName == "lint"))' "$work/run-list.all" > "$GH_FIX/run-list.json"
run --pr 7 --out "$work/logs"
eq "green" "$rc $out" '0 []'
echo '[]' > "$GH_FIX/run-list.json"; run --pr 7 --out "$work/logs"
eq "no runs" "$rc $out" '0 []'
cp "$work/run-list.all" "$GH_FIX/run-list.json"
ok "green prints []"

# --- a job whose log gh cannot give is still listed ---
mv "$GH_FIX/log-555.txt" "$work/log-555.keep"; run --pr 7 --out "$work/logs2"
eq "no log" "$rc $(echo "$out" | jq -c '.[] | select(.workflow == "tests") | .jobs[0] | [.id, .first_errors]')" '0 [555,[]]'
mv "$work/log-555.keep" "$GH_FIX/log-555.txt"
ok "job without a log"

# --- a failing gh never reads as green ---
GH_FAIL='^run list' run --pr 7 --out "$work/logs"
[ "$rc" -ne 0 ] || fail "run list 403 must fail"; eq "run list 403 stdout" "$out" ""
GH_FAIL='^pr view' run --pr 7 --out "$work/logs"
[ "$rc" -ne 0 ] || fail "pr view 403 must fail"; eq "pr view 403 stdout" "$out" ""
[ "$(grep -c '^run list' "$GH_LOG" || true)" = 0 ] || fail "pr view 403: no run list after a failed PR read"
GH_FAIL='^run view 100' run --pr 7 --out "$work/logs"
[ "$rc" -ne 0 ] || fail "job list 403 must fail"; eq "job list 403 stdout" "$out" ""
GH_FAIL='^run list' run main --out "$work/logs"
[ "$rc" -ne 0 ] || fail "branch run list 403 must fail"
ok "failing gh exits non-zero"

# --- usage ---
run; eq "no args" "$rc" 2
run main --pr 7; eq "branch and --pr" "$rc" 2
run --pr 7 --commit "$sha"; eq "--pr and --commit" "$rc" 2
run --pr abc; eq "--pr not a number" "$rc" 2
run --commit abc123; eq "--commit short sha" "$rc" 2
run main extra; eq "two branches" "$rc" 2
run main --bogus; eq "unknown flag" "$rc" 2
run main --lines x; eq "--lines not a number" "$rc" 2
eq "usage errors call nothing" "$(wc -l < "$GH_LOG" | tr -d ' ')" 0
ok "usage errors exit 2"
